# Invented fixture contract

`nis_synthetic_data(year)` generates records in memory without reading any
HCUP data or calling a random-number generator. The year can be 2017–2022.
No binary record files are bundled. The fixture has 12 discharges, 4 hospitals,
and 2 strata. Each hospital has three discharges with weights 2, 3, and 4.
Identifiers deliberately recur across years, and discharge keys exceed the
exact integer range of a double. Hospital keys retain leading zeros.

The repeated DIED values are 0, 1, and missing. Weighted deaths are 12,
the observed-outcome weight is 20, and the observed-outcome proportion is 0.6.
The total discharge weight is 36. Ages repeat 20, 40, and 60, except for the
last age, which is missing. The observed-age weight is 32 and its weighted
mean is 42.5. These arithmetic expectations do not validate survey inference.

Diagnosis slots vary as 2, 3, 4, 2, 3, 4 across the six year labels; procedure
slots alternate between 1 and 2. Every fixture has Core, Hospital, and invented
Severity fields. The 2017 fixture omits the groups component. These small
patterns exercise future adapters and are not audited annual schemas.
`SYN_*` and `001` are test tokens, not clinical phenotypes or reviewed ICD codes.
Ordinary NA values represent invented missing observations; special HCUP
missing reasons and conversion-loss cases require later metadata tests.
