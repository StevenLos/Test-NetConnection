# Test-NetConnection Plan Package

This package contains one PowerShell script, example input/output files, project folders, and reusable target-device CSV templates.

## Scope

The script uses `Test-NetConnection` only. It supports:

- TCP port tests using `Test-NetConnection -Port`
- ICMP reachability tests using `Test-NetConnection` without `-Port`
- Target-focused CSV input validation before network checks run
- Optional summary CSV output
- Optional target-hostname testing with `-UseTargetServerName`

The bundled example focuses on Active Directory line-of-sight testing, but the script can run any target-device plan that uses TCP ports and ICMP.

Run the same target list from each source server or source network location that needs validation. The input CSV does not need source server details.

The generated inputs exclude UDP-only rows and port-range rows because `Test-NetConnection` does not test UDP and does not accept port ranges.

## Files

- `Test-NetConnectionPlan.ps1` - runner script
- `RUNBOOK.md` - simple end-user operating instructions
- `01-examples/` - target-list example input
- `02-templates/` - starter CSV templates
- `03-projects/` - suggested location for real user projects
- `04-tests/` - Pester tests

## Input CSV Columns

Required columns:

```csv
TargetServerName,TargetIpAddress,Protocol,Port
```

Optional reporting/context columns:

```csv
TestId,TargetDomain,Service,Purpose
```

The richer packaged target lists include optional columns for readability and output grouping. Supported `Protocol` values are `TCP` and `ICMP`. TCP rows require a numeric `Port` from 1 through 65535. ICMP rows must have a blank `Port`.

## Examples

Validate the included example CSV:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\Test-NetConnectionPlan.ps1 `
  -InputCsv .\01-examples\input\example-target-ad-line-of-sight.csv `
  -ValidateOnly
```

Run all target rows from the current source server:

```powershell
.\Test-NetConnectionPlan.ps1 `
  -InputCsv .\01-examples\input\example-target-ad-line-of-sight.csv `
  -OutputCsv .\results.csv
```

Write both detail and grouped summary output:

```powershell
.\Test-NetConnectionPlan.ps1 `
  -InputCsv .\01-examples\input\example-target-ad-line-of-sight.csv `
  -OutputCsv .\results.csv `
  -SummaryCsv .\summary.csv
```

Use target DNS names instead of target IP addresses:

```powershell
.\Test-NetConnectionPlan.ps1 `
  -InputCsv .\01-examples\input\example-target-ad-line-of-sight.csv `
  -OutputCsv .\results-name-test.csv `
  -UseTargetServerName
```

## Output

Detail CSV columns:

```csv
TestId,LocalComputerName,TargetDomain,TargetServerName,TargetIpAddress,Protocol,Port,Service,Status,TcpTestSucceeded,PingSucceeded,SourceAddress,RemoteAddress,ResolvedAddresses,StartedAt,DurationMs,ErrorMessage
```

Summary CSV columns:

```csv
TargetDomain,TargetServerName,Protocol,Port,Service,Status,Count
```

## Exit Codes

| Exit code | Meaning |
|---|---|
| `0` | Script completed and all tests passed. |
| `1` | Script completed but one or more tests failed or were skipped. |
| `2` | Input validation or runtime error occurred. |

Run the relevant target CSV from each source server or source network location. Results are exported as CSV.
