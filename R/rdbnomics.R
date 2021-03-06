#' Package rdbnomics
#'
#' DBnomics R client (<https://db.nomics.world/>).
#'
#' @docType package
#' @name rdbnomics
#' 
#' @import curl jsonlite data.table
#' 
NULL

if (getRversion() >= "2.15.1") {
  vars <- c(
    ".", ":=", "value", "dotI", "period", "period_start_day", "series_code",
    "filtered", "original_period", "series_name", "original_value",
    "period_middle_day"
  )
  utils::globalVariables(unique(vars))
}