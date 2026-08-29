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
    read_resource = function(
      resource,
      col_types = NULL,
      use_tabular_types = FALSE
    ) {
      mock_csv_data()
    }
  )

  out <- dg_refetch(uri)

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 3)
  expect_named(out, c("a", "b"))
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
    read_resource = function(
      resource,
      col_types = NULL,
      use_tabular_types = FALSE
    ) {
      mock_csv_data()
    }
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
    read_one_zip_file = function(
      resource,
      name,
      col_types = NULL,
      use_tabular_types = FALSE
    ) {
      data.frame(c = 1, d = "x")
    }
  )

  out <- dg_refetch(uri)

  expect_equal(nrow(out), 1)
  expect_named(out, c("c", "d"))
  expect_equal(dg_table_id(out), uri)
})

test_that("a file inside a ZIP is addressable via its URI", {
  # A file within a ZIP is addressed by appending the file name to the resource
  # URI (`#<resource_id>/<file>`). Re-fetching that URI must return the data of
  # exactly that named file, not the first file of the ZIP.
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"
  uri <- paste0(
    "https://www.data.gouv.fr/datasets/",
    did,
    "#",
    rid,
    "/mapping.csv"
  )

  local_mocked_bindings(
    fetch_dataset = function(id) {
      mock_dataset(
        title = id,
        id = id,
        resources = list(mock_resource("zip", id = rid))
      )
    },
    read_one_zip_file = function(
      resource,
      name,
      col_types = NULL,
      use_tabular_types = FALSE
    ) {
      # The requested file name determines the returned data.
      data.frame(c = 1, d = name)
    }
  )

  out <- dg_refetch(uri)

  # Only the addressed file is returned, and its data reflects that file.
  expect_equal(nrow(out), 1)
  expect_named(out, c("c", "d"))
  expect_equal(out$d, "mapping.csv")
  expect_equal(
    dg_table_id(out),
    "https://www.data.gouv.fr/datasets/aaaaaaaaaaaaaaaaaaaaaaaa#99999999-9999-4999-8999-999999999999/mapping.csv"
  )
})

test_that("dg_refetch() forwards remove_na to format_tibble()", {
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
    read_resource = function(
      resource,
      col_types = NULL,
      use_tabular_types = FALSE
    ) {
      mock_csv_data()
    }
  )

  out <- dg_refetch(uri, remove_na = TRUE)

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
    dg_refetch(paste0(
      "https://www.data.gouv.fr/datasets/",
      did,
      "#",
      rid
    )),
    "was not found on dataset"
  )
})

test_that("dg_refetch() errors on a table without an id attribute", {
  expect_error(dg_refetch(data.frame(a = 1)), "carries no table id")
})

test_that("dg_refetch() forwards col_types to the parse step", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"
  uri <- paste0("https://www.data.gouv.fr/datasets/", did, "#", rid)

  captured <- NULL
  local_mocked_bindings(
    fetch_dataset = function(id) {
      mock_dataset(
        title = id,
        id = id,
        resources = list(mock_resource("csv", id = rid))
      )
    },
    read_resource = function(
      resource,
      col_types = NULL,
      use_tabular_types = FALSE
    ) {
      captured <<- col_types
      mock_csv_data()
    }
  )

  out <- dg_refetch(uri, col_types = c(date = "Date"))

  expect_equal(captured, c(date = "Date"))
  expect_s3_class(out, "tbl_df")
})
