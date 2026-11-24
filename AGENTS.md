# Working on easyNIS

## Keep the implementation simple

- Start with the problem in front of you. Add an abstraction only when it removes real work from its callers or gives a rule one clear home.
- Prefer straightforward control flow and established R and tidyverse idioms. Keep data masking and tidyselect at the interfaces where analysts use them. Validate shapes, types, and invariants where data enters a module.
- Fix a design that causes repeated problems. Delete obsolete paths, stale assumptions, and speculative extension points. Git retains the history.
- Explain constraints the code cannot express, such as a DuckDB behavior or a survey-design requirement. Remove comments that repeat the implementation.
- Ask before deleting data, rewriting history, or taking another action that is difficult to reverse.

## Work and verify

- Work on a branch or isolated worktree. Keep commits focused and use your configured Git identity.
- Decide what would prove the change before implementing it. Prefer tests that exercise the real package workflow. When a focused test is necessary, identify its failure case and write the test before the fix. Avoid duplicate checks and assertions on implementation details.
- Start verification with focused tests and `devtools::check()`. Run independent review before requesting merge. See [Contributing](CONTRIBUTING.md) for local checks and the module map.
- Keep reproducible end-to-end evidence with the invented inputs, exact command, observed result, and verification scope under the ignored `local/loop/` directory.
- Use invented public fixtures and independently authored code. Keep licensed NIS inputs, record-derived results, private paths, and local validation receipts out of Git. Real NIS results and probe spill files stay under the verified, ignored `local/loop/` directory.

## Repository references

- Track work in [GitHub Issues](https://github.com/MSaadAsif/easyNIS/issues). Follow the [improvement loop](docs/LOOP.md) for triage and the [roadmap](docs/IMPROVEMENT-ROADMAP.md) for scope decisions.
- Use the [NIS glossary](vignettes/articles/glossary.Rmd) for domain terms and [Contributing](CONTRIBUTING.md) to find the code and tests for each domain.
- The [HOCM backlog](docs/backlog/hocm-srt-pacing-gaps.md) and the roadmap record the deferral of device code sets and the conditions for resuming Elixhauser work.

Adapted from the [RCMetaStudio engineering guidance](https://github.com/AliSalman-et-al/rc-metastudio/blob/master/AGENTS.md).
