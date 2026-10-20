# Improvement loop playbook

## Roles

- The orchestrator probes, files findings, plans work, and reviews completed
  changes.
- Workers implement assigned issues in separate worktrees under
  `$USERPROFILE\.t3\worktrees\easyNIS\`. Use no more than four workers at
  once, and assign disjoint files.
- A max-effort reviewer independently reviews each proposed change.

## Cycle

1. In PowerShell, source the main checkout's setup file with
   `. "$env:USERPROFILE\Documents\easyNIS\.easynis-local.ps1"`, then run
   `& $env:EASYNIS_RSCRIPT tools/probe/probe-real-data.R` and
   `& $env:EASYNIS_RSCRIPT tools/probe/probe-quality.R`. Keep outputs under the
   ignored `local/loop/` directory. A shell-provided `EASYNIS_LOOP_DIR` takes
   precedence over the value in `.Renviron`.
2. Run `& $env:EASYNIS_RSCRIPT tools/probe/test-probe-helpers.R`, then
   `& $env:EASYNIS_RSCRIPT tools/check-public-text.R --self-test`. Run
   `& $env:EASYNIS_RSCRIPT tools/probe/readiness.R` and inspect the cyclocomp report.
3. Turn actionable findings into GitHub issues using
   `.github/ISSUE_TEMPLATE/loop-finding.yml`. For CLI issues use
   `gh issue create --label loop-found --label P1 --body-file issue.md` and
   replace `P1` with the assigned priority so the readiness query sees it. Run
   `& $env:EASYNIS_RSCRIPT tools/check-public-text.R --stdin` on every issue or PR body before
   submitting it. Do not file issues for this tooling change; start with the
   next loop cycle.
4. Pick P0 issues first, then P1, P2, and P3. Assign at most four workers, with
   no two workers editing the same files. Branch from current `main` and open
   a focused PR for each issue.
5. Require an independent max-effort review and the repository's required
   status checks. Re-run affected probes and readiness after merge.

## Branches, PRs, and done

Use `fix/<issue>-short-topic` or `docs/<issue>-short-topic` branches. PR titles
state the change and reference the issue. Each issue is done when its fix has
a regression test using synthetic data, `devtools::check()` is clean, and
documentation plus `NEWS.md` are updated. Keep changes focused and preserve
tidyverse conventions, established package behavior, and low cyclomatic
complexity.

## Privacy and attribution

Licensed NIS data may be read locally for diagnosis only. Never publish or
commit real records, counts, estimates, distributions, data inventories,
private paths, or local validation receipts. Public probe findings contain
only step/function/year, redacted diagnostics, timing, an approximate R heap
estimate, and pass/fail. Numeric diagnostics are replaced as a whole to avoid
leaking small-cell counts through singular/plural wording. Arrow and other
native allocations can exceed the heap estimate. Private output contains
estimates only, never a survey design or record-level copy.
Use invented public fixtures. Run the public-text guard before filing issues
or PRs.

Set commit author and committer to `Muhammad Saad
<168359874+MSaadAsif@users.noreply.github.com>`. Do not add co-authors or AI
attribution in commits, PRs, issues, documentation, or code comments.

## Owner decisions and stopping

Label `needs-owner-decision` and do not merge work involving adding or removing
exports, breaking API changes, new hard Imports, releases, or data-policy
changes. Stop when `readiness.R` reports every criterion ready, or after two
cycles find no new P0–P2 findings.

## Merge procedure

The `main` branch requires up-to-date branches and five status checks; auto
merge is disabled. Squash merge only after review and green checks, then remove
the merged worktree. Do not merge changes behind a pending owner decision.
