nis_comorbidity_spec <- function(method) {
  refined <- c("elixhauser_ahrq_icd10", paste0("elixhauser_ahrq", 2022:2026))
  charlson <- c("charlson_quan2005", "charlson_quan2011", "charlson_deyo1992")
  if (
    !is.character(method) ||
      length(method) != 1L ||
      !method %in%
        c(
          refined,
          charlson,
          "elixhauser_ahrq2027",
          "elixhauser_quan2005",
          "elixhauser_ahrq_web",
          "elixhauser_elixhauser1998"
        )
  ) {
    cli::cli_abort("`method` must be a supported Elixhauser or Charlson method name.")
  }
  if (method %in% refined) {
    return(nis_cmrb_refined(method))
  }
  if (method == "elixhauser_ahrq2027") {
    return(nis_cmrb_ahrq2027())
  }
  rlang::check_installed("medicalcoder", version = "0.10.0", reason = "to look up comorbidity mappings.")
  if (method %in% refined) {
    return(nis_cmrb_refined(method))
  }
  if (method %in% charlson) {
    return(nis_cmrb_charlson(method))
  }
  nis_cmrb_legacy_elixhauser(method)
}

nis_cmrb_refined <- function(method) {
  codes <- medicalcoder::get_elixhauser_codes()
  codes <- codes[codes[[method]] %in% 1L & codes$icdv == 10L & codes$dx == 1L, ]
  weights <- nis_cmrb_elixhauser_weights(method)
  poa <- medicalcoder::get_elixhauser_poa()
  unrestricted <- poa$condition[poa[[method]] %in% 1L & poa$poa_required == 0L]

  # The exported dictionary encodes some pairs as one category. Some
  # components inherit any-POA evidence and others need positive POA evidence.
  always <- c(
    DRUG_ABUSEPSYCHOSES = "DRUG_ABUSE",
    HFHTN_CX = "HTN_CX",
    HTN_CXRENLFL_SEV = "HTN_CX",
    HFHTN_CXRENLFL_SEV = "HTN_CX",
    ALCOHOLLIVER_MLD = "ALCOHOL",
    VALVE_AUTOIMMUNE = "AUTOIMMUNE",
    LIVER_MLD_NEURO = "LIVER_MLD",
    LIVER_MLD_NEURO = "NEURO_OTH",
    NEURO_OTH_SEIZ = "NEURO_OTH",
    NEURO_OTH_SEIZ = "NEURO_SEIZ",
    LIVER_MLD_PULMCIRC = "LIVER_MLD",
    LIVER_MLD_PULMCIRC = "PULMCIRC"
  )
  positive <- c(
    DRUG_ABUSEPSYCHOSES = "PSYCHOSES",
    HFHTN_CX = "HF",
    HTN_CXRENLFL_SEV = "RENLFL_SEV",
    HFHTN_CXRENLFL_SEV = "HF",
    HFHTN_CXRENLFL_SEV = "RENLFL_SEV",
    CBVD_SQLAPARALYSIS = "PARALYSIS",
    CBVD_SQLAPARALYSIS = "CBVD_SQLA",
    ALCOHOLLIVER_MLD = "LIVER_MLD",
    VALVE_AUTOIMMUNE = "VALVE"
  )
  conditions <- sort(unique(codes$condition))
  map <- nis_cmrb_medicalcoder_masks(conditions, codes, codes$poaexempt %in% 1L)
  spec <- nis_cmrb_refined_spec(map, c(conditions, "CBVD"), weights)
  spec$evidence <- list(unrestricted = unrestricted, always = always, positive = positive)
  spec
}

nis_cmrb_medicalcoder_masks <- function(conditions, codes, exempt) {
  map <- nis_cmrb_masks(conditions, codes[!exempt, ], codes[exempt, ], codes)
  names(map$values) <- c("id", "nonexempt", "exempt", "observed")
  map
}

nis_cmrb_ahrq2027 <- function() {
  read_table <- function(table) {
    path <- system.file("extdata", paste0("elixhauser-2027-", table, ".csv"), package = "easyNIS")
    utils::read.csv(path)
  }
  codes <- read_table("codes")
  codes$icdv <- 10L
  codes$dx <- 1L
  coefficients <- read_table("weights")
  conditions <- coefficients$condition
  weights <- lapply(coefficients[c("mortality_index", "readmission_index")], stats::setNames, conditions)
  unrestricted <- codes[codes$condition %in% conditions[coefficients$requires_poa == 0L], ]
  npoa <- nis_cmrb_expand(codes, c(CBVD_POA = "CBVD_NPOA"))
  bits <- c(setdiff(conditions, "CBVD"), "CBVD_POA", "CBVD_SQLA", "CBVD_NPOA")
  masks <- nis_cmrb_masks(bits, codes, rbind(unrestricted, npoa), unrestricted)
  masks$values$fiscal_exempt <- codes$exempt_versions[match(substring(masks$values$id, 6L), codes$code)]
  spec <- nis_cmrb_refined_spec(masks, conditions, weights)
  spec$fiscal_exemptions <- TRUE
  spec
}

