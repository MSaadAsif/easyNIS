* `nis_open(reader = "arrow")` now limits Arrow's CPU worker pool during queries to the DuckDB thread count, reducing peak memory for multi-year scans.
