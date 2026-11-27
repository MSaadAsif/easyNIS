## New features

- Collecting a lazy `nis_open()` table or using an easyNIS helper that collects
  DuckDB results now checks estimated result size against available RAM. Large
  collects emit a message. Before blocking a collect that could use at least
  half of available RAM, easyNIS confirms the result's row count. Set
  `options(easyNIS.collect_prudence = FALSE)` to override the check.
