BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'Test-NetConnectionPlan.ps1')

    $script:TestColumns = @(
        'TargetServerName',
        'TargetIpAddress',
        'Protocol',
        'Port'
    )

    $script:RichTestColumns = @(
        'TestId',
        'TargetDomain',
        'TargetServerName',
        'TargetIpAddress',
        'Protocol',
        'Port',
        'Service',
        'Purpose'
    )

    $script:ResultColumns = @(
        'TestId',
        'LocalComputerName',
        'TargetDomain',
        'TargetServerName',
        'TargetIpAddress',
        'Protocol',
        'Port',
        'Service',
        'Status',
        'TcpTestSucceeded',
        'PingSucceeded',
        'SourceAddress',
        'RemoteAddress',
        'ResolvedAddresses',
        'StartedAt',
        'DurationMs',
        'ErrorMessage'
    )

    function New-TestRow {
        param(
            [string]$TestId = 'TEST001',
            [string]$TargetServerName = 'localhost',
            [string]$TargetIpAddress = '127.0.0.1',
            [string]$Protocol = 'ICMP',
            [string]$Port = '',
            [string]$Service = 'ICMP'
        )

        [pscustomobject]@{
            TestId = $TestId
            TargetDomain = 'example.local'
            TargetServerName = $TargetServerName
            TargetIpAddress = $TargetIpAddress
            Protocol = $Protocol
            Port = $Port
            Service = $Service
            Purpose = 'Unit test fixture'
        }
    }

    function Write-TestCsv {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path,

            [Parameter(Mandatory = $true)]
            [string[]]$Lines
        )

        Set-Content -LiteralPath $Path -Value $Lines -Encoding UTF8
    }

    if (-not (Get-Command Test-NetConnection -ErrorAction SilentlyContinue)) {
        function global:Test-NetConnection {
            [CmdletBinding()]
            param(
                [string]$ComputerName,
                [int]$Port,
                [string]$InformationLevel
            )
        }
    }
}

Describe 'Invoke-TncTestRow' {
    It 'returns expected columns for a passing TCP row' {
        Mock -CommandName Test-NetConnection -MockWith {
            [pscustomobject]@{
                TcpTestSucceeded = $true
                PingSucceeded = $true
                RemoteAddress = '127.0.0.1'
                ResolvedAddresses = @('127.0.0.1')
                SourceAddress = '127.0.0.1'
            }
        }

        $row = New-TestRow -Protocol 'TCP' -Port '445' -Service 'SMB'
        $result = Invoke-TncTestRow -Test $row -LocalComputerName 'LOCAL'

        $result.Status | Should -Be 'Pass'
        $result.TcpTestSucceeded | Should -BeTrue
        foreach ($column in $script:ResultColumns) {
            $result.PSObject.Properties.Name | Should -Contain $column
        }
        Should -Invoke -CommandName Test-NetConnection -Times 1 -Exactly
    }

    It 'returns expected columns for a passing ICMP row' {
        Mock -CommandName Test-NetConnection -MockWith {
            [pscustomobject]@{
                TcpTestSucceeded = $null
                PingSucceeded = $true
                RemoteAddress = '127.0.0.1'
                ResolvedAddresses = @('127.0.0.1')
                SourceAddress = '127.0.0.1'
            }
        }

        $row = New-TestRow -Protocol 'ICMP' -Port '' -Service 'ICMP'
        $result = Invoke-TncTestRow -Test $row -LocalComputerName 'LOCAL'

        $result.Status | Should -Be 'Pass'
        $result.PingSucceeded | Should -BeTrue
        foreach ($column in $script:ResultColumns) {
            $result.PSObject.Properties.Name | Should -Contain $column
        }
        Should -Invoke -CommandName Test-NetConnection -Times 1 -Exactly
    }

    It 'uses TargetServerName when requested' {
        Mock -CommandName Test-NetConnection -MockWith {
            [pscustomobject]@{
                TcpTestSucceeded = $null
                PingSucceeded = $true
                RemoteAddress = '127.0.0.1'
                ResolvedAddresses = @('127.0.0.1')
                SourceAddress = '127.0.0.1'
            }
        } -ParameterFilter { $ComputerName -eq 'localhost' }

        $row = New-TestRow -Protocol 'ICMP' -TargetServerName 'localhost' -TargetIpAddress '192.0.2.10'
        $result = Invoke-TncTestRow -Test $row -LocalComputerName 'LOCAL' -UseTargetServerName

        $result.Status | Should -Be 'Pass'
        Should -Invoke -CommandName Test-NetConnection -Times 1 -Exactly -ParameterFilter { $ComputerName -eq 'localhost' }
    }
}