nis_cmrb_refined_spec <- function(map, conditions, weights) {
  list(
    map = map,
    conditions = conditions,
    weights = weights,
    counted = names(weights$mortality_index),
    systems = 10L,
    poa = TRUE,
    derived = list(CBVD = "CBVD_POA OR (CBVD_SQLA AND NOT CBVD_NPOA)"),
    exclude = c(
      DIAB_UNCX = "DIAB_CX",
      HTN_UNCX = "HTN_CX",
      CANCER_SOLID = "CANCER_METS",
      CANCER_NSITU = "CANCER_METS OR CANCER_SOLID",
      LIVER_MLD = "LIVER_SEV",
      RENLFL_MOD = "RENLFL_SEV"
    )
  )
}

nis_cmrb_charlson <- function(method) {
  codes <- medicalcoder::get_charlson_codes()
  weights <- medicalcoder::get_charlson_index_scores()
  weight <- stats::setNames(weights[[method]], weights$condition)
  weight <- weight[!is.na(weight)]
  systems <- if (method == "charlson_deyo1992") 9L else c(9L, 10L)
  # Quan 2011 updates the weights used with the Quan 2005 coding algorithm.
  coding <- if (method == "charlson_quan2011") "charlson_quan2005" else method
  codes <- codes[codes[[coding]] %in% 1L & codes$condition %in% names(weight), ]
  conditions <- names(weight)
  list(
    map = nis_cmrb_medicalcoder_masks(conditions, codes, rep(FALSE, nrow(codes))),
    conditions = conditions,
    weights = list(cci = weight),
    counted = conditions,
    systems = systems,
    procedures = any(codes$dx == 0L & codes$icdv %in% systems),
    evidence = list(),
    poa = TRUE,
    derived = list(),
    exclude = c(mld = "msld", dm = "dmc", mal = "mst")
  )
}

nis_cmrb_legacy_elixhauser <- function(method) {
  codes <- medicalcoder::get_elixhauser_codes()
  codes <- codes[codes[[method]] %in% 1L & codes$dx == 1L, ]
  weights <- nis_cmrb_elixhauser_weights(method)
  conditions <- unique(codes$condition)
  list(
    map = nis_cmrb_masks(conditions, codes, codes, codes),
    conditions = c(conditions, "HTN_C"),
    weights = weights,
    counted = names(weights$mortality_index),
    systems = sort(unique(codes$icdv)),
    poa = FALSE,
    derived = list(HTN_C = "HTN_UNCX OR HTN_CX"),
    exclude = c(HTN_UNCX = "HTN_CX", DM = "DMCX", TUMOR = "METS")
  )
}

nis_cmrb_elixhauser_weights <- function(method) {
  weights <- medicalcoder::get_elixhauser_index_scores()
  scores <- stats::setNames(weights[[method]], weights$condition)
  list(
    mortality_index = scores[weights$index == "mortality" & !is.na(scores)],
    readmission_index = scores[weights$index == "readmission" & !is.na(scores)]
  )
}

nis_cmrb_expand <- function(codes, expansion) {
  index <- match(codes$condition, names(expansion))
  rows <- which(!is.na(index))
  expanded <- merge(
    codes[rows, ],
    data.frame(condition = names(expansion), component = unname(expansion)),
    by = "condition"
  )
  expanded$condition <- expanded$component
  expanded[names(codes)]
}

nis_cmrb_masks <- function(conditions, yes, no, unknown) {
  bits <- stats::setNames(2^(seq_along(conditions) - 1L), conditions)
  mask <- function(codes) {
    if (!nrow(codes)) {
      return(rep(0, length(ids)))
    }
    id <- paste(codes$icdv, codes$dx, codes$code, sep = ":")
    pairs <- unique(data.frame(id = id, bit = unname(bits[codes$condition])))
    sums <- tapply(pairs$bit, pairs$id, sum)
    sums[match(ids, names(sums))]
  }
  ids <- unique(unlist(lapply(list(yes, no, unknown), function(codes) {
    paste(codes$icdv, codes$dx, codes$code, sep = ":")
  })))
  values <- data.frame(id = ids, yes = mask(yes), no = mask(no), unknown = mask(unknown))
  values[is.na(values)] <- 0
  list(values = values, bits = bits)
}
