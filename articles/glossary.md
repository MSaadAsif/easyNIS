# Glossary

## Analysis terms

- **NIS:** The HCUP National Inpatient Sample, called the Nationwide
  Inpatient Sample before its 2012 redesign. It samples inpatient stays
  and is not a census of all hospitalizations.
- **Discharge:** One hospital stay represented by a record. A person may
  have multiple stays; the NIS does not provide longitudinal patient
  linkage.
- **Data year:** The calendar year of discharges in an annual NIS
  release. It is different from the release date.
- **Release revision:** A corrected or distributed version of a
  data-year release. The data year alone may not identify which file
  revision was used.
- **Component:** A discharge-level or hospital-level file in an NIS
  release, such as Core or Hospital. easyNIS’s opening and analysis
  workflows target compatible discharge-level data.
- **Cohort:** The discharges meeting a study’s inclusion definition.
- **Analytic domain:** A subpopulation for which a survey estimate is
  calculated while accounting for the original sample design. It is not
  an independently sampled subgroup.
- **Discharge weight (`DISCWT`):** The NIS weight used to estimate
  national discharge totals and other weighted quantities.
- **Trend weight:** An HCUP weight supplied for specified historical NIS
  years to improve comparability with the redesigned sample. It is not
  universal across historical years, and easyNIS does not select it
  automatically.
- **Estimand:** The explicitly defined quantity a study aims to
  estimate, such as an annual national total or a proportion across
  several years.
- **Stratum (`NIS_STRATUM`):** A sampling-design group used with
  hospitals and weights for variance estimation.
- **PSU / hospital (`HOSP_NIS`):** The primary sampling unit in the NIS
  design. Hospital numbers are year-specific, so easyNIS scopes them by
  year.
- **Annualization:** The
  [`nis_design()`](https://msaadasif.github.io/easyNIS/reference/nis_design.md)
  option that divides weights by the count of valid years included. It
  treats partial years as full years.
- **Reweighting:** Multiplication of design weights by additional
  analyst weights. In easyNIS this is experimental and changes the
  interpretation of weighted totals.

## Coding and reporting terms

- **Prefix flag:** A logical indicator that checks whether an ICD code
  begins with an analyst-supplied string in one of the selected code
  slots.
- **CCSR:** Clinical Classifications Software Refined, a category system
  for ICD-10-CM/PCS codes. easyNIS can read a reference file supplied by
  the user.
- **Primary suppression:** Masking a cell that violates a reporting
  rule.
- **Complementary suppression:** Masking an additional cell so a primary
  suppressed value cannot be recovered from totals. easyNIS’s data-frame
  helper supports a single-dimension case; it is not a general
  suppression solver.
- **CCR (`CCR_NIS`):** Cost-to-charge ratio used to estimate cost from
  hospital charges.
- **Charge:** The amount billed for a stay. It differs from the
  resources used to provide care and from payment received.
- **Cost estimate:** An estimate of resources used for care, potentially
  calculated from charges and a cost-to-charge ratio. Interpretation
  depends on the method and year.
- **CPI-U:** Consumer Price Index for All Urban Consumers, used by
  [`nis_cost()`](https://msaadasif.github.io/easyNIS/reference/nis_cost.md)
  to express amounts in a selected reference-year dollar.
- **Synthetic fixture:** Invented data made by
  [`nis_example()`](https://msaadasif.github.io/easyNIS/reference/nis_example.md)
  to demonstrate package behavior. It contains no real NIS discharges.
- **Coding era:** The code system applicable to a discharge. In 2015,
  NIS includes both ICD-9-CM and ICD-10-CM/PCS discharges.

## Common pitfalls

> **Common pitfalls**
>
> - A weight, code flag, or suppression label is meaningful only with
>   its method and assumptions documented.
> - Synthetic fixture outputs are not estimates of the NIS population.

Continue with [Get
started](https://msaadasif.github.io/easyNIS/getting-started.md), or
consult the workflow articles for definitions in context.
