# Import the original stacks in https://www.speedscope.app/ for an R flame graph.
args <- commandArgs(TRUE)
for (path in list.dirs(args[[1]], recursive = FALSE, full.names = TRUE)) {
  file <- file.path(path, "Rprof.out")
  if (!file.exists(file)) {
    next
  }
  lines <- readLines(file)
  if (length(lines) <= 1L) {
    next
  }
  raw <- regmatches(lines[-1L], gregexpr('"[^"]+"', lines[-1L]))
  stacks <- lapply(raw, function(x) rev(gsub('"', "", x, fixed = TRUE)))
  stacks <- Filter(length, stacks)
  frames <- unique(unlist(stacks))
  tick <- as.numeric(sub("^.*sample.interval=([0-9]+).*$", "\\1", lines[[1L]])) / 1000
  chart <- list(
    "$schema" = "https://www.speedscope.app/file-format-schema.json",
    shared = list(frames = lapply(frames, function(x) list(name = x))),
    profiles = list(list(
      type = "sampled",
      name = basename(path),
      unit = "milliseconds",
      startValue = 0,
      endValue = tick * length(stacks),
      samples = lapply(stacks, function(x) as.list(match(x, frames) - 1L)),
      weights = as.list(rep(tick, length(stacks)))
    ))
  )
  jsonlite::write_json(chart, file.path(path, "flamegraph.speedscope.json"), auto_unbox = TRUE)
}
