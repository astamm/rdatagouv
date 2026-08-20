test_that("dg_refetch() re-fetches a single-file table by its URI", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"
  uri <- paste0("https://www.data.gouv.fr/datasets/", did, "#", rid)

  local_mocked_bindings(
    fetch_dataset = function(id) {
      mock_dataset(
        title = id,
        id = id,
        resources = list(mock_resource("csv", id = rid))
      )
    },
    read_resource = function(resource) mock_csv_data()
  )

  out <- dg_refetch(uri)

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 3)
  expect_named(out, c("a", "b"))
  expect_equal(dg_table_id(out), uri)
})

test_that("dg_refetch() still accepts the legacy '::' id", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"
  legacy <- paste(did, rid, sep = "::")
  uri <- paste0("https://www.data.gouv.fr/datasets/", did, "#", rid)

  local_mocked_bindings(
    fetch_dataset = function(id) {
      mock_dataset(
        title = id,
        id = id,
        resources = list(mock_resource("csv", id = rid))
      )
    },
    read_resource = function(resource) mock_csv_data()
  )

  out <- dg_refetch(legacy)

  expect_equal(dg_table_id(out), uri)
})

test_that("dg_refetch() accepts a table and reads its id attribute", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"
  uri <- paste0("https://www.data.gouv.fr/datasets/", did, "#", rid)

  local_mocked_bindings(
    fetch_dataset = function(id) {
      mock_dataset(
        title = id,
        id = id,
        resources = list(mock_resource("csv", id = rid))
      )
    },
    read_resource = function(resource) mock_csv_data()
  )

  tbl <- structure(data.frame(a = 1, b = "x"), id = uri)
  out <- dg_refetch(tbl)

  expect_s3_class(out, "tbl_df")
  expect_equal(dg_table_id(out), uri)
})

test_that("dg_refetch() re-fetches one file out of a ZIP", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"
  uri <- paste0(
    "https://www.data.gouv.fr/datasets/",
    did,
    "#",
    rid,
    "/notes.tsv"
  )

  local_mocked_bindings(
    fetch_dataset = function(id) {
      mock_dataset(
        title = id,
        id = id,
        resources = list(mock_resource("zip", id = rid))
      )
    },
    read_one_zip_file = function(resource, name) data.frame(c = 1, d = "x")
  )

  out <- dg_refetch(uri)

  expect_equal(nrow(out), 1)
  expect_named(out, c("c", "d"))
  expect_equal(dg_table_id(out), uri)
})

test_that("dg_refetch() forwards remove_na to format_tibble()", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"
  legacy <- paste(did, rid, sep = "::")

  local_mocked_bindings(
    fetch_dataset = function(id) {
      mock_dataset(
        title = id,
        id = id,
        resources = list(mock_resource("csv", id = rid))
      )
    },
    read_resource = function(resource) mock_csv_data()
  )

  out <- dg_refetch(legacy, remove_na = TRUE)

  # mock_csv_data() has one NA row; removing NA drops it.
  expect_equal(nrow(out), 2)
})

test_that("dg_refetch() errors on a malformed id", {
  expect_error(dg_refetch("not-a-table-id"), "Invalid table id")
})

test_that("dg_refetch() errors when the resource is not found", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"

  local_mocked_bindings(
    fetch_dataset = function(id) {
      mock_dataset(
        title = id,
        id = id,
        resources = list(mock_resource("csv", id = "other-resource"))
      )
    }
  )

  expect_error(
    dg_refetch(paste(did, rid, sep = "::")),
    "was not found on dataset"
  )
})

test_that("dg_refetch() errors on a table without an id attribute", {
  expect_error(dg_refetch(data.frame(a = 1)), "carries no table id")
})
