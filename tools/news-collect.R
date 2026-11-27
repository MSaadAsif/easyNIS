#!/usr/bin/env Rscript

collect_news <- function() {
  files <- sort(list.files("news", "[.]md$", full.names = TRUE), method = "radix")
  if (!length(files)) {
    return(invisible(NULL))
  }

  news <- readLines("NEWS.md", encoding = "UTF-8")
  versions <- which(startsWith(news, "# "))
  dev <- match("# easyNIS (development version)", news)
  if (is.na(dev)) {
    stop("Missing development heading in NEWS.md.", call. = FALSE)
  }
  end <- min(c(versions[versions > dev], length(news) + 1L)) - 1L
  sections <- which(startsWith(news, "## "))
  sections <- sections[sections > dev & sections <= end]
  entries <- list()

  # Validate all fragments before changing NEWS.md or removing any input.
  for (file in files) {
    lines <- readLines(file, encoding = "UTF-8")
    content <- which(nzchar(trimws(lines)))
    headings <- grep("^ {0,3}#{1,6}([[:space:]]|$)", lines)
    target <- dev
    if (length(headings)) {
      if (!identical(headings, content[1L])) {
        stop(file, ": use at most one section heading at the start.", call. = FALSE)
      }
      heading <- lines[headings]
      target <- sections[match(heading, news[sections])]
      if (is.na(target)) {
        stop(file, ": unknown development section ", heading, call. = FALSE)
      }
      content <- content[-1L]
    }
    if (!length(content)) {
      stop(file, ": empty fragment.", call. = FALSE)
    }
    key <- as.character(target)
    entries[[key]] <- c(entries[[key]], lines[min(content):max(content)], "")
  }

  # Insert from the bottom up so the original heading positions stay valid.
  for (target in sort(as.integer(names(entries)), decreasing = TRUE)) {
    block <- entries[[as.character(target)]]
    if (identical(news[target + 1L], "")) {
      news <- append(news, block, after = target + 1L)
    } else {
      news <- append(news, c("", block), after = target)
    }
  }
  writeLines(news, "NEWS.md", useBytes = TRUE)
  if (!all(file.remove(files))) {
    stop("Could not remove all collected fragments.", call. = FALSE)
  }
}

collect_news()
