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
  dependency_names <- c("arrow", "dplyr", "rlang", "srvyr", "survey", "tidyselect")
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
    dependency_versions = dependency_versions,
    survey_options = survey_options
  )
}

# These packages implement the generated report's tables, models, plots, and
# rendered outputs. Optional packages use an explicit sentinel so installing or
# upgrading one changes the cache key instead of silently reusing old output.
nis_study_report_packages <- function() {
  c(
    "broom.helpers", "cardx", "cards", "flextable", "ggplot2", "gt",
    "gtsummary", "knitr", "purrr"
  )
}

nis_study_package_versions <- function(packages) {
  vapply(packages, function(name) {
    if (!requireNamespace(name, quietly = TRUE)) {
      return("<not-installed>")
    }
    as.character(utils::packageVersion(name))
  }, character(1))
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

# Check whether the observed cohort can support a model contrast.
nis_study_model_data_status <- function(data, outcome, exposure, formula = NULL) {
  if (!is.data.frame(data)) {
    return("The model data are unavailable.")
  }
  if (nrow(data) == 0L) {
    return("The cohort has no rows after applying the study design.")
  }
  required <- c(outcome, exposure)
  missing <- setdiff(required, names(data))
  if (length(missing) > 0L) {
    return(paste("The model data are missing", paste(missing, collapse = ", "), "."))
  }
  suffix <- if (is.null(formula)) "." else " in the complete-case rows."
  model_frame <- data
  outcome_values <- data[[outcome]]
  if (!is.null(formula)) {
    model_frame <- tryCatch(
      stats::model.frame(formula, data = data, na.action = stats::na.omit),
      error = function(error) error
    )
    if (inherits(model_frame, "error")) {
      return(paste("The declared model specification fails on complete-case rows:",
                   conditionMessage(model_frame),
                   "Review covariate levels and missingness; no terms were removed."))
    }
    if (nrow(model_frame) == 0L) {
      return("The declared model has no complete-case rows after applying its covariates.")
    }
    outcome_values <- stats::model.response(model_frame)
    model_matrix <- tryCatch(stats::model.matrix(formula, data = model_frame),
                             error = function(error) error)
    if (inherits(model_matrix, "error")) {
      return(paste("The declared model specification fails on complete-case rows:",
                   conditionMessage(model_matrix),
                   "Review covariate levels and missingness; no terms were removed."))
    }
    if (any(!is.finite(model_matrix))) {
      return(paste("The declared model matrix contains non-finite values on complete-case rows.",
                   "Review numeric covariates for Inf or NaN; no terms were removed."))
    }
    matrix_rank <- tryCatch(qr(model_matrix)$rank, error = function(error) error)
    if (inherits(matrix_rank, "error")) {
      return(paste("The declared model matrix rank could not be evaluated on complete-case rows:",
                   conditionMessage(matrix_rank),
                   "Review covariate values and collinearity; no terms were removed."))
    }
    if (matrix_rank < ncol(model_matrix)) {
      return(paste("The declared model matrix is rank-deficient on complete-case rows.",
                   "Review covariate variation, missingness, and collinearity; no terms were removed."))
    }
  }
  exposure_values <- model_frame[[exposure]]
  exposure_values <- exposure_values[!is.na(exposure_values)]
  if (is.numeric(exposure_values) && any(!is.finite(exposure_values))) {
    return(paste0("The exposure ", exposure, " contains non-finite values", suffix))
  }
  if (length(unique(exposure_values)) < 2L) {
    return(paste0("The exposure ", exposure, " has fewer than two observed levels", suffix))
  }
  outcome_values <- outcome_values[!is.na(outcome_values)]
  if (is.numeric(outcome_values) && any(!is.finite(outcome_values))) {
    return(paste0("The outcome ", outcome, " contains non-finite values", suffix))
  }
  if (length(unique(outcome_values)) < 2L) {
    return(paste0("The outcome ", outcome, " has fewer than two observed values", suffix))
  }
  NULL
}

nis_study_fit_model <- function(formula, design, family, fit = survey::svyglm,
                                outcome = NULL, exposure = NULL) {
  warnings <- character()
  if (!is.null(outcome) || !is.null(exposure)) {
    status <- nis_study_model_data_status(design$variables, outcome, exposure, formula)
    if (!is.null(status)) {
      return(list(model = NULL, status = status, warnings = warnings))
    }
  }
  model <- tryCatch(
    withCallingHandlers(
      fit(formula, design = design, family = family),
      warning = function(warning) {
        warnings <<- c(warnings, conditionMessage(warning))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(error) error
  )
  if (inherits(model, "error")) {
    return(list(model = NULL, status = paste("Model fit failed:", conditionMessage(model)),
                warnings = warnings))
  }
  if (identical(model$converged, FALSE)) {
    return(list(model = NULL, status = "The model did not converge.", warnings = warnings))
  }
  material_warning <- grepl(
    paste0(
      "did not converge|failed to converge|not converged|iteration limit|",
      "fitted probabilities.*(0 or 1|numerically)|non[- ]finite|nonfinite|",
      "NaNs? produced|perfect separation"
    ),
    warnings, ignore.case = TRUE
  )
  if (any(material_warning)) {
    return(list(model = NULL, status = paste("The model fit is unstable:",
                 paste(unique(warnings[material_warning]), collapse = "; ")), warnings = warnings))
  }
  coefficients <- tryCatch(stats::coef(model), error = function(error) NULL)
  if (is.null(coefficients) || length(coefficients) == 0L || any(!is.finite(coefficients))) {
    return(list(model = NULL, status = "The model returned missing or non-finite coefficients.",
                warnings = warnings))
  }
  covariance <- tryCatch(stats::vcov(model), error = function(error) NULL)
  if (is.null(covariance) || length(covariance) == 0L || any(!is.finite(covariance))) {
    return(list(model = NULL, status = "The model returned missing or non-finite covariance estimates.",
                warnings = warnings))
  }
  list(model = model, status = NULL, warnings = warnings)
}

#' Create a new NIS study folder
#'
#' Copy the packaged Quarto study template to a new directory. The destination
#' must not already exist.
#'
#' @param path A new local directory path for the study.
#' @return The normalized path to the created study directory.
#' @export
#' @examples
#' study_path <- tempfile("nis-study-example-")
#' nis_new_study(study_path)
#' list.files(study_path, all.files = TRUE, no.. = TRUE)
nis_new_study <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !nzchar(trimws(path))) {
    cli::cli_abort("`path` must be one non-empty directory path.")
  }

  path <- normalizePath(path.expand(path), winslash = "/", mustWork = FALSE)
  link <- Sys.readlink(path)
  if (file.exists(path) || dir.exists(path) ||
      (length(link) == 1L && !is.na(link) && nzchar(link))) {
    cli::cli_abort("The study path already exists.")
  }

  parent <- dirname(path)
  if (!dir.exists(parent) &&
      !dir.create(parent, recursive = TRUE, showWarnings = FALSE)) {
    cli::cli_abort("Could not create the parent directory for the study.")
  }
  if (file.exists(path) || dir.exists(path) || !dir.create(path, showWarnings = FALSE)) {
    cli::cli_abort("Could not create the study directory because the path is unavailable.")
  }

  template <- system.file("templates", "nis-study", package = "easyNIS")
  if (!nzchar(template) || !dir.exists(template)) {
    unlink(path, recursive = TRUE)
    cli::cli_abort("The packaged NIS study template is unavailable.")
  }

  files <- list.files(template, full.names = TRUE, no.. = TRUE)
  if (!length(files) || any(dir.exists(files)) ||
      !all(file.copy(files, path, overwrite = FALSE))) {
    unlink(path, recursive = TRUE)
    cli::cli_abort("Could not copy the packaged NIS study template.")
  }

  if (!file.rename(file.path(path, "gitignore"), file.path(path, ".gitignore"))) {
    unlink(path, recursive = TRUE)
    cli::cli_abort("Could not create the study output `.gitignore`.")
  }

  path
}
