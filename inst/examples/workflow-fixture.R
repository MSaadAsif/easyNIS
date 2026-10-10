# Shared entirely invented core for the installed workflow examples.
workflow_fixture <- function(year, multiplier = 1, shift = 0) {
  core <- easyNIS::nis_synthetic_data(year)$core[rep(1L, 120L),
    c("YEAR", "KEY_NIS", "HOSP_NIS", "NIS_STRATUM", "DISCWT", "LOS", "I10_DX1")]
  core$KEY_NIS <- sprintf("%06d", seq_len(nrow(core)))
  hospital <- rep(1:4, each = 30L)
  core$HOSP_NIS <- sprintf("%04d", hospital)
  core$NIS_STRATUM <- (hospital - 1L) %/% 2L + 1L
  core$DISCWT <- multiplier * (hospital + 1)
  core$LOS <- rep(c(0, 2, 4), 40L) + hospital + shift
  core$LOS[as.vector(outer(c(1L, 3L, 5L), c(0L, 30L, 60L, 90L), "+"))] <- NA_real_
  core$I10_DX1 <- rep(c("A001", "B001"), 60L)
  core$rare <- as.integer(seq_len(nrow(core)) %in% c(1L, 3L, 5L))
  core
}
