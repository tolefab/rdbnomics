context("Right api_link and use_readLines")
library(rdbnomics)

test_that("api_link is NULL", {
  expect_identical(rdb_by_api_link(NULL), NULL)
})

test_that("api_link length is greater than one or equal to zero", {
  expect_error(rdb_by_api_link(c("url1", "url2")))
  expect_error(rdb_by_api_link(character()))
})

test_that("api_link is not a character string", {
  expect_error(rdb_by_api_link(0))
})

test_that("use_readLines is NULL", {
  expect_error(rdb_by_api_link("url", NULL))
})

test_that("use_readLines length is greater than one or equal to zero", {
  expect_error(rdb_by_api_link("url", c(TRUE, FALSE)))
  expect_error(rdb_by_api_link("url", logical()))
})

test_that("use_readLines is not a logical", {
  expect_error(rdb_by_api_link("url", "TRUE"))
})

test_that("curl_config is not a curl_handle object or a named list", {
  expect_error(rdb_by_api_link("url", curl_config = TRUE))
  expect_error(rdb_by_api_link("url", curl_config = list(1)))
})

test_that("filters is not a valid list", {
  expect_error(rdb_by_api_link("url", filters = TRUE))
  expect_error(rdb_by_api_link("url", filters = "filters"))
  expect_error(rdb_by_api_link("url", filters = list()))
  expect_error(rdb_by_api_link("url", filters = list(code = "interpolate", parameter = NULL)))
  expect_error(rdb_by_api_link("url", filters = list(code = "interpolate", parameters = list())))
  expect_error(rdb_by_api_link("url", filters = list(list(code = "interpolate", parameters = list(frequency = "quarterly", method = "spline")), list(code = "aggregate", parameters = list()))))
})