Describe 'Test-TestPlanSchema' {
    It 'fails validation when a required column is missing' {
        $path = Join-Path 'TestDrive:' 'missing-column.csv'
        $lines = @(
            'TargetServerName,Protocol,Port',
            'localhost,ICMP,'
        )
        Write-TestCsv -Path $path -Lines $lines

        $plan = Import-TestPlan -Path $path
        $validation = Test-TestPlanSchema -Rows $plan.Rows -Columns $plan.Columns

        $validation.IsValid | Should -BeFalse
        ($validation.Errors -join "`n") | Should -Match 'Missing required column: TargetIpAddress'
    }

    It 'accepts the absolute technical minimum columns' {
        $path = Join-Path 'TestDrive:' 'minimum.csv'
        $lines = @(
            'TargetServerName,TargetIpAddress,Protocol,Port',
            'localhost,127.0.0.1,ICMP,',
            'localhost,127.0.0.1,TCP,445'
        )
        Write-TestCsv -Path $path -Lines $lines

        $plan = Import-TestPlan -Path $path
        $validation = Test-TestPlanSchema -Rows $plan.Rows -Columns $plan.Columns

        $validation.IsValid | Should -BeTrue
    }

    It 'accepts richer target rows without source metadata columns' {
        $row = New-TestRow

        $validation = Test-TestPlanSchema -Rows @($row) -Columns $script:RichTestColumns

        $validation.IsValid | Should -BeTrue
    }

    It 'accepts neutral extra columns as additional context' {
        $row = New-TestRow
        $row | Add-Member -NotePropertyName Environment -NotePropertyValue 'Test'
        $row | Add-Member -NotePropertyName OwnerTeam -NotePropertyValue 'Infrastructure'
        $columns = @('Environment', 'OwnerTeam') + $script:RichTestColumns

        $validation = Test-TestPlanSchema -Rows @($row) -Columns $columns

        $validation.IsValid | Should -BeTrue
    }

    It 'fails validation for an unsupported protocol' {
        $row = New-TestRow -Protocol 'UDP'

        $validation = Test-TestPlanSchema -Rows @($row) -Columns $script:RichTestColumns

        $validation.IsValid | Should -BeFalse
        ($validation.Errors -join "`n") | Should -Match "unsupported Protocol 'UDP'"
    }

    It 'fails validation for a non-numeric TCP port' {
        $row = New-TestRow -Protocol 'TCP' -Port 'ldap'

        $validation = Test-TestPlanSchema -Rows @($row) -Columns $script:RichTestColumns

        $validation.IsValid | Should -BeFalse
        ($validation.Errors -join "`n") | Should -Match "Port 'ldap' is not numeric"
    }

    It 'fails validation for duplicate TestId values' {
        $rows = @(
            (New-TestRow -TestId 'TEST001'),
            (New-TestRow -TestId 'test001')
        )

        $validation = Test-TestPlanSchema -Rows $rows -Columns $script:RichTestColumns

        $validation.IsValid | Should -BeFalse
        ($validation.Errors -join "`n") | Should -Match "Duplicate TestId 'test001'"
    }
}

Describe 'Plan helpers' {
    It 'creates the output directory before exporting results' {
        $path = Join-Path 'TestDrive:' 'nested/results.csv'
        $row = [pscustomobject]@{
            TargetDomain = 'example.local'
            TargetServerName = 'localhost'
            Protocol = 'ICMP'
            Port = ''
            Service = 'ICMP'
            Status = 'Pass'
        }

        Export-TestResults -Rows @($row) -Path $path

        Test-Path -LiteralPath $path | Should -BeTrue
    }
}

Describe 'Invoke-NetConnectionPlanMain' {
    It 'writes detail and summary CSVs and returns success code' {
        Mock -CommandName Test-NetConnection -MockWith {
            [pscustomobject]@{
                TcpTestSucceeded = $true
                PingSucceeded = $true
                RemoteAddress = '127.0.0.1'
                ResolvedAddresses = @('127.0.0.1')
                SourceAddress = '127.0.0.1'
            }
        }

        $input = Join-Path 'TestDrive:' 'plan.csv'
        $output = Join-Path 'TestDrive:' 'out/results.csv'
        $summary = Join-Path 'TestDrive:' 'out/summary.csv'
        $lines = @(
            ($script:TestColumns -join ','),
            'localhost,127.0.0.1,TCP,445'
        )
        Write-TestCsv -Path $input -Lines $lines

        $exitCode = Invoke-NetConnectionPlanMain -InputCsv $input -OutputCsv $output -SummaryCsv $summary

        $exitCode | Should -Be 0
        Test-Path -LiteralPath $output | Should -BeTrue
        Test-Path -LiteralPath $summary | Should -BeTrue

        $detailRows = @(Import-Csv -LiteralPath $output)
        $summaryRows = @(Import-Csv -LiteralPath $summary)

        $detailRows.Count | Should -Be 1
        $detailRows[0].Status | Should -Be 'Pass'
        $summaryRows.Count | Should -Be 1
        $summaryRows[0].Status | Should -Be 'Pass'
        $summaryRows[0].Count | Should -Be '1'
    }
}
