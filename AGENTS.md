# easyNIS agent instructions

For an explicit instruction to start or continue easyNIS development, read
`docs/AUTONOMY.md` and execute its loop through the agreed backlog. That
instruction authorizes review, testing, commits, pushes, PR creation and merging
passing experimental increments. Preserve user changes and resume from evidence.
For status questions, reviews, or setup requests, perform only the requested work.

Scheduling requires an explicit user request. A start instruction alone does not
authorize a heartbeat, scheduled task, background restart, or later wakeup.

Before changing a module, read its backlog acceptance criteria and relevant
contract in `docs/`. Before committing, use `tools/verify.ps1`. Before merging,
use `tools/merge-verified.ps1` with independent review evidence for the current
PR head. Use a separate read-only review agent for each merge; the implementing
agent resolves findings and reruns affected checks. Parallel writers need their
own worktrees. Read `docs/SKILL-ROUTES.md` when choosing a skill.
Use `docs/MODEL-ROUTING.md` for usage-aware native worker selection.

Development merges are distinct from scientific approval. Keep experimental
methods explicit until Saad and Ali approve scientific choices and the evidence
in `docs/SUPPORT.md` permits capability promotion. Keep licensed inputs, private
paths, local receipts and record-derived output ignored. Public fixtures are
invented. Write independent MIT code; existing easyNRD code has separate terms.

Record reproducible public progress and the next action in `docs/BACKLOG.md`;
store machine-specific logs and review receipts in `.audit/`. A passing test
count alone does not establish annual support or statistical correctness.
