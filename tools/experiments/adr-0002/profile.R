read_experiment_profile <- function(path) {
  profile <- jsonlite::read_json(path)
  fields <- c("query_name", "latency", "cpu_time", "system_peak_buffer_memory", "system_peak_temp_dir_size", "children")
  if (!all(fields %in% names(profile))) {
    stop("Expected a DuckDB 1.5.2 experiment profile in ", path, ".", call. = FALSE)
  }
  profile
}
