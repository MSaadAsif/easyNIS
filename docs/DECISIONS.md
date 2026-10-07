# Design decisions and interview

Updated 2026-10-08. The requested grill-with-docs workflow records decisions as the interview progresses. The development plan distinguishes confirmed direction from proposals awaiting review. Creating this public repository, cloning the repositories, and writing the plan were directly authorized by Saad.

## Confirmed direction

| ID | Decision | Basis |
|---|---|---|
| D1 | Develop easyNIS first; return to easyNRD later. | Initial request. |
| D2 | A standard R package with simple workflows and a later software paper. | Initial request. |
| D3 | V1 includes import, validation, harmonization, cohort definition, survey designs, models, and publication tables. | Q1: include models and publication tables in v1. |
| D4 | Expand coverage toward all released years in verified stages. | Q2: stage coverage toward all years. |
| D5 | Saad/Ali have access to 2017–2022 NIS for private validation. | Q3. Actual formats, revisions, and files remain uninspected. |
| D6 | Use one public MSaadAsif/easyNIS development repository with tagged stable releases. | Q4. |
| D7 | License new easyNIS code under MIT. | Q5. This does not change easyNRD or third-party terms. |
| D8 | Release-supported years start with 2017–2022, then 2023, then transition and historical years. | Q6. |
| D9 | Initial inputs are parquet; Saad's workstation has 40 GB RAM. | Q7. Ali's hardware and conversion provenance remain to inventory. |
| D10 | V1 models are survey-weighted linear, logistic, and Poisson-family regressions; tables export CSV, HTML, and Word. | Q8. Survival, propensity methods, and imputation are later extensions. |
| D11 | JOSS is the primary paper target. | Q9. |
| D12 | Saad is maintainer; Ali is coauthor; both review methods. | Q10. Public email and preferred author metadata remain to provide. |
| D13 | Parquet is the release-tested v1 input; other importers follow later. | Q11. |
| D14 | Use DuckDB for disk-based preparation and narrow analysis projections, with numerical reference checks and 40 GB benchmarks. | Q12. Disk-backed inference remains to prototype and validate. |
| D15 | Record pooled estimands, missingness, inference choices, and disclosure checks explicitly. | Q13. |
| D16 | Write independent easyNIS implementation; defer copying easyNRD code until permission/licensing is resolved. | Q14. |

## Completed interview rounds

| Question | Recommendation | Status |
|---|---|---|
| Q6: first release years and expansion order | Validate 2017–2022 first, then 2023, 2012–2016, and older years. | Accepted. |
| Q7: input formats and available RAM | Inventory files and machines. | Parquet and Saad's 40 GB RAM confirmed. |
| Q8: model families and table formats | Survey GLMs for linear/logistic/Poisson-family models; descriptive/regression tables; CSV, HTML, Word. | Accepted. |
| Q9: paper venue | Initially recommended The R Journal. | Saad selected JOSS as primary. |
| Q10: maintainer and author metadata | Saad maintains; Ali coauthors; both review methods. | Roles accepted; contact/ORCIDs outstanding. |
| Q11: first input contract | Parquet first; other formats later. | Accepted. |
| Q12: performance approach | DuckDB preparation, narrow model projection, numerical agreement, benchmarks. | Accepted. |
| Q13: statistical/export contracts | Explicit estimands, missingness, inference settings, disclosure checks. | Accepted. |
| Q14: independent implementation | New MIT implementation; no direct easyNRD copying without permission. | Accepted. |

## Design tree

```text
easyNIS before easyNRD [confirmed]
  Standard R package, later paper [confirmed]
    Complete analysis workflow in v1 [confirmed]
      Model families and export formats [confirmed]
        Effect measures, df policy, missingness contract [methods review]
      Parquet inputs and 40 GB RAM [confirmed]
        DuckDB preparation and narrow model projection [confirmed]
        Supported performance envelope [benchmark gate]
    All released years via staged coverage [confirmed]
      2017–2022 licensed access [confirmed]
        First-release/expansion order [confirmed]
        File revisions and private independent validation [inventory]
      Older-year validation access [later frontier]
        Historical support claims and release gates [dependent]
    One public development repository [confirmed]
      MIT for new code [confirmed]
        Independent implementation first [confirmed]
      Maintainer roles [confirmed]; contact/ORCIDs [outstanding metadata]
        CONTRIBUTING, reviewer roles, support commitments [dependent]
    JOSS as primary paper venue [confirmed]
      Validation comparisons and research adoption evidence [ongoing]
      Journal-specific manuscript and archive [dependent]
```

## Remaining review and deliberately deferred details

The planning frontier is resolved. On 2026-10-08 Saad instructed Codex to begin implementation and provided the public maintainer name Muhammad Saad, email msaadasif.md@gmail.com, and ORCID 0000-0002-1792-2357. Saad identified the local AHRQ NIS folder for the licensed input inventory. Ali's full preferred public name and optional ORCID remain pending. Before the relevant module is released, Saad and Ali must review exact inference/default choices using the cases listed in the plan. Historical methods and disk-backed inference remain gated research tasks, not silently accepted assumptions.

The repository can hold proposals during this interview. Function names, exact metadata storage, supported R baseline, and optional rendering dependency versions remain implementation proposals. They can be resolved during their stated phase with evidence and author review; the initial scope and workflow contracts above are confirmed. Accepted ADRs record only decisions already made.

## Additional context review

Saad authorized a full Biostatistics context review after the interview rounds. The completed source/documentation audit refined the existing validation contracts rather than changing the agreed v1 model/input scope. The plan now includes verified conversion profiles, original-code preservation, clinical-algorithm provenance, and model-scale checks. No existing study code or clinical record was copied into the public package. The remaining shared-understanding confirmation applies to the concrete written plan.
