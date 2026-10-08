# Explicit-start development

Saad approved this policy on 2026-10-08. An instruction such as "Start working
on easyNIS autonomously" authorizes continuing through the agreed backlog,
including finding and fixing problems, testing, independent agent review,
committing, pushing, and merging passing development increments. Routine
reversible implementation choices do not need another confirmation.

Setup or status requests do not start the development loop. The hourly
continuation automation was deleted. A schedule may be created only when Saad
explicitly requests one, with its scope, end condition and timing. An ordinary
start runs in the active chat; reaching account limits saves a checkpoint and
requires another instruction to resume. Files and scripts do not keep an agent
running when the chat is stopped or the application is closed.

## Run loop

1. Read repository status, current PRs, `docs/BACKLOG.md`, and the latest local
   evidence. Inspect unfinished work before deciding whether to adopt it. Use
   `tools/verify.ps1 -Doctor` to confirm R, development packages and GitHub
   access. Confirm there is no other writer working in the same checkout.
2. Choose the next actionable acceptance criterion. Prioritize correctness,
   failed checks, review findings, provenance and missing verification before
   new features. The initial goal is the agreed 2017–2022 workflow. Later years
   and new model families retain their separate backlog and validation gates.
3. Define the observable result and adequate cases before changing behavior.
   Bug fixes get a reproducer that fails on the old behavior. Statistical work
   gets independent reference calculations and justified tolerances. Test
   normal use, relevant boundaries, missingness and rejection paths. Increase
   case coverage when a real failure or new contract calls for it, rather than
   adding tests solely to increase the count.
4. Make one reviewable increment on a feature branch. Retain raw meanings,
   provenance and experimental status. Preserve existing user work; use a
   separate checkout when it cannot safely coexist. Avoid force pushes and
   broad staging of ignored or unrelated files.
5. Generate documentation deliberately, then run `tools/verify.ps1`. The command
   fails on documentation drift, failed/warned/skipped tests, failed package
   checks, or forbidden tarball contents. It builds and installs the source
   package and exercises the installed public API using invented parquet files.
   Inspect the logs and write the evidence and remaining limitations into the
   backlog. Rerun after changes that invalidate that evidence.
6. Commit named files, then rerun verification from the clean committed head to
   bind the local evidence to the commit. Push and create or update a PR with the problem, resulting
   behavior, case coverage and evidence. Attach created PRs to the Codex chat.
   Watch the current CI run within the active turn and repair failures; do not
   create a schedule to watch it. All five platform/R jobs must succeed for the
   commit being considered. Integrate a newer base if GitHub requires it, then
   repeat affected verification.
7. Have an independent read-only agent inspect the final diff against its
   acceptance criteria, test adequacy, scientific claims, and private-data
   boundaries. Resolve all blocking findings. Record a JSON review receipt in
   `.audit/reviews/` using the format below. Only the reviewer can supply the
   verdict. Refresh the review when either head or base changes.
8. Mark the PR ready when it has passed review. Run
   `tools/merge-verified.ps1 -PullRequest <number> -ReviewFile <receipt>` for a
   read-only gate check, then add `-Merge` to land it. The command requires a
   clean PR against `main`, successful checks, current independent review,
   configured GitHub protection, and a clean local checkout at the PR head.
   It uses GitHub's head-match option and never bypasses protection.
9. Fetch the resulting `main`, inspect its checks, update the checkpoint, and
   repeat from step 2. A finding about the workflow itself becomes a targeted
   gate or documentation improvement with the same verification and review.

## Review receipt

This local receipt makes the review attributable and binds it to the diff. It
does not replace the reviewer's actual inspection or GitHub's CI enforcement.
The report must exist and be nonempty. The verification directory must contain
its successful summary, current committed head and empty working-tree state. Use a clean verification
checkout for this final run; the gate rejects missing or stale local evidence.

```json
{
  "head_sha": "full PR head SHA",
  "base_sha": "full PR base SHA",
  "verdict": "VERIFIED",
  "reviewer": "independent agent identity",
  "independent": true,
  "blocking_findings": 0,
  "report_file": ".audit/reviews/head-report.md",
  "verification_dir": ".audit/verify/completed-run-directory"
}
```

## Scientific and publication gates

Tested experimental methods may merge after reference verification and agent
review. Their merge does not mark them scientifically approved or change the
installed support matrix. Saad and Ali still review scientific choices before
validation or release claims. Stable releases, CRAN/JOSS submissions and new
external communications need their applicable explicit instruction.

An unavailable official source or missing conversion history blocks the affected
annual claim, not unrelated synthetic work. Record the dependency and continue
with independent actionable work. Never replace missing evidence with invented
annual metadata or make broken checks easier merely to obtain a pass.

## Stop and handoff

Stop on the user's instruction, completion, account limits, or when every
remaining actionable item depends on external information or a scientific
decision. Record completed increments, evidence, open findings, worktree/branch,
and the next command. Do not restart later without a new instruction or an
explicitly authorized schedule. Keep routine progress concise and notify about
meaningful results, failures and decisions that need the user.

## Commands on this workstation

Use [MODEL-ROUTING.md](MODEL-ROUTING.md) to choose native workers and reasoning
effort without changing global model settings or using unconfigured providers.

From PowerShell in the easyNIS repository:

```powershell
./tools/verify.ps1 -Doctor
./tools/verify.ps1
./tools/merge-verified.ps1 -PullRequest 1 -ReviewFile .audit/reviews/head.json
```

The ignored `.easynis-local.ps1` selects this machine's R installation, library
paths and locale. On another machine, put Rscript on PATH or set
`EASYNIS_RSCRIPT`, and install the packages reported by the doctor. The portable
equivalent is `Rscript tools/verify.R`; its doctor is `Rscript tools/verify.R
--doctor`. Verification creates a unique ignored `.audit/verify/` directory and
preserves its logs. It does not read licensed files or change Git refs.
