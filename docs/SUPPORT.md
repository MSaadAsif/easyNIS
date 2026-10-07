# Year support and validation

The target is every NIS year currently released, 1988–2023. This is a roadmap, not a present compatibility claim. **No year has implemented or validated easyNIS support yet.**

The [CSV matrix](year-support.csv) has a row for every target year. Each capability must be backed by reproducible evidence before a release claims support. Extend the matrix when HCUP publishes a new year; do not advertise future years automatically.

## Coverage sequence

| Stage | Years | Validation access | Main boundary |
|---|---|---|---|
| V1 | 2017–2022 | Saad/Ali report parquet access; files uninspected. | Modern coding, annual components and derived-tool variation. |
| Expansion 1 | 2023 | Not yet established. | Removed race/geography and adjusted charges. |
| Expansion 2 | 2012–2016 | Not yet established. | Redesign and split-era 2015. |
| Expansion 3 | 1993–2011 | Not yet established. | Historical schemas, trend weights, 1998 redesign, 2000 charge weight. |
| Expansion 4 | 1988–1992 | Not yet established. | Early formats/designs and restricted trend comparability. |

## Coverage levels

1. **Target** means the year appears in the roadmap. No executable capability is promised.
2. **Metadata-audited** means the year/revision's official component layouts, variable meanings, coding, missingness, and design rules have been reviewed.
3. **Synthetic-validated** means invented fixtures pass applicable import, join, cohort, survey, model, and export tests.
4. **Licensed-validated** means the authorized team has checked actual files against independent reference analyses and recorded sanitized evidence.
5. **Release-supported** means an identified release ships those capabilities with documentation, checks, and limitations.

A synthetic fixture proves behavior on invented inputs. It does not establish that every converted licensed file has the documented layout or provenance. Public documentation establishes metadata facts; it does not replace licensed validation.

Track each capability separately. Missing optional components, unavailable classifications, unvalidated input formats, and trend-specific limits should appear in the capability lookup. Do not collapse 'can read', 'can estimate', and 'comparable across years' into one boolean.

## Evidence required per year

- Official source URLs, revision identifiers, and audited registry commit.
- Component/key/type/missingness checks and expected counts where applicable.
- Cohort code-system and slot-policy tests.
- Point estimate, standard error, and approved model comparisons with recorded tolerances.
- End-to-end publication exports and disclosure edge cases.
- Local licensed validation receipt with sanitized public summary.
- Package tag, supported input format, performance envelope, and documented limits.

For 1988–1992, single-year support and pooled/trend support need separate claims. An adapter must not imply the availability of the official 1993–2011 trend-weight methodology in earlier years.
