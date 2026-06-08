# Test-NetConnection Plan Runbook

## What This Does

This package runs a CSV-based `Test-NetConnection` plan from the current machine.

Use it to test whether one source server or source network location can reach target servers or devices over TCP ports and ICMP.

The script does not remote into other servers. Run the same plan separately from each source server that needs validation.

## Folder Map

```text
Test-NetConnectionPlan.ps1        Main script
01-examples/                      Finished sample input and output
02-templates/                     Project and CSV templates
03-projects/                      Place real project files here
04-tests/                         Script tests
```

## Input CSV Rules

Required columns:

```csv
TargetServerName,TargetIpAddress,Protocol,Port
```

Optional columns:

```csv
TestId,TargetDomain,Service,Purpose
```

Use `TCP` or `ICMP` for `Protocol`.

- TCP rows need a numeric `Port`.
- ICMP rows must leave `Port` blank.
- The CSV should list target devices only. Do not add source server details.
- UDP and port ranges are not supported by `Test-NetConnection`.

## Basic Workflow

Open PowerShell from the package root:

```powershell
cd C:\Path\To\Test-NetConnection
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Create a project folder:

```powershell
Copy-Item .\02-templates\my-project-template .\03-projects\my-project -Recurse
```

Copy a CSV template into the project:

```powershell
Copy-Item ".\02-templates\template CSVs\ad-line-of-sight-template.csv" .\03-projects\my-project\input\test-plan.csv
```

Edit `.\03-projects\my-project\input\test-plan.csv` with the real target server names, target IP addresses, protocols, and ports.

Validate the CSV before running network checks:

```powershell
.\Test-NetConnectionPlan.ps1 `
  -InputCsv .\03-projects\my-project\input\test-plan.csv `
  -ValidateOnly
```

Run the test plan:

```powershell
.\Test-NetConnectionPlan.ps1 `
  -InputCsv .\03-projects\my-project\input\test-plan.csv `
  -OutputCsv .\03-projects\my-project\output\results.csv `
  -SummaryCsv .\03-projects\my-project\output\summary.csv
```

Repeat the run command from each source server or source network location that needs to be tested.

## Optional DNS Name Test

By default, the script tests `TargetIpAddress`.

Use `-UseTargetServerName` when you want the test to use `TargetServerName` instead:

```powershell
.\Test-NetConnectionPlan.ps1 `
  -InputCsv .\03-projects\my-project\input\test-plan.csv `
  -OutputCsv .\03-projects\my-project\output\results-name-test.csv `
  -SummaryCsv .\03-projects\my-project\output\summary-name-test.csv `
  -UseTargetServerName
```

## Output Files

The result CSV is the detailed evidence file. Key columns are:

- `LocalComputerName` - server where the script ran.
- `Status` - `Pass`, `Fail`, `Skipped`, or `Error`.
- `TcpTestSucceeded` - TCP result for TCP rows.
- `PingSucceeded` - ICMP result for ICMP rows.
- `SourceAddress` - local source address reported by `Test-NetConnection`.
- `RemoteAddress` - remote address reported by `Test-NetConnection`.
- `ErrorMessage` - row-level validation or runtime error.

The summary CSV is optional. It groups results by target, protocol, port, service, and status.

## Exit Codes

| Exit code | Meaning |
|---|---|
| `0` | Script completed and all tests passed. |
| `1` | Script completed but one or more tests failed or were skipped. |
| `2` | Input validation or runtime error occurred. |

## Example

See `01-examples/input/example-target-ad-line-of-sight.csv` for a complete Active Directory line-of-sight sample.
