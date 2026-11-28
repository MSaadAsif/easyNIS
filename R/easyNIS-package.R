#' @details
#' Use [nis_open()] to open annual National Inpatient Sample (NIS) data as a
#' lazy DuckDB table, [nis_flag_dx()] or [nis_flag_pr()] to define a cohort,
#' and [nis_design()] to prepare a survey design. Use [nis_suppress()] to
#' review tables for disclosure risk before sharing.
#'
#' Start with the simulated files from [nis_example()] and the
#' [Getting started guide](https://msaadasif.github.io/easyNIS/articles/getting-started.html).
#' For licensed data, see the
#' [AHRQ HCUP NIS overview](https://hcup-us.ahrq.gov/nisoverview.jsp) for
#' documentation and access.
#'
#' @aliases easyNIS
#' @keywords internal
#' @examples
#' nis_open(nis_example(2020)) |>
#'   dplyr::count(YEAR) |>
#'   dplyr::collect()
"_PACKAGE"
