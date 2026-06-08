# Project Template

Copy this folder into `03-projects` and rename it for the engagement or test window.

Recommended copy command from the package root:

```powershell
Copy-Item .\02-templates\my-project-template .\03-projects\my-project -Recurse
```

Then copy one or more CSV templates from `02-templates/template CSVs` into the copied project `input` folder and edit them with real target server names and IP addresses.

Example:

```powershell
Copy-Item ".\02-templates\template CSVs\ad-line-of-sight-template.csv" .\03-projects\my-project\input\test-plan.csv
```

Suggested workflow:

```powershell
.\Test-NetConnectionPlan.ps1 `
  -InputCsv .\03-projects\my-project\input\test-plan.csv `
  -ValidateOnly

.\Test-NetConnectionPlan.ps1 `
  -InputCsv .\03-projects\my-project\input\test-plan.csv `
  -OutputCsv .\03-projects\my-project\output\results.csv `
  -SummaryCsv .\03-projects\my-project\output\summary.csv
```

Run the project from each source server or source network location that needs line-of-sight validation.
