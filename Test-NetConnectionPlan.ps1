<#
.SYNOPSIS
Runs a CSV-based Test-NetConnection plan and exports results to CSV.

.DESCRIPTION
Input CSV rows define target devices, protocols, and ports. This script intentionally supports
only what Test-NetConnection can test directly:
  - TCP port checks
  - ICMP reachability checks

UDP rows are not included in the generated input files because Test-NetConnection does not
perform UDP connection tests.

Run the script from each source server or source network location that needs to be validated.

Typical use:
  .\Test-NetConnectionPlan.ps1 -InputCsv .\01-examples\input\example-target-ad-line-of-sight.csv -OutputCsv .\results.csv

Validate the input plan without running network checks:
  .\Test-NetConnectionPlan.ps1 -InputCsv .\01-examples\input\example-target-ad-line-of-sight.csv -ValidateOnly
#>

[CmdletBinding()]
param(
    [string]$InputCsv,

    [string]$OutputCsv,

    [string]$SummaryCsv,

    [switch]$ValidateOnly,

    [switch]$WhatIfPlan,

    [switch]$UseTargetServerName,

    [int]$InformationLevelTimeoutSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RequiredColumns = @(
    'TargetServerName',
    'TargetIpAddress',
    'Protocol',
    'Port'
)

function Get-CsvValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Row.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return ''
    }

    return "$($property.Value)"
}

function Get-ObjectValue {
    param(
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Import-TestPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'InputCsv is required.'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Input CSV not found: $Path"
    }

    $rows = @(Import-Csv -LiteralPath $Path)
    $headerLine = Get-Content -LiteralPath $Path -TotalCount 1
    $columns = @()

    if (-not [string]::IsNullOrWhiteSpace($headerLine)) {
        $columns = @(
            $headerLine.TrimStart([char]0xFEFF) -split ',' |
                ForEach-Object { $_.Trim().Trim('"') }
        )
    }
    elseif ($rows.Count -gt 0) {
        $columns = @($rows[0].PSObject.Properties.Name)
    }

    [pscustomobject]@{
        Rows = $rows
        Columns = $columns
    }
}

