pr_timing_parity_data <- function() {
  dplyr::tibble(
    I10_PR1 = "IX",
    I10_PR2 = "OUT",
    I10_PR3 = c("IDX", "IDX", "OTHER", "OTHER", "OTHER"),
    I10_PR4 = "ALT",
    PRDAY1 = c(0L, -99L, 0L, -99L, -99L),
    PRDAY2 = c(1, 1, -99, NA_real_, 1),
    PRDAY3 = c(2L, 1L, 0L, -99L, 1L),
    PRDAY4 = c(3L, -99L, 0L, 1L, 1L),
    YEAR = 2018L,
    PRVER = c(10L, 10L, 10L, 10L, 9L)
  )
}
