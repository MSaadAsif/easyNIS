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

The installed `synthetic-workflow` HTML vignette executes the same quickstart
during source build and displays only its reviewed CSV presentation, rounded
to four decimal places with suppressed cells blank. It explains domain order,
inference and disclosure declarations, output retention and remaining gates.
The HTML engine uses knitr without Pandoc or a network connection. Source build
and check both execute its code; the installed smoke requires the vignette
index and HTML and checks for suppressed cells and absence of temporary paths.
Open it with `vignette("synthetic-workflow", package = "easyNIS")` after
installing the built tarball. Direct source installation does not build it.

## Six-year pooling and model walkthrough

`inst/examples/pooled-model-workflow.R` reuses the invented core builder in
`inst/examples/workflow-fixture.R`; the single-year example uses its unchanged
default fixture. Neither helper nor script is an exported package API.
The pooled script constructs complete designs for invented labels 2017–2022
before pooling and then selecting the same code-set domain. Raw identifiers
repeat across years; the pooled design must have 24 year-specific hospitals,
12 strata and native population df 12. The caller declares
`average_annual_total`, weight divisor 6, missing exclusion, WR variance,
interval df 12 and confidence 0.95. Raw supplied weights remain retained.
The internal Gaussian identity model `LOS ~ 1` has no offset, transformations,
exponentiation or causal interpretation. Its coefficient scale is days.

For year index i from 1 to 6, supplied weights multiply by i and observed LOS
adds i-1 days. Base observed hospital weights are W=(24,36,48,60) and totals
T=(72,144,240,360). Year i therefore has i*W and i*(T+(i-1)*W). Every year has
48 observed and 12 missing domain LOS outcomes. Combined observed weight is
3528 and LOS total is 28896. Thus the pooled mean is 172/21 and average annual
LOS total is 4816. The mean weights discharges across years, rather than
averaging annual means.

The two within-stratum differences of hospital residual totals for the mean
are `12*i*(i-67/21)` and `12*i*(i+17/21)`. With sums i^2=91, i^3=441 and
i^4=2275, the independent mean variance is
`144*(2*2275 - 100/21*441 + (67^2+17^2)/21^2*91)/3528^2`.
Its SE is approximately 0.1993771. Independent average annual total variance
is `(288*2275 + 4032*441 + 15264*91)/36 = 106176`.
The script checks both estimates, SEs and df-12 t bounds, and independently
checks the model intercept/SE/bounds and 288 included/72 excluded outcomes.
Absolute tolerance 1e-9 accommodates double accumulation for these deterministic
totals up to 4816; it is not a general licensed-analysis tolerance.

The rare indicator is nonzero only for three selected first-year discharges.
The same explicit disclosure policy hides that row. CSV/HTML export only the
reviewed descriptive presentation. The fixed report includes versions,
code/domain/weight/inference declarations, model formula/family/scale and
reference-check statements. It omits model coefficients, sample accounting,
retained designs/provenance, raw records, suppressed results and local paths.
This demonstrates model fitting without publishing unreviewed regression
results. Regression-table disclosure review and export remain unsupported.

The installed vignette executes both scripts and displays both reviewed CSVs.
Installed smoke runs the pooled script twice, checks independent CSV references,
explicit model/pool declarations and identical output bytes, and checks blank
suppressed cells in both vignette tables. Generated artifacts are removed by
verification. Users retain output by copying each script's three returned
files together before ending R. Both scripts clean input files/connections on
success or error and remove incomplete output directories.

Word has a separate API contract. Annual metadata, conversion history,
performance, licensed validation, regression-table disclosure/export and
scientific approval retain their separate gates. No annual support, clinical
validity, scientific approval or supported memory envelope is established.
