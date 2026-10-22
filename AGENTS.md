# easyNIS development

Work on a branch or isolated worktree. Run focused tests and
`devtools::check()` before requesting independent review. Use invented
public fixtures and independently authored code compatible with the
project’s AGPL-3.0-only license. Never commit licensed inputs, private
paths, local validation receipts, or record-derived output. Real NIS
results stay local under the ignored `local/loop/` directory. Follow
`docs/LOOP.md` for the improvement cycle.

Commits must use author and committer
`Muhammad Saad <168359874+MSaadAsif@users.noreply.github.com>` and must
not include AI attribution or co-authors.

Deferred HOCM backlog items: curated cardiac device code sets (#3) and
Elixhauser computation (#8). Elixhauser may be resumed only as a thin
wrapper over an existing package such as `comorbidity` or
`medicalcoder`; device code sets remain deferred. See
`docs/backlog/hocm-srt-pacing-gaps.md`.

For improvement planning, read `docs/IMPROVEMENT-ROADMAP.md`.
