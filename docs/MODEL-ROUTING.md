# Usage-aware model routing

Project policy proposed from current OpenAI documentation on 2026-10-08 and
Saad's instruction to evaluate Sol/Luna division of work. The table is a starting
point, not measured easyNIS performance or a promised subscription multiplier.

| Work | Native model | Requested effort | Escalation |
|---|---|---|---|
| Coordinator, acceptance criteria, API decisions, source interpretation | gpt-6.1-sol | medium | high for ambiguous cross-year or inference choices |
| Bounded edits, documentation updates, straightforward implementation from a reviewed contract | gpt-6-luna | medium | Sol when the contract changes or a reproduction remains unresolved |
| Read-only file inventory, narrow log triage, mechanical consistency checks | gpt-6-luna | low | Sol for conflicting evidence or an uncertain finding |
| Survey methods, pooling, missingness semantics, precision and provenance logic | gpt-6.1-sol | high | Astra only for a difficult unresolved question worth the added usage |
| Independent pre-merge specification/correctness review | gpt-6.1-sol | high | Escalate a specific unresolved risk, rather than running a panel by default |
| Independent mechanical/standards review of a bounded increment | gpt-6-luna | medium | Sol when there are consequential findings or inadequate scientific references |
| Persistent hard architecture or methods problem | gpt-6-astra | high | Explicitly scoped read-only judgment task; return findings to the coordinator |

These identifiers and efforts are exposed by the native Codex tools on this
host. A model listed in a tool schema is not proof that a run will pass its
current account limit. Probe the needed route with a small real task and record
its outcome. Availability failure is not a successful review. Keep the work
checkpointed if an essential reviewer cannot run, and never merge on an
inconclusive verdict. Verify current model identifiers when the host changes.

## Dispatch

For a new native worker, pass `fork_turns="none"` with the chosen `model` and
`reasoning_effort`, plus the exact worktree, relevant files, acceptance criterion,
allowed changes and required evidence. Full-history forks retain the parent
model and consume context that a narrow task often does not need. Do not send
licensed records, local private validation paths or unrelated project files.

Use at most two workers plus the coordinator for ordinary increments. Separate
writers with worktrees; reviewers are read-only. Prefer serial standards/spec
reviews for small increments if parallel overhead is unnecessary. Scientific
logic requires an independently calculated reference and stronger review even
when a Luna worker implemented it. Native reviewers are independent agents,
not a claim of different model families or scientific approval.

The current chat keeps its selected parent model. This project policy does not
change that model automatically or update global pstack defaults. For future
development chats, select Sol with medium reasoning as the coordinator when
available; narrower workers use the routes above. No external model provider,
API key, purchase or usage reset credit is required by this configuration.

## Usage controls

- Start ordinary tasks at the table's effort rather than defaulting to max or
  ultra. Increase effort only for a stated unresolved risk.
- Use deterministic scripts for tests, builds, parsing and repeated checks.
  Save logs once and read concise summaries instead of sending full output
  through multiple agents. A real new defect or input change justifies reruns.
- Read account usage at start, major checkpoints and before a long new phase.
  Treat it as account-wide information, not precise task billing. If usage is
  unavailable, report that fact; do not invent remaining capacity.
- When little capacity remains, finish or checkpoint the current increment
  rather than launching optional reviews or speculative work. Keep the merge
  gates unchanged. If scheduled continuation was explicitly authorized, wait
  for that run; otherwise await the user's resume instruction.
- Do not create a schedule, buy credits, consume reset credits or change speed
  mode merely to extend a run. Scheduling needs its own explicit instruction.

## Evaluate the policy

During authorized increments, record the model/effort, task class, acceptance
result, wall time, rework/escalation count and any reported token usage in local
evidence. Compare representative bounded implementations, a regression fix,
and one metadata/methods investigation. Judge a cheaper route by correct work
per successful increment, including review and rework, rather than by model
name or one fast response. Preserve the same cases and merge criteria across
routes. Account-wide percentage changes during concurrent use cannot establish
exact per-model savings.

OpenAI describes Luna as efficient for scoped work and Sol as a balance for
complex technical work. It recommends experimenting with model and effort for
the workload. See [model selection](https://developers.openai.com/api/docs/guides/model-selection).
Included Codex usage differs by model, task and speed mode; API prices do not
estimate subscription task allowances. See [pricing and usage](https://learn.chatgpt.com/docs/pricing).
These sources inform the policy; actual easyNIS comparative results are pending.
