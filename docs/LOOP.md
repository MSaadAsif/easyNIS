# Improvement loop

One orchestrator sets direction from the [roadmap](IMPROVEMENT-ROADMAP.md) and
makes product decisions, including exports, API changes, and new Imports.
Releases, license changes, data-policy changes, and any work touching the
owner's real data files are owner-only.

## Triage

Start directly from the roadmap when work can begin. File findings that will
wait using the [loop finding template](../.github/ISSUE_TEMPLATE/loop-finding.yml).
Apply `loop-found` and one priority. Work from P0 (blocks safe use or release)
through P1 (high), P2 (normal), and P3 (low). Describe the problem in general
terms and reproduce it with `nis_example()` or another invented fixture. Follow
the [privacy and text-scanning rules](../CONTRIBUTING.md#privacy-and-licensing).

## Work and review

- Assign one area per worker, with disjoint files and at most 12 active workers.
  Each worker branches from current `main` in a separate worktree under
  `$USERPROFILE\.t3\worktrees\easyNIS`.
- Workers implement the assigned change, pass the
  [contributor checks](../CONTRIBUTING.md#verify-a-change), open one PR against
  `main`, and stop. Workers never start subagents or reviewers.
- The orchestrator performs independent review, consults a second-opinion
  model when useful, and requests changes as needed. Once review and required
  checks pass on the up-to-date branch, the orchestrator squash-merges the PR
  and removes the worktree and local branch.
- Reviewers check the [data type rules](../CONTRIBUTING.md#data-types) in DuckDB and at the R boundary.
- Periodically and before release, the orchestrator runs `Rscript --vanilla tools/news-collect.R`
  from the repository root and opens a PR with the updated `NEWS.md` and deleted fragments.

## Local evidence

Use the [quality probe](../tools/probe/probe-quality.R) and
[readiness report](../tools/probe/readiness.R) to track roadmap criteria.
Rerun affected probes after merge. Readiness needs GitHub CLI access to check
issues and CI.

Run the [real-data probe](../tools/probe/probe-real-data.R) and other licensed-data checks only on the owner's machine.
It reads `EASYNIS_DATA` from the environment or the main checkout's ignored
`.Renviron`. The probes keep evidence in the main checkout's ignored
`local/loop/`. Any `EASYNIS_LOOP_DIR` override must resolve inside that directory.
Keep full condition text and diagnostic artifacts under `local/loop/<run>/private/`.
