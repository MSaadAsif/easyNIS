source("tools/probe/hcup-url-proxy.R")

hcup <- "https://hcup-us.ahrq.gov/fixture/"
ok <- paste0(hcup, "available")
missing <- paste0(hcup, "missing")
offline <- paste0(hcup, "offline")
other <- "https://example.org/unavailable"
lookalike <- "https://hcup-us.ahrq.gov.example.org/unavailable"
page <- function(url, content, warning = "") {
  list(
    status_code = 200L,
    content = charToRaw(paste(
      "Title: Invented HCUP page",
      paste("URL Source:", url),
      warning,
      "Markdown Content:",
      content,
      sep = "\n"
    ))
  )
}
responses <- stats::setNames(
  list(
    page(ok, "Invented content."),
    page(missing, "The page you have requested is not found.", "Warning: Target URL returned error 404: Not Found")
  ),
  c(ok, missing)
)
fetch <- function(url) {
  stopifnot(url %in% c(ok, missing, offline))
  if (identical(url, offline)) {
    stop("Invented proxy timeout.")
  }
  responses[[url]]
}
positions <- function(...) lapply(c(...), function(url) list(line = url))
stopifnot(
  nrow(hcup_proxy_checks(list(status = TRUE), function(url) stop("Direct pass must skip proxy."))) == 0L,
  nrow(hcup_proxy_checks(list(status = FALSE, positions = positions(other, lookalike)), fetch)) == 0L,
  identical(
    hcup_proxy_checks(list(status = FALSE, positions = positions(ok, missing, offline)), fetch),
    data.frame(url = c(ok, missing, offline), reachable = c(TRUE, FALSE, FALSE))
  ),
  !hcup_proxy_reachable(page(missing, "The page you have requested is not found."), missing),
  !hcup_proxy_reachable(page(ok, "Invented content."), missing),
  !hcup_proxy_reachable(list(status_code = 404L, content = responses[[ok]]$content), ok),
  !hcup_proxy_reachable(page(ok, ""), ok)
)
result <- hcup_proxy_checks(list(status = FALSE, positions = positions(ok, missing, offline)), fetch)
stopifnot(
  hcup_proxy_resolved(positions(ok), result),
  !hcup_proxy_resolved(positions(ok, missing), result),
  !hcup_proxy_resolved(positions(ok, offline), result),
  !hcup_proxy_resolved(positions(ok, other), result),
  !hcup_proxy_resolved(positions(ok), NULL)
)
cat("HCUP URL fallback passed invented direct, proxy, missing and transport cases.\n")
