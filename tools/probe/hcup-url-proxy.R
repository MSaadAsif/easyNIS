hcup_proxy_fetch <- function(url) {
  handle <- curl::new_handle(timeout = 25, followlocation = FALSE)
  curl::curl_fetch_memory(paste0("https://r.jina.ai/", url), handle)
}

hcup_proxy_reachable <- function(response, url) {
  if (is.null(response) || !identical(response$status_code, 200L) || !is.raw(response$content)) {
    return(FALSE)
  }
  lines <- strsplit(rawToChar(response$content), "\r?\n")[[1L]]
  content_start <- match("Markdown Content:", trimws(lines))
  if (is.na(content_start) || content_start == length(lines)) {
    return(FALSE)
  }
  headers <- trimws(utils::head(lines, content_start - 1L))
  content <- trimws(lines[(content_start + 1L):length(lines)])
  source <- headers[startsWith(headers, "URL Source:")]
  identical(source, paste("URL Source:", url)) &&
    any(startsWith(headers, "Title: ") & nchar(headers) > nchar("Title: ")) &&
    !any(startsWith(headers, "Warning:")) &&
    any(nzchar(content)) &&
    !any(grepl("the page you have requested is not found", tolower(content), fixed = TRUE))
}

hcup_proxy_checks <- function(check, fetch = hcup_proxy_fetch) {
  urls <- if (identical(check$status, FALSE)) {
    unique(vapply(check$positions, function(position) position$line, character(1)))
  } else {
    character()
  }
  urls <- urls[grepl("^https?://hcup-us[.]ahrq[.]gov(/|$)", urls)]
  reachable <- vapply(
    urls,
    function(url) {
      target <- sub("#.*$", "", url)
      tryCatch(hcup_proxy_reachable(fetch(target), target), error = function(error) FALSE)
    },
    logical(1),
    USE.NAMES = FALSE
  )
  data.frame(url = urls, reachable = reachable)
}

hcup_proxy_resolved <- function(positions, results) {
  verified <- results$url[results$reachable %in% TRUE]
  length(positions) > 0L &&
    all(vapply(positions, function(position) position$line %in% verified, logical(1)))
}
