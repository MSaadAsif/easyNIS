# easyNIS development

Work on a branch. Run focused `testthat` tests and `devtools::check()` before
requesting review. An independent reviewer reviews the diff; merge only after
review and checks pass.

Use invented public fixtures and independent MIT code. Never commit licensed
inputs, private paths, local validation receipts, or record-derived output.

For improvement planning or backlog work, read `docs/IMPROVEMENT-ROADMAP.md`.
It records the completed HOCM study. In `docs/backlog/hocm-srt-pacing-gaps.md`,
item 3 (curated cardiac device code sets) and item 8 (AHRQ Elixhauser
comorbidity computation) are deferred until the user explicitly resumes them.
These numbers refer to the HOCM backlog, not the improvement roadmap.
