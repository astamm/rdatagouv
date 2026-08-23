test_that("dg_summary() computes the expected metrics", {
  x <- data.frame(
    num = c(1, 2, NA, 4),
    chr = c("a", NA, "c", "d"),
    lgl = c(TRUE, FALSE, TRUE, FALSE)
  )

  out <- dg_summary(x, name = "test")

  expect_s3_class(out, "tbl_df")
  expect_equal(out$dataset, "test")
  expect_equal(out$n_vars, 3)
  expect_equal(out$n_numeric, 1)
  expect_equal(out$n_non_numeric, 2)
  expect_equal(out$n_rows, 4)
  # 2 missing values out of 12 cells
  expect_equal(out$prop_missing, 2 / 12)
  expect_gt(out$size_kb, 0)
})

test_that("dg_summary() defaults the name to the expression", {
  out <- dg_summary(iris)

  expect_equal(out$dataset, "iris")
})

test_that("dg_summary() reports all numeric variables when appropriate", {
  out <- dg_summary(mtcars, name = "mtcars")

  expect_equal(out$n_vars, 11)
  expect_equal(out$n_numeric, 11)
  expect_equal(out$n_non_numeric, 0)
})

test_that("dg_summary() handles a zero-row tibble", {
  out <- dg_summary(
    tibble::tibble(a = numeric(), b = character()),
    name = "empty"
  )

  expect_equal(out$n_rows, 0)
  expect_equal(out$prop_missing, 0)
})

test_that("dg_summary() handles an all-NA column", {
  x <- data.frame(a = c(NA, NA, NA))
  out <- dg_summary(x, name = "na_col")

  expect_equal(out$n_numeric, 0)
  expect_equal(out$prop_missing, 1)
})

test_that("dg_summary() errors on non-data-frame input", {
  expect_snapshot(error = TRUE, dg_summary(42))
})
