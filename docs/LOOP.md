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
   precedence only when its normalized path remains inside the main checkout's
   Git-ignored `local/loop/` directory; the probe verifies this with
   `git check-ignore` and stops when the path is outside it or is not ignored.
2. Run `& $env:EASYNIS_RSCRIPT tools/probe/test-probe-helpers.R`, then
   `& $env:EASYNIS_RSCRIPT tools/check-public-text.R --self-test`. Run
   `& $env:EASYNIS_RSCRIPT tools/probe/readiness.R` and inspect its cyclocomp
   gate and the violation report from `probe-quality.R`. Keep
   `cyclocomp_linter(15)` out of `.lintr` until the final violation is cleared;
   add it in the PR that clears that violation.
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

No output from a real-data run may be copied into an issue, PR, commit, or
document. This includes `findings.jsonl`; keep every real-data output local.
Full condition text may be stored only under `local/loop/<run>/private/`.
When `pkgcheck` or `goodpractice` fails, `probe-quality.R` saves its nested
diagnostic results and captured warning conditions in
`private/quality-diagnostics.rds`; keep that artifact local as well. Public
quality receipts contain categorical failure and warning summaries, not
nested condition text. A goodpractice prep failure is a failed step, while an
unknown check status remains unverified.
A public issue contains only a synthetic reproduction using `nis_example()` or
another fixture, plus a description of the problem in general terms. The
public-text scanner is a backstop, not publication clearance. Use judgment and
remove all real-run output before submitting any public text.

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
