# Templates

This folder contains reusable templates for starting new project work.

Available folders:

- `my-project-template/` - project folder template with empty `input` and `output` folders.
- `template CSVs/` - reusable sample CSV files to copy into a project `input` folder.

Recommended project-template copy command from the package root:

```powershell
Copy-Item .\02-templates\my-project-template .\03-projects\my-project -Recurse
```

Recommended CSV copy command:

```powershell
Copy-Item ".\02-templates\template CSVs\ad-line-of-sight-template.csv" .\03-projects\my-project\input\test-plan.csv
```

Available CSV templates:

- `minimal-test-plan-template.csv` - the absolute technical minimum columns only: `TargetServerName`, `TargetIpAddress`, `Protocol`, and `Port`.
- `ad-line-of-sight-template.csv` - ICMP plus the AD-related TCP ports used by the bundled package test files.
- `sql-server-connectivity-template.csv` - SQL Server client access and common Windows management ports.
- `web-server-connectivity-template.csv` - HTTP and HTTPS web server ports plus common administration ports.
- `application-server-connectivity-template.csv` - common application listener and dependency ports.
- `file-print-server-connectivity-template.csv` - SMB and common TCP print service ports.
- `windows-management-connectivity-template.csv` - common Windows remote management ports.
- `database-server-common-connectivity-template.csv` - common database listener ports across several platforms.

The AD line-of-sight template includes TCP ports `53`, `88`, `135`, `139`, `389`, `445`, `464`, `636`, `3268`, `3269`, `5722`, `5985`, `5986`, and `9389`.

Do not add UDP rows or port ranges. This package uses `Test-NetConnection`, which supports TCP ports and ICMP reachability for this workflow. For example SQL Browser UDP `1434`, DNS UDP `53`, and Kerberos UDP `88` are intentionally not represented as UDP checks.
