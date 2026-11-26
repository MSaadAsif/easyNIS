# Build cache dependencies for the generated study template. External NIS data
# use path and metadata instead of a full content scan; the small bundled example
# is hashed by content because its temporary directory changes on every render.
nis_study_cache_key <- function(
  input_path,
  is_example,
  data_files,
  years,
  codes,
  cohort,
  annualize,
  source_chunks,
  survey_options
) {
  source_code <- lapply(source_chunks, function(code) {
    paste(deparse(parse(text = code)), collapse = "\n")
  })
  file_paths <- if (length(data_files) > 0L) {
    sort(normalizePath(data_files, winslash = "/", mustWork = TRUE))
  } else {
    character()
  }
  data_key <- if (isTRUE(is_example)) {
    list(example_md5 = unname(tools::md5sum(file_paths)))
  } else {
    file_info <- file.info(file_paths)
    list(
      path = normalizePath(input_path, winslash = "/", mustWork = TRUE),
      files = file_paths,
      size = as.numeric(file_info$size),
      mtime = as.numeric(file_info$mtime)
    )
  }

  namespace <- asNamespace("easyNIS")
  function_names <- sort(Filter(
    function(name) is.function(get(name, envir = namespace, inherits = FALSE)),
    ls(envir = namespace, all.names = TRUE)
  ))
  package_code <- lapply(function_names, function(name) {
    paste(deparse(get(name, envir = namespace, inherits = FALSE)), collapse = "\n")
  })
  names(package_code) <- function_names
  dependency_names <- c("DBI", "dbplyr", "dplyr", "duckdb", "rlang", "srvyr", "survey", "tidyselect")
  dependency_versions <- vapply(
    dependency_names,
    function(name) as.character(utils::packageVersion(name)),
    character(1)
  )

  list(
    package = as.character(utils::packageVersion("easyNIS")),
    r = R.version$version.string,
    years = years,
    codes = codes,
    cohort = cohort,
    annualize = annualize,
    data = data_key,
    source_chunks = source_code,
    package_code = package_code,
    data_policy = list(cpi = .cpi_u, labels = .hcup_labels),
    workload_settings = getOption("easyNIS.duckdb_config"),
    dependency_versions = dependency_versions,
    survey_options = survey_options
  )
}

# These packages implement the generated report's tables, models, plots, and
# rendered outputs. Optional packages use an explicit sentinel so installing or
# upgrading one changes the cache key instead of silently reusing old output.
nis_study_report_packages <- function() {
  c(
    "broom.helpers",
    "cardx",
    "cards",
    "flextable",
    "ggplot2",
    "gt",
    "gtsummary",
    "knitr",
    "purrr"
  )
}

nis_study_package_versions <- function(packages) {
  vapply(
    packages,
    function(name) {
      if (!requireNamespace(name, quietly = TRUE)) {
        return("<not-installed>")
      }
      as.character(utils::packageVersion(name))
    },
    character(1)
  )
}

nis_study_report_cache_key <- function(
  design_key,
  exposure,
  covariates,
  outcomes,
  output_format,
  package_versions = nis_study_package_versions(nis_study_report_packages())
) {
  list(
    design = design_key,
    report_inputs = list(
      exposure = exposure,
      covariates = covariates,
      outcomes = outcomes
    ),
    output_format = output_format,
    package_versions = package_versions
  )
}
