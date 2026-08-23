test_that("dg_pull_dataset() returns a single tibble with its id as an attribute", {
  local_mocked_bindings(
    find_dataset = function(id) mock_dataset(title = id, id = id),
    read_first_parseable_resource = function(dataset) {
      list(data = mock_csv_data(), resource = mock_resource("csv", id = "rid"))
    }
  )

  out <- dg_pull_dataset("aaaaaaaaaaaaaaaaaaaaaaaa")

  # By default the result is a single tibble (not a list), with the id carried
  # as an attribute rather than a per-row column.
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 3)
  expect_named(out, c("a", "b"))
  expect_equal(
    dg_table_id(out),
    "https://www.data.gouv.fr/datasets/aaaaaaaaaaaaaaaaaaaaaaaa#rid"
  )
})

test_that("dg_pull_dataset() forwards remove_na to format_tibble()", {
  local_mocked_bindings(
    find_dataset = function(id) mock_dataset(title = id, id = id),
    read_first_parseable_resource = function(dataset) {
      list(data = mock_csv_data(), resource = mock_resource("csv"))
    }
  )

  out <- dg_pull_dataset("aaaaaaaaaaaaaaaaaaaaaaaa", remove_na = TRUE)

  expect_equal(nrow(out), 2)
})

test_that("dg_pull_dataset() returns the first file of a ZIP by default", {
  local_mocked_bindings(
    find_dataset = function(id) mock_dataset(title = id, id = id),
    read_first_parseable_resource = function(dataset) {
      list(
        data = list(
          "data.csv" = mock_csv_data(),
          "notes.tsv" = data.frame(c = 1, d = "x")
        ),
        resource = mock_resource("zip", id = "rid")
      )
    }
  )

  out <- dg_pull_dataset("aaaaaaaaaaaaaaaaaaaaaaaa")

  # The default is still a single tibble: the first parseable file of the ZIP.
  expect_s3_class(out, "tbl_df")
  expect_named(out, c("a", "b"))
  expect_equal(nrow(out), 3)
  expect_equal(
    dg_table_id(out),
    "https://www.data.gouv.fr/datasets/aaaaaaaaaaaaaaaaaaaaaaaa#rid/data.csv"
  )
})

test_that("dg_pull_dataset(all_files = TRUE) keeps every file of a ZIP", {
  local_mocked_bindings(
    find_dataset = function(id) mock_dataset(title = id, id = id),
    read_first_parseable_resource = function(dataset) {
      list(
        data = list(
          "data.csv" = mock_csv_data(),
          "notes.tsv" = data.frame(c = 1, d = "x")
        ),
        resource = mock_resource("zip", id = "rid")
      )
    }
  )

  out <- dg_pull_dataset("aaaaaaaaaaaaaaaaaaaaaaaa", all_files = TRUE)

  expect_type(out, "list")
  expect_named(out, c("data.csv", "notes.tsv"))
  expect_s3_class(out$`data.csv`, "tbl_df")
  expect_s3_class(out$notes.tsv, "tbl_df")
  expect_equal(nrow(out$`data.csv`), 3)
  expect_equal(
    dg_table_id(out$`data.csv`),
    "https://www.data.gouv.fr/datasets/aaaaaaaaaaaaaaaaaaaaaaaa#rid/data.csv"
  )
  expect_equal(
    dg_table_id(out$notes.tsv),
    "https://www.data.gouv.fr/datasets/aaaaaaaaaaaaaaaaaaaaaaaa#rid/notes.tsv"
  )
})

test_that("dg_pull_dataset() skips a resource that fails to parse", {
  # The first candidate cannot be read as a table; the second one can.
  local_mocked_bindings(
    find_dataset = function(id) mock_dataset(title = id, id = id),
    read_first_parseable_resource = function(dataset) {
      list(data = mock_csv_data(), resource = mock_resource("json"))
    }
  )

  out <- dg_pull_dataset("aaaaaaaaaaaaaaaaaaaaaaaa")

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 3)
  expect_named(out, c("a", "b"))
})
