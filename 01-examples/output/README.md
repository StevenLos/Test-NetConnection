# Example Output

This folder contains sample result and summary files for running `01-examples/input/example-target-ad-line-of-sight.csv` from two different source servers.

Because the script runs locally, each source server writes its own output files:

- `example-SRC-DC01-results-sample.csv`
- `example-SRC-DC01-summary-sample.csv`
- `example-SRC-DC02-results-sample.csv`
- `example-SRC-DC02-summary-sample.csv`

Sample source assumptions:

| Source server | Source address | Sample result pattern |
|---|---:|---|
| `SRC-DC01` | `192.0.2.11` | All example checks pass. |
| `SRC-DC02` | `192.0.2.12` | Most checks pass, with a few sample TCP failures to show failed-row output. |

Run pattern from each source server:

```powershell
.\Test-NetConnectionPlan.ps1 `
  -InputCsv .\01-examples\input\example-target-ad-line-of-sight.csv `
  -OutputCsv .\01-examples\output\example-<SOURCE>-results.csv `
  -SummaryCsv .\01-examples\output\example-<SOURCE>-summary.csv
```

The result CSV is the detailed evidence file. The summary CSV is a grouped count view generated because `-SummaryCsv` was supplied.

The example input and sample outputs use placeholder server names and documentation-only IP addresses. Replace those values with real project values before using generated results for connectivity decisions.