function Test-TestPlanSchema {
    param(
        [object[]]$Rows,

        [string[]]$Columns,

        [switch]$UseTargetServerName
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $rowList = @($Rows)
    $columnList = @($Columns)
    $missingColumns = @($script:RequiredColumns | Where-Object { $columnList -notcontains $_ })

    foreach ($missingColumn in $missingColumns) {
        $errors.Add("Missing required column: $missingColumn") | Out-Null
    }

    if ($missingColumns.Count -gt 0) {
        return [pscustomobject]@{
            IsValid = $false
            Errors = @($errors)
        }
    }

    if ($rowList.Count -eq 0) {
        $errors.Add('Input CSV does not contain any test rows.') | Out-Null
    }

    $seenTestIds = @{}
    $rowNumber = 1

    foreach ($row in $rowList) {
        $rowNumber++
        $testId = (Get-CsvValue -Row $row -Name 'TestId').Trim()
        $targetIpAddress = (Get-CsvValue -Row $row -Name 'TargetIpAddress').Trim()
        $targetServerName = (Get-CsvValue -Row $row -Name 'TargetServerName').Trim()
        $protocol = (Get-CsvValue -Row $row -Name 'Protocol').Trim().ToUpperInvariant()
        $port = (Get-CsvValue -Row $row -Name 'Port').Trim()
        $rowLabel = if ([string]::IsNullOrWhiteSpace($testId)) { "row $rowNumber" } else { "row $rowNumber ($testId)" }

        if (-not [string]::IsNullOrWhiteSpace($testId)) {
            $testIdKey = $testId.ToUpperInvariant()
            if ($seenTestIds.ContainsKey($testIdKey)) {
                $errors.Add("Duplicate TestId '$testId' found on rows $($seenTestIds[$testIdKey]) and $rowNumber.") | Out-Null
            }
            else {
                $seenTestIds[$testIdKey] = $rowNumber
            }
        }

        if ([string]::IsNullOrWhiteSpace($targetServerName)) {
            $errors.Add("$rowLabel has blank TargetServerName.") | Out-Null
        }

        if ([string]::IsNullOrWhiteSpace($targetIpAddress)) {
            $errors.Add("$rowLabel has blank TargetIpAddress.") | Out-Null
        }

        if ($protocol -eq 'TCP') {
            if ([string]::IsNullOrWhiteSpace($port)) {
                $errors.Add("$rowLabel is TCP but has blank Port.") | Out-Null
            }
            else {
                $portNumber = 0
                if (-not [int]::TryParse($port, [ref]$portNumber)) {
                    $errors.Add("$rowLabel is TCP but Port '$port' is not numeric.") | Out-Null
                }
                elseif ($portNumber -lt 1 -or $portNumber -gt 65535) {
                    $errors.Add("$rowLabel is TCP but Port '$port' is outside the valid range 1-65535.") | Out-Null
                }
            }
        }
        elseif ($protocol -eq 'ICMP') {
            if (-not [string]::IsNullOrWhiteSpace($port)) {
                $errors.Add("$rowLabel is ICMP but Port '$port' is not blank.") | Out-Null
            }
        }
        else {
            if ([string]::IsNullOrWhiteSpace($protocol)) {
                $errors.Add("$rowLabel has blank Protocol.") | Out-Null
            }
            else {
                $errors.Add("$rowLabel has unsupported Protocol '$protocol'. Supported values are TCP and ICMP.") | Out-Null
            }
        }
    }

    [pscustomobject]@{
        IsValid = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}

function Get-UniqueNonBlankValue {
    param(
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    @(
        @($Rows) |
            ForEach-Object { (Get-CsvValue -Row $_ -Name $Name).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )
}

function Format-ValuePreview {
    param(
        [string[]]$Values,

        [int]$Limit = 20
    )

    $valueList = @($Values)
    if ($valueList.Count -eq 0) {
        return '(none)'
    }

    if ($valueList.Count -le $Limit) {
        return ($valueList -join '; ')
    }

    return "$(($valueList | Select-Object -First $Limit) -join '; '); ... (+$($valueList.Count - $Limit) more)"
}

function New-TestPlanReport {
    param(
        [object[]]$Rows
    )

    $rowList = @($Rows)
    $tcpRows = @($rowList | Where-Object { (Get-CsvValue -Row $_ -Name 'Protocol').Trim() -ieq 'TCP' })
    $icmpRows = @($rowList | Where-Object { (Get-CsvValue -Row $_ -Name 'Protocol').Trim() -ieq 'ICMP' })
    $unsupportedRows = @($rowList | Where-Object {
        $protocol = (Get-CsvValue -Row $_ -Name 'Protocol').Trim()
        -not [string]::IsNullOrWhiteSpace($protocol) -and
            $protocol -ine 'TCP' -and
            $protocol -ine 'ICMP'
    })
    $targetServers = @(Get-UniqueNonBlankValue -Rows $rowList -Name 'TargetServerName')

    [pscustomobject]@{
        TotalRows = $rowList.Count
        TcpRows = $tcpRows.Count
        IcmpRows = $icmpRows.Count
        UnsupportedRows = $unsupportedRows.Count
        TargetServers = $targetServers
    }
}

function Write-TestPlanReport {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report
    )

    Write-Host 'Test plan validation summary'
    Write-Host "Total rows: $($Report.TotalRows)"
    Write-Host "TCP rows: $($Report.TcpRows)"
    Write-Host "ICMP rows: $($Report.IcmpRows)"
    Write-Host "Unsupported rows: $($Report.UnsupportedRows)"
    Write-Host "Distinct target servers ($($Report.TargetServers.Count)): $(Format-ValuePreview -Values $Report.TargetServers)"
}

function Convert-TncOutput {
    param(
        [object]$Tnc
    )

    $tcpSucceeded = Get-ObjectValue -Object $Tnc -Name 'TcpTestSucceeded'
    $pingSucceeded = Get-ObjectValue -Object $Tnc -Name 'PingSucceeded'
    $remoteAddress = Get-ObjectValue -Object $Tnc -Name 'RemoteAddress'
    $resolvedAddresses = Get-ObjectValue -Object $Tnc -Name 'ResolvedAddresses'
    $sourceAddress = Get-ObjectValue -Object $Tnc -Name 'SourceAddress'

    [pscustomobject]@{
        TcpTestSucceeded = if ($null -eq $tcpSucceeded) { $null } else { [bool]$tcpSucceeded }
        PingSucceeded = if ($null -eq $pingSucceeded) { $null } else { [bool]$pingSucceeded }
        RemoteAddress = if ($null -eq $remoteAddress) { $null } else { "$remoteAddress" }
        ResolvedAddresses = if ($null -eq $resolvedAddresses) { $null } else { @($resolvedAddresses) -join ';' }
        SourceAddress = if ($null -eq $sourceAddress) { $null } else { "$sourceAddress" }
    }
}

function Get-LocalComputerName {
    if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) {
        return $env:COMPUTERNAME
    }

    if (-not [string]::IsNullOrWhiteSpace($env:HOSTNAME)) {
        return $env:HOSTNAME
    }

    return [System.Net.Dns]::GetHostName()
}

function Invoke-TncTestRow {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Test,

        [Parameter(Mandatory = $true)]
        [string]$LocalComputerName,

        [switch]$UseTargetServerName
    )

    $protocol = (Get-CsvValue -Row $Test -Name 'Protocol').Trim().ToUpperInvariant()
    $targetIpAddress = (Get-CsvValue -Row $Test -Name 'TargetIpAddress').Trim()
    $targetServerName = (Get-CsvValue -Row $Test -Name 'TargetServerName').Trim()
    $target = if ($UseTargetServerName) { $targetServerName } else { $targetIpAddress }
    $port = (Get-CsvValue -Row $Test -Name 'Port').Trim()
    $started = Get-Date
    $status = 'Fail'
    $errorMessage = $null
    $remoteAddress = $null
    $resolvedAddresses = $null
    $tcpSucceeded = $null
    $pingSucceeded = $null
    $sourceAddress = $null

    try {
        if ([string]::IsNullOrWhiteSpace($target)) {
            throw 'Test target is blank.'
        }

        if ($protocol -eq 'TCP') {
            $portNumber = [int]$port
            $tnc = Test-NetConnection -ComputerName $target -Port $portNumber -InformationLevel Detailed -WarningAction SilentlyContinue
            $details = Convert-TncOutput -Tnc $tnc
            $tcpSucceeded = $details.TcpTestSucceeded
            $pingSucceeded = $details.PingSucceeded
            $remoteAddress = $details.RemoteAddress
            $resolvedAddresses = $details.ResolvedAddresses
            $sourceAddress = $details.SourceAddress
            $status = if ($tcpSucceeded -eq $true) { 'Pass' } else { 'Fail' }
        }
        elseif ($protocol -eq 'ICMP') {
            $tnc = Test-NetConnection -ComputerName $target -InformationLevel Detailed -WarningAction SilentlyContinue
            $details = Convert-TncOutput -Tnc $tnc
            $tcpSucceeded = $details.TcpTestSucceeded
            $pingSucceeded = $details.PingSucceeded
            $remoteAddress = $details.RemoteAddress
            $resolvedAddresses = $details.ResolvedAddresses
            $sourceAddress = $details.SourceAddress
            $status = if ($pingSucceeded -eq $true) { 'Pass' } else { 'Fail' }
        }
        else {
            $status = 'Skipped'
            $errorMessage = "Unsupported protocol for this script: $protocol"
        }
    }
    catch {
        $status = 'Error'
        $errorMessage = $_.Exception.Message
    }

    $ended = Get-Date
    $durationMs = [int](New-TimeSpan -Start $started -End $ended).TotalMilliseconds

    [pscustomobject]@{
        TestId = Get-CsvValue -Row $Test -Name 'TestId'
        LocalComputerName = $LocalComputerName
        TargetDomain = Get-CsvValue -Row $Test -Name 'TargetDomain'
        TargetServerName = Get-CsvValue -Row $Test -Name 'TargetServerName'
        TargetIpAddress = Get-CsvValue -Row $Test -Name 'TargetIpAddress'
        Protocol = Get-CsvValue -Row $Test -Name 'Protocol'
        Port = Get-CsvValue -Row $Test -Name 'Port'
        Service = Get-CsvValue -Row $Test -Name 'Service'
        Status = $status
        TcpTestSucceeded = $tcpSucceeded
        PingSucceeded = $pingSucceeded
        SourceAddress = $sourceAddress
        RemoteAddress = $remoteAddress
        ResolvedAddresses = $resolvedAddresses
        StartedAt = $started.ToString('s')
        DurationMs = $durationMs
        ErrorMessage = $errorMessage
    }
}

function Export-TestResults {
    param(
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }

    @($Rows) | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
}

function New-TestSummary {
    param(
        [object[]]$Results
    )

    @($Results) |
        Group-Object -Property TargetDomain, TargetServerName, Protocol, Port, Service, Status |
        Sort-Object Name |
        ForEach-Object {
            $first = $_.Group[0]
            [pscustomobject]@{
                TargetDomain = $first.TargetDomain
                TargetServerName = $first.TargetServerName
                Protocol = $first.Protocol
                Port = $first.Port
                Service = $first.Service
                Status = $first.Status
                Count = $_.Count
            }
        }
}

function Write-ValidationErrors {
    param(
        [string[]]$Errors
    )

    foreach ($validationError in @($Errors)) {
        Write-Error -Message $validationError -ErrorAction Continue
    }
}

function Invoke-NetConnectionPlanMain {
    [CmdletBinding()]
    param(
        [string]$InputCsv,

        [string]$OutputCsv,

        [string]$SummaryCsv,

        [switch]$ValidateOnly,

        [switch]$WhatIfPlan,

        [switch]$UseTargetServerName,

        [int]$InformationLevelTimeoutSeconds = 5
    )

    try {
        $null = $InformationLevelTimeoutSeconds
        $validateMode = $ValidateOnly -or $WhatIfPlan
        $testPlan = Import-TestPlan -Path $InputCsv
        $validation = Test-TestPlanSchema -Rows $testPlan.Rows -Columns $testPlan.Columns -UseTargetServerName:$UseTargetServerName
        $selectedTests = @($testPlan.Rows)

        if ($validateMode) {
            $report = New-TestPlanReport -Rows $selectedTests
            Write-TestPlanReport -Report $report

            if (-not $validation.IsValid) {
                Write-ValidationErrors -Errors $validation.Errors
                return 2
            }

            return 0
        }

        if (-not $validation.IsValid) {
            Write-ValidationErrors -Errors $validation.Errors
            return 2
        }

        if ([string]::IsNullOrWhiteSpace($OutputCsv)) {
            throw 'OutputCsv is required unless -ValidateOnly or -WhatIfPlan is specified.'
        }

        $results = New-Object System.Collections.Generic.List[object]
        $total = $selectedTests.Count
        $index = 0
        $localComputerName = Get-LocalComputerName

        foreach ($test in $selectedTests) {
            $index++
            $protocol = (Get-CsvValue -Row $test -Name 'Protocol').Trim().ToUpperInvariant()
            $target = if ($UseTargetServerName) {
                (Get-CsvValue -Row $test -Name 'TargetServerName').Trim()
            }
            else {
                (Get-CsvValue -Row $test -Name 'TargetIpAddress').Trim()
            }
            $port = (Get-CsvValue -Row $test -Name 'Port').Trim()

            Write-Progress -Activity 'Running Test-NetConnection checks' -Status "$index of ${total}: $target $protocol $port" -PercentComplete (($index / [Math]::Max($total, 1)) * 100)

            $results.Add((Invoke-TncTestRow -Test $test -LocalComputerName $localComputerName -UseTargetServerName:$UseTargetServerName)) | Out-Null
        }

        Write-Progress -Activity 'Running Test-NetConnection checks' -Completed

        Export-TestResults -Rows $results -Path $OutputCsv
        Write-Host "Wrote $($results.Count) result rows to $OutputCsv"

        if (-not [string]::IsNullOrWhiteSpace($SummaryCsv)) {
            $summaryRows = @(New-TestSummary -Results $results)
            Export-TestResults -Rows $summaryRows -Path $SummaryCsv
            Write-Host "Wrote $($summaryRows.Count) summary rows to $SummaryCsv"
        }

        $statusSummary = $results |
            Group-Object Status |
            Sort-Object Name |
            ForEach-Object { [pscustomobject]@{ Status = $_.Name; Count = $_.Count } }

        $statusSummary | Format-Table -AutoSize | Out-Host

        if (@($results | Where-Object { $_.Status -eq 'Error' }).Count -gt 0) {
            return 2
        }

        if (@($results | Where-Object { $_.Status -eq 'Fail' -or $_.Status -eq 'Skipped' }).Count -gt 0) {
            return 1
        }

        return 0
    }
    catch {
        Write-Error -Message $_.Exception.Message -ErrorAction Continue
        return 2
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $exitCode = Invoke-NetConnectionPlanMain @PSBoundParameters
    exit $exitCode
}
