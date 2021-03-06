.rdb <- function(
  api_link,
  use_readLines = getOption("rdbnomics.use_readLines"),
  curl_config = getOption("rdbnomics.curl_config"),
  filters = getOption("rdbnomics.filters")
) {
  # Checking 'api_link'
  if (is.null(api_link)) { return(NULL) }
  check_argument(api_link, "character")

  # Checking 'use_readLines'
  check_argument(use_readLines, "logical")

  # Checking 'filters'
  if (!is.null(filters)) {
    check_filter <- filter_type(filters)
    if (check_filter == "ko") {
      stop(
        paste0(
          "If only one filter is applied then 'filters' must be a named list ",
          "with two elements : 'code' and 'parameters'."
        ),
        "\n",
        paste0(
          "'code' is a character string and 'parameters' is an empty list ",
          "or a named list ('frequency' and 'method')."
        ),
        "\n",
        "For more informations, visit <https://editor.nomics.world/filters>.",
        "\n",
        paste0(
          "If multiple filters are applied then 'filters' must be a unnamed ",
          "list of valid filters."
        ),
        call. = FALSE
      )
    }

    if (use_readLines) {
      warning(
        "When applying filters, the curl functions must be used.",
        "\n",
        "As a consequence, 'use_readLines' is set to FALSE.",
        call. = FALSE
      )
      use_readLines <- FALSE
    }
  }

  # Fetching data
  DBlist <- get_data(api_link, use_readLines, curl_config)

  # Getting API version
  api_version <- get_version(DBlist)

  if (api_version == 21) {
    data_elt <- "data"
  } else if (api_version == 22) {
    data_elt <- "docs"
  } else {
    stop(
      paste0("Don't know what to do for API version ", api_version, "."),
      call. = FALSE
    )
  }

  # If data is empty, return NULL
  if (is.data.frame(DBlist$series[[data_elt]])) {
    if (nrow(DBlist$series[[data_elt]]) <= 0) {
      return(NULL)
    }
  }

  if (inherits(DBlist$series[[data_elt]], "list")) {
    if (length(DBlist$series[[data_elt]]) <= 0) {
      return(NULL)
    }
  }

  # Checking if the limit has been reached
  num_found <- DBlist$series$num_found
  limit <- DBlist$series$limit
  
  # Additional informations to translate geo, freq, ...
  if (!getOption("rdbnomics.translate_codes")) {
    additional_geo_column <- additional_geo_mapping <- NULL
  } else {
    additional_geo_column <- get_geo_colname(DBlist)
    additional_geo_mapping <- get_geo_names(DBlist, additional_geo_column)
    # Check coherence
    if (is.null(additional_geo_column) | is.null(additional_geo_mapping)) {
      additional_geo_column <- additional_geo_mapping <- NULL
    }
    if (!is.null(additional_geo_column) & !is.null(additional_geo_mapping)) {
      if (length(additional_geo_column) != length(additional_geo_mapping)) {
        if (
          length(additional_geo_column) == 0 |
          length(additional_geo_mapping) == 0
        ) {
          additional_geo_column <- additional_geo_mapping <- NULL
        } else {
          check_agc <- sapply(additional_geo_column, paste0, collapse = "|")
          additional_geo_column <- stats::setNames(additional_geo_column, check_agc)

          check_agm <- sapply(additional_geo_mapping, function(u) {
            u1 <- u$dataset_code[1]
            u2 <- colnames(u)[2:3]
            u2 <- paste0(u2, collapse = "|")
            paste0(u1, "|", u2)
          })
          additional_geo_mapping <- stats::setNames(additional_geo_mapping, check_agm)

          keep <- intersect(check_agc, check_agm)

          if (length(keep) == 0) {
            additional_geo_column <- additional_geo_mapping <- NULL
          } else {
            additional_geo_column <- additional_geo_column[sort(keep)]
            additional_geo_mapping <- additional_geo_mapping[sort(keep)]
          }
        }
      }
    }
  }
  
  # Extracting data
  DBdata <- list(DBlist$series[[data_elt]])
  rm(DBlist)

  if (num_found > limit) {
    DBdata0 <- DBdata
    rm(DBdata)

    sequence <- seq(1, floor(num_found / limit), 1)

    # Modifying link
    if (grepl("offset=", api_link)) {
      api_link <- gsub("\\&offset=[0-9]+", "", api_link)
      api_link <- gsub("\\?offset=[0-9]+", "", api_link)
    }
    sep <- ifelse(grepl("\\?", api_link), "&", "?")

    DBdata <- lapply(sequence, function(i) {
      # Modifying link
      tmp_api_link <- paste0(api_link, sep, "offset=", i * limit)
      # Fetching data
      DBlist <- get_data(tmp_api_link, use_readLines, curl_config)

      # Extracting data
      DBlist$series[[data_elt]]
    })

    DBdata <- append(DBdata, DBdata0, 0)
    rm(DBdata0)
  }

  # Transform data.frames inside DBdata
  if (list_has_dataframe(DBdata)) {
    DBdata <- lapply(DBdata, dataframe_to_columns)
  }

  # Transforming into data.table
  DBdata <- lapply(DBdata, data.table::setDT)
  # Gathering data
  DBdata <- data.table::rbindlist(DBdata, use.names = TRUE, fill = TRUE)
  # Expanding list columns
  DBdata <- deploy(DBdata)
  # To reproduce the Python module, we copy the 'value' element
  DBdata[
    ,
    original_value := format(
      value, scientific = FALSE, decimal.mark = ".", big.mark = "", trim = TRUE,
      drop0trailing = TRUE
    )
  ]
  # Transforming date format and timestamp format
  transform_date_timestamp(DBdata)

  # Modifying column names
  tryCatch({
    data.table::setnames(DBdata, "period", "original_period")
  }, error = function(e) {
    stop(
      paste0(
        "The retrieved dataset doesn't have a column named 'period', it's not ",
        "normal please check <db.nomics.world>."
      ),
      call. = FALSE
    )
  })

  tryCatch({
    data.table::setnames(DBdata, "period_start_day", "period")
  }, error = function(e) {
    stop(
      paste0(
        "The retrieved dataset doesn't have a column named ",
        "'period_start_day', it's not normal please check <db.nomics.world>."
      ),
      call. = FALSE
    )
  })

  # DBnomics editor
  if (!is.null(filters)) {
    if (check_filter == "notlist") {
      filters <- list(filters)
    }

    # Filters are applied by 'series_code'
    codes <- unique(DBdata$series_code)
    multicodes <- length(codes) > 1

    # A progress bar is displayed if there are more than one code
    if (multicodes & getOption("rdbnomics.progress_bar")) {
      pb <- utils::txtProgressBar(min = 0, max = length(codes), style = 3)
    }

    DBlist <- lapply(seq_along(codes), function(i) {
      x <- codes[i]
      tmpdata <- DBdata[series_code == x]

      # 'series' for the POST request
      series <- list(
        frequency = unique(tmpdata$`@frequency`),
        period_start_day = tmpdata$period,
        value = tmpdata$value
      )

      # POST request header
      headers <- list(
        "Content-Type" = "application/json", 
        "Accept" = "application/json"
      )

      # POST elements
      opt <- list(
        customrequest = "POST",
        postfields = as.character(
          jsonlite::toJSON(
            list(filters = filters, series = list(series)),
            auto_unbox = TRUE
          )
        )
      )

      # Editor url
      editor_link <- paste0(
        getOption("rdbnomics.editor_base_url"), "/api/v",
        getOption("rdbnomics.editor_version"), "/apply"
      )

      request <- get_data(editor_link, FALSE, curl_config, headers, opt)
      request <- dataframe_to_columns(request$filter_results$series)
      data.table::setDT(request)
      request <- deploy(request)
      request[
        ,
        original_value := format(
          value, scientific = FALSE, decimal.mark = ".", big.mark = "",
          trim = TRUE, drop0trailing = TRUE
        )
      ]
      transform_date_timestamp(request)

      # Some columns from the original dataset will be replaced by the
      # filtered dataset
      tmpdata <- remove_columns(
        tmpdata,
        c(
          "@frequency", "original_period", "period", "value", "original_value",
          "indexed_at", "series_code"
        )
      )
      try(
        {
          cols_to_remove <- sapply(additional_geo_column, `[[`, 2)
          tmpdata <- remove_columns(tmpdata, cols_to_remove)
          rm(cols_to_remove)
        },
        silent = TRUE
      )
      tmpdata <- remove_columns(tmpdata, "^observation", expr = TRUE)
      # The aim is to keep only unique informations
      tmpdata <- unique(tmpdata)
      if (nrow(tmpdata) > 1) {
        reduce_to_one(tmpdata)
        tmpdata <- unique(tmpdata)
      }

      if (multicodes & getOption("rdbnomics.progress_bar")) {
        utils::setTxtProgressBar(pb, i)
      }

      # Entire dataset with replaced columns
      cbind(tmpdata, request)
    })

    if (multicodes & getOption("rdbnomics.progress_bar")) { close(pb) }
    
    DBlist <- stats::setNames(DBlist, codes)
    DBlist <- data.table::rbindlist(
      DBlist, use.names = TRUE, fill = TRUE, idcol = "series_code"
    )

    # Add filtered suffix
    DBlist[, series_code := paste0(series_code, "_filtered")]
    DBlist[, series_name := paste(series_name, "(filtered)")]

    # We rename the column 'frequency'
    try(
      setnames(
        DBlist,
        "frequency",
        grep("^[@]*frequency$", colnames(DBdata), value = TRUE)
      ),
      silent = TRUE
    )

    tryCatch({
      data.table::setnames(DBlist, "period", "original_period")
    }, error = function(e) {
      stop(
        paste0(
          "The retrieved dataset doesn't have a column named 'period', it's not ",
          "normal please check <db.nomics.world>."
        ),
        call. = FALSE
      )
    })
    # In case of different classes, the class of the column 'original_period'
    # is set to 'character'
    if (
      inherits(DBdata$original_period, "character") &
      !inherits(DBlist$original_period, "character")
    ) {
      DBlist[, original_period := as.character(original_period)]
    }
    if (
      !inherits(DBdata$original_period, "character") &
      inherits(DBlist$original_period, "character")
    ) {
      DBdata[, original_period := as.character(original_period)]
    }

    tryCatch({
      data.table::setnames(DBlist, "period_start_day", "period")
    }, error = function(e) {
      stop(
        paste0(
          "The retrieved dataset doesn't have a column named ",
          "'period_start_day', it's not normal please check <db.nomics.world>."
        ),
        call. = FALSE
      )
    })

    # Add boolean to distinct be filtered and non-filtered series
    DBdata[, filtered := FALSE]
    DBlist[, filtered := TRUE]

    # For R 3.1
    diff_cols <- setdiff(colnames(DBlist), colnames(DBdata))
    if (length(diff_cols) > 0) {
      DBdata[, period_middle_day := as.Date(NA)]
    }

    DBdata <- list(DBdata, DBlist)
    DBdata <- data.table::rbindlist(DBdata, use.names = TRUE, fill = TRUE)
  }

  # Additional informations translations
  if (!is.null(additional_geo_column) & !is.null(additional_geo_mapping)) {
    for (i in seq_along(additional_geo_mapping)) {
      addcol <- additional_geo_column[[i]][3]
      suffix <- ""
      if (addcol %in% colnames(DBdata)) {
        suffix <- "_add"
        newcol <- paste0(addcol, suffix)
        setnames(additional_geo_mapping[[i]], addcol, newcol)
      }

      DBdata <- merge(
        DBdata, additional_geo_mapping[[i]],
        by = c("dataset_code", additional_geo_column[[i]][2]),
        all.x = TRUE, all.y = FALSE, sort = FALSE, allow.cartesian = FALSE
      )

      if (suffix != "") {
        DBdata[, (addcol) := ifelse(is.na(get(newcol)), get(addcol), get(newcol))]
        DBdata[, (newcol) := NULL]
      }
    }
  }

  # We reorder the columns by their names
  setcolorder(DBdata, sort(colnames(DBdata)))

  DBdata[]
}
