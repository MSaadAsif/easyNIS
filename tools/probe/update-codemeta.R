root <- normalizePath(".", mustWork = TRUE)
description <- read.dcf(file.path(root, "DESCRIPTION"))
field <- function(name) {
  if (name %in% colnames(description)) unname(description[1L, name]) else NA_character_
}

authors <- eval(parse(text = field("Authors@R")), envir = globalenv())
person_metadata <- function(author) {
  author <- unclass(author)[[1L]]
  has_value <- function(value) length(value) > 0L && !is.na(value[[1L]]) && nzchar(value[[1L]])
  metadata <- list("@type" = "Person")
  if (has_value(author$given)) metadata$givenName <- author$given
  if (has_value(author$family)) metadata$familyName <- author$family
  if (has_value(author$email)) metadata$email <- author$email
  if (!is.null(author$comment) && "ORCID" %in% names(author$comment)) {
    metadata$`@id` <- paste0("https://orcid.org/", author$comment[["ORCID"]])
  }
  metadata
}

dependencies <- unlist(lapply(c("Depends", "Imports", "Suggests", "LinkingTo"), function(name) {
  value <- field(name)
  if (is.na(value) || !nzchar(value)) return(character())
  trimws(strsplit(value, ",", fixed = TRUE)[[1L]])
}), use.names = FALSE)

license <- sub(" \\+ file LICENSE$", "", field("License"))
if (identical(license, "AGPL-3")) license <- "AGPL-3.0-only"

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
  "softwareRequirements" = dependencies,
  "programmingLanguage" = list("@type" = "ComputerLanguage", "name" = "R"),
  "runtimePlatform" = dependencies[grepl("^R( |$)", dependencies)]
)
metadata <- metadata[!vapply(metadata, is.null, logical(1))]
jsonlite::write_json(metadata, file.path(root, "codemeta.json"), auto_unbox = TRUE, pretty = TRUE)
