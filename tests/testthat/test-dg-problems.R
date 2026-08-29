# Tests for the dg_problems() accessor.

test_that("dg_problems() returns NULL for a table with no problems", {
  expect_null(dg_problems(iris))
  expect_null(dg_problems(data.frame(a = 1)))
})

test_that("dg_problems() returns a tibble with a problems-bearing table", {
  tbl <- parse_resource_file(local_messy_date_csv(5000), "csv")
  problems <- dg_problems(tbl)

  expect_s3_class(problems, "data.frame")
  expect_equal(names(problems), c("row", "col", "expected", "actual"))
  expect_gt(nrow(problems), 0)
})

test_that("dg_problems() returns NULL for a table without the attribute", {
  tbl <- structure(data.frame(a = 1:3), id = "https://example.org/x")
  expect_null(dg_problems(tbl))
})
