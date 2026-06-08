# Examples

This folder contains an AD line-of-sight scenario that demonstrates the target-focused workflow.

Input:

- `input/example-target-ad-line-of-sight.csv`

Scenario shape:

- 3 target domain controllers.
- ICMP plus every AD-related TCP port present in the bundled target CSV files.
- 45 total test rows.

AD TCP ports included:

```text
53, 88, 135, 139, 389, 445, 464, 636, 3268, 3269, 5722, 5985, 5986, 9389
```

Run the example from the package root:

```powershell
.\Test-NetConnectionPlan.ps1 `
  -InputCsv .\01-examples\input\example-target-ad-line-of-sight.csv `
  -OutputCsv .\01-examples\output\example-target-results.csv `
  -SummaryCsv .\01-examples\output\example-target-summary.csv
```

The `output` folder includes sample result and summary CSVs for running this same input from two source servers: `SRC-DC01` and `SRC-DC02`.

The example uses documentation-only hostnames and IP addresses. Copy it into `03-projects`, replace the placeholder target values with real project values, then run from each source server or source network location.
