# Offline synthetic workflow

The first NIS-021 increment ships `inst/examples/synthetic-workflow.R` in the
installed package. Run the README command from an R session with DBI, duckdb
and survey installed. No network, licensed inputs or optional Word dependency
is used. The script returns only paths to `report.md`, `table.csv` and
`table.html` in a new temporary directory. Copy all three together before the
R session ends. Their relative links then remain valid. R errors are propagated;
connections and the invented parquet file are cleaned on exit, and incomplete
output directories are removed. The example does not change survey options.
Incompatible caller survey options can therefore reject inference under the
existing estimate contract.

## Observable result

The invented population has four hospitals, two in each of two strata, and
30 discharges per hospital. Hospital weights are 2, 3, 4 and 5. The principal
diagnosis alternates A001 and B001. Only slot 1 is matched, exactly, with
normalization off and missing codes treated as no match. A001 selects 15
discharges per hospital after construction of the complete design.

LOS cycles through 0, 2 and 4, plus the hospital number. The first three
selected LOS values in each hospital are missing. Outcome exclusion therefore
leaves 12 observed domain discharges per hospital. Weighted observed totals
are 72, 144, 240 and 360; weights are 24, 36, 48 and 60. The ratio mean is
816/168 = 34/7. Linearized hospital residual totals are -312/7, -216/7, 48/7
and 480/7. Hospital WR variance of the mean is
`((96/7)^2 + (432/7)^2) / 168^2`. Its SE is approximately 0.3763.
The two-sided 95 percent interval uses the caller-declared df of 2 and
`qt(0.975, 2)`. Checks use absolute tolerance 1e-12, suitable for this small
deterministic calculation on doubles. This choice is not a general tolerance
or a scientific recommendation for licensed analyses.

The rare indicator is one only for the first three selected discharges in
the first hospital. Its weighted total must remain hidden. Review explicitly
suppresses raw counts 1 through 10, displays zero, requires two contributing
hospitals and declares no margins. The LOS row is shown, while the rare row
is primary-suppressed. Neither the report nor either table export includes
the hidden estimate, underlying raw counts or disclosure audit fields. CSV
preserves shown doubles exactly and refuses formula-leading text. HTML rounds
estimates, SEs and intervals to four significant digits and includes policy
notes. Both retain the table's disclosure status.

## Report boundary and verification

The report deliberately lists only R and package versions, invented source
declaration, code-set declaration, slot/match/domain policies, design field
names and methods, unscaled weight and estimand meaning, outcome missingness,
variance, df/confidence, row definitions, disclosure policy and relative output
links. It does not serialize `sessionInfo()`, provenance objects, source paths,
data frames, retained designs or numeric inference. Numeric results appear
only in the reviewed exports. This is a fixed example, not a report generator
for arbitrary user objects or a guarantee that arbitrary caller labels are
free of identifying text.

`tools/smoke-installed.R` executes the installed script twice, checks independent
mean/SE/interval values, shown counts and suppression, verifies the report's
policy declarations and absence of local paths, and requires identical report
and export contents across both runs. It removes generated artifacts afterward.
Full verification also checks the installed example is in the source package.

This increment demonstrates single-year descriptive inference. Pooling,
regression and Word have separate executable examples and contracts; integrating
them into a longer workflow and a formal vignette remains NIS-021 acceptance
work. Regression-table disclosure/export, annual metadata, conversion history,
performance and licensed validation remain separate gates. The example does
not promote annual support, clinical validity or scientific approval.
