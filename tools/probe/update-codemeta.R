root <- normalizePath(".", mustWork = TRUE)
description <- read.dcf(file.path(root, "DESCRIPTION"))
field <- function(name) {
  if (name %in% colnames(description)) unname(description[1L, name]) else NA_character_
}

authors <- eval(parse(text = field("Authors@R")), envir = globalenv())
author_id <- function(author) {
  orcid <- author$comment[["ORCID"]]
  if (length(orcid)) paste0("https://orcid.org/", orcid) else NULL
}
person_metadata <- function(author) {
  author <- unclass(author)[[1L]]
  has_value <- function(value) length(value) > 0L && !is.na(value[[1L]]) && nzchar(value[[1L]])
  metadata <- list("@type" = "Person")
  if (has_value(author$given)) {
    metadata$givenName <- author$given
  }
  if (has_value(author$family)) {
    metadata$familyName <- author$family
  }
  if (has_value(author$email)) {
    metadata$email <- author$email
  }
  if (!is.null(author$comment) && "ORCID" %in% names(author$comment)) {
    metadata$`@id` <- paste0("https://orcid.org/", author$comment[["ORCID"]])
  }
  metadata
}

dependencies <- unlist(
  lapply(c("Depends", "Imports", "Suggests", "LinkingTo"), function(name) {
    value <- field(name)
    if (is.na(value) || !nzchar(value)) {
      return(character())
    }
    trimws(strsplit(value, ",", fixed = TRUE)[[1L]])
  }),
  use.names = FALSE
)

maintainers <- unname(lapply(
  authors[vapply(
    authors,
    function(author) {
      "cre" %in% author$role || identical(author$comment[["project_role"]], "co-maintainer")
    },
    logical(1)
  )],
  function(author) {
    id <- author_id(author)
    if (is.null(id)) paste(author$given, author$family) else id
  }
))

license <- sub(" \\+ file LICENSE$", "", field("License"))
if (identical(license, "AGPL-3")) {
  license <- "AGPL-3.0-only"
}

metadata <- list(
  "@context" = "https://doi.org/10.5063/schema/codemeta-2.0",
  "@type" = "SoftwareSourceCode",
  "identifier" = field("Package"),
  "name" = field("Package"),
  "description" = field("Description"),
  "version" = field("Version"),
  "license" = license,
  "codeRepository" = trimws(strsplit(field("URL"), ",", fixed = TRUE)[[1L]][[1L]]),
  "issueTracker" = field("BugReports"),
  "author" = unname(lapply(authors, person_metadata)),
  "maintainer" = maintainers,
  "softwareRequirements" = dependencies,
  "programmingLanguage" = list("@type" = "ComputerLanguage", "name" = "R"),
  "runtimePlatform" = dependencies[grepl("^R( |$)", dependencies)]
)
metadata <- metadata[!vapply(metadata, is.null, logical(1))]
path <- file.path(root, "codemeta.json")
output <- as.character(jsonlite::toJSON(metadata, auto_unbox = TRUE, pretty = TRUE))
args <- commandArgs(trailingOnly = TRUE)
if (identical(args, "--check")) {
  current <- paste(readLines(path, warn = FALSE), collapse = "\n")
  if (!identical(current, output)) stop("Run tools/probe/update-codemeta.R to refresh CodeMeta.", call. = FALSE)
} else if (!length(args)) {
  writeLines(output, path, useBytes = TRUE)
} else {
  stop("Usage: Rscript tools/probe/update-codemeta.R [--check]", call. = FALSE)
}
