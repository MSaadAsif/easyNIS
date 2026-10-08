# Skill routes for easyNIS

Inspected on 2026-10-08. Load the actual installed SKILL.md when using a route;
this table selects the route and records project context. The user's
explicit-start and scheduling policy in `AUTONOMY.md` takes precedence over
generic defaults. Skill names refer to the installed mattpocock-skills and
pstack plugins; the local verification skill is committed with this repository.

| When | Skill | Application here |
|---|---|---|
| Agree on a new material decision | mattpocock-skills:grill-with-docs, grilling, domain-modeling | Interview unsettled decisions; look up facts rather than asking Saad. Record settled research terms in GLOSSARY and material tradeoffs in docs/adr. The autonomy policy is already agreed. |
| Write agent instructions | mattpocock-skills:writing-for-agents | Keep AGENTS concise; disclose the loop and checks through precise document pointers. |
| Verify an increment | verify-easynis, pstack:principle-prove-it-works | Use the installed package, invented parquet files, reference assertions, full source checks and retained logs. |
| Wrong output or a regression | mattpocock-skills:diagnosing-bugs | Reproduce through public R calls, minimize the failing case, then fix the cause and keep a regression test. |
| Explicit test-first request | mattpocock-skills:tdd | Confirm its testing seam requirement once when needed; test public behavior rather than helper implementation. Routine runs can add behavior tests without invoking this interview workflow. |
| Design an R module or API | mattpocock-skills:codebase-design | Keep annual metadata and inference complexity behind small, explicit interfaces. |
| Resolve metadata or methodological facts | mattpocock-skills:research | Use official HCUP documentation and original method/package sources, cite findings under docs, retain private evidence locally. |
| Review before merge | mattpocock-skills:code-review | Give both native read-only reviewers the pinned base, backlog/spec and CONTRIBUTING standards. Separate standards and specification findings; resolve blocking findings before a verdict. |
| Identifier, join, schema or missingness changes | pstack:blast-radius | Inspect callers beyond the diff and prove exact identifiers, row preservation, or the relevant missingness invariant. |
| Hosted checks fail | pstack:fix-ci | Read logs for the current SHA, fix the cause, push and await fresh checks during the active run. |
| Main advances | pstack:fix-merge-conflicts | Resolve on the feature branch, regenerate help, verify and finish resolution before the later publication step. |
| Write a PR description | mattpocock-skills:pr | Describe the concrete behavior, case coverage, evidence, limitations and impact; use the real repository URL. |
| New feature or drift in verification recipes | pstack:maintain-verification-skill | Read source and update the local feature map, then run every affected recipe. Product regressions go through the implementation loop. |
| Repeated mistake | pstack:principle-encode-lessons-in-structure | Add a specific test, metadata contract or gate so the next run catches it. |
| Write any artifact | pstack:unslop | Use direct factual prose in documentation, receipts, commit messages and reports. |

`pstack:create-verification-skill` informs the committed `.agents/skills/verify-easynis/`
skill and feature map. Its deliverable must be executed end to end before it is
reported as working. Existing checks are wrapped rather than replaced.

## Conditional tools

`pstack:babysit` can help watch a PR during an authorized run. Its suggested
heartbeats are disabled by the user's policy unless scheduling is explicitly
requested. It is not the owner of the overall development loop.

`pstack:interrogate`, arena and architect can request model/provider routes
that are not configured on this workstation. Confirm their prerequisites before
invoking them, and disclose unavailable reviewers rather than silently replacing
them. Native independent review is the baseline, without a claim of model
diversity. Multiple models agreeing does not establish scientific correctness.

`mattpocock-skills:prototype` prescribes a throwaway HTML prototype. Use it for
explaining an unsettled workflow interaction if useful, not as the default for
statistical R experiments. R reference calculations belong in reproducible tests.

Avoid installing more plugins or requiring an interview for routine choices
already covered by the approved policy. Load a narrower skill only when its
actual instructions improve the task.
