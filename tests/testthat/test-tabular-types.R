# Tests for the tabular-API profile-backed column typing (use_tabular_types).
# Covers the internal helpers in R/utils.R and their wiring through
# dg_pull_dataset()/dg_refetch(). All network access is mocked.

test_that("python_type_to_col() maps the csv-detective vocabulary to shorthand", {
  expect_equal(python_type_to_col("string"), "character")
  expect_equal(python_type_to_col("int"), "integer")
  expect_equal(python_type_to_col("float"), "double")
  expect_equal(python_type_to_col("bool"), "logical")
  expect_equal(python_type_to_col("date"), "Date")
  expect_equal(python_type_to_col("datetime"), "datetime")
  expect_equal(python_type_to_col("timestamp"), "datetime")
  expect_equal(python_type_to_col("time"), "datetime")
  # Unknown / non-tabular types fall back to character (always safe).
  expect_equal(python_type_to_col("json"), "character")
  expect_equal(python_type_to_col("uuid"), "character")
  expect_equal(python_type_to_col(NULL), "character") # via %||%
})

test_that("tabular_profile_col_types() maps a profile to shorthand types", {
  profile <- list(
    columns = list(
      name = list(python_type = "string"),
      age = list(python_type = "int"),
      height = list(python_type = "float"),
      active = list(python_type = "bool"),
      born = list(python_type = "date")
    )
  )
  out <- tabular_profile_col_types(profile)
  expect_named(out, c("name", "age", "height", "active", "born"))
  expect_equal(
    unname(out),
    c("character", "integer", "double", "logical", "Date")
  )
})

test_that("tabular_profile_col_types() returns NULL on empty/absent columns", {
  expect_null(tabular_profile_col_types(list()))
  expect_null(tabular_profile_col_types(list(columns = list())))
  expect_null(tabular_profile_col_types(list(foo = "bar")))
})

test_that("tabular_profile_col_types() drops low-confidence detections", {
  profile <- list(
    columns = list(
      # score above threshold and at-threshold are kept
      a = list(python_type = "int", score = 0.9),
      b = list(python_type = "string", score = 0.5),
      # below-threshold detection is left for vroom to infer
      c = list(python_type = "Date", score = 0.2),
      # missing score is treated as pass-through
      d = list(python_type = "float")
    )
  )
  out <- tabular_profile_col_types(profile, min_score = 0.5)
  expect_named(out, c("a", "b", "d"))
  expect_equal(
    unname(out),
    c("integer", "character", "double")
  )
})

test_that("tabular_profile_col_types() falls back when all detections are low-confidence", {
  profile <- list(
    columns = list(
      a = list(python_type = "Date", score = 0.1),
      b = list(python_type = "int", score = 0.4)
    )
  )
  expect_null(tabular_profile_col_types(profile, min_score = 0.5))
})

test_that("tabular_profile_col_types() honors a custom min_score", {
  profile <- list(
    columns = list(
      a = list(python_type = "int", score = 0.6),
      b = list(python_type = "string", score = 0.9)
    )
  )
  expect_named(tabular_profile_col_types(profile, min_score = 0.8), "b")
  expect_named(tabular_profile_col_types(profile, min_score = 0.5), c("a", "b"))
})

test_that("tabular_types_for_resource() is a no-op unless opted in", {
  res <- mock_resource("csv", id = "aaa")
  # use_tabular_types = FALSE must never hit the network.
  expect_null(tabular_types_for_resource(res, use_tabular_types = FALSE))
})

test_that("tabular_types_for_resource() skips ZIP resources", {
  res <- mock_resource("zip", id = "aaa")
  # Even opted in, a ZIP member has no rid-scoped profile.
  expect_null(tabular_types_for_resource(res, use_tabular_types = TRUE))
})

test_that("tabular_types_for_resource() fetches and maps a profile", {
  res <- mock_resource("csv", id = "aaa")
  local_mocked_bindings(
    tabular_profile = function(rid) {
      expect_equal(rid, "aaa")
      list(
        columns = list(
          x = list(python_type = "int"),
          y = list(python_type = "string")
        )
      )
    }
  )
  out <- tabular_types_for_resource(res, use_tabular_types = TRUE)
  expect_equal(out, c(x = "integer", y = "character"))
})

test_that("tabular_types_for_resource() degrades to NULL on a missing profile", {
  res <- mock_resource("csv", id = "aaa")
  local_mocked_bindings(
    tabular_profile = function(rid) stop("HTTP 404 Not Found")
  )
  expect_null(tabular_types_for_resource(res, use_tabular_types = TRUE))
})

test_that("merge_col_types() lets user types win and fills the rest", {
  tabular <- c(a = "integer", b = "Date", c = "character")
  # User pins `a`; profile provides `b` and `c`.
  expect_equal(
    merge_col_types(c(a = "double"), tabular),
    c(a = "double", b = "Date", c = "character")
  )
  # NULL user -> profile alone.
  expect_equal(merge_col_types(NULL, tabular), tabular)
  # NULL profile -> user alone.
  expect_equal(merge_col_types(c(a = "double"), NULL), c(a = "double"))
  # User-only columns are preserved.
  expect_equal(
    merge_col_types(c(z = "skip"), tabular),
    c(a = "integer", b = "Date", c = "character", z = "skip")
  )
})

test_that("read_resource() seeds types from the tabular profile of its resource", {
  res <- mock_resource("csv", id = "aaa")
  captured <- NULL
  local_mocked_bindings(
    tabular_profile = function(rid) {
      list(
        columns = list(
          x = list(python_type = "int"),
          y = list(python_type = "string")
        )
      )
    },
    download_resource = function(resource) tempfile(fileext = ".csv"),
    parse_resource_file = function(path, fmt, col_types = NULL) {
      captured <<- col_types
      mock_csv_data()
    }
  )
  out <- read_resource(res, use_tabular_types = TRUE)
  expect_equal(captured, c(x = "integer", y = "character"))
  expect_true(is.data.frame(out))
})

test_that("read_resource() lets explicit col_types win over the profile", {
  res <- mock_resource("csv", id = "aaa")
  captured <- NULL
  local_mocked_bindings(
    tabular_profile = function(rid) {
      list(
        columns = list(
          x = list(python_type = "int"),
          y = list(python_type = "string")
        )
      )
    },
    download_resource = function(resource) tempfile(fileext = ".csv"),
    parse_resource_file = function(path, fmt, col_types = NULL) {
      captured <<- col_types
      mock_csv_data()
    }
  )
  read_resource(res, col_types = c(x = "double"), use_tabular_types = TRUE)
  # `x` keeps the user type (double); `y` is seeded from the profile.
  expect_equal(captured, c(x = "double", y = "character"))
})

test_that("read_resource() leaves low-confidence columns to vroom inference", {
  res <- mock_resource("csv", id = "aaa")
  captured <- NULL
  local_mocked_bindings(
    tabular_profile = function(rid) {
      list(
        columns = list(
          x = list(python_type = "int", score = 0.95),
          y = list(python_type = "Date", score = 0.1)
        )
      )
    },
    download_resource = function(resource) tempfile(fileext = ".csv"),
    parse_resource_file = function(path, fmt, col_types = NULL) {
      captured <<- col_types
      mock_csv_data()
    }
  )
  read_resource(res, use_tabular_types = TRUE)
  # Low-confidence `y` must NOT be pinned: vroom infers it.
  expect_equal(captured, c(x = "integer"))
})

test_that("read_first_parseable_resource() resolves each resource's own profile", {
  # Two resources; the first fails to parse, so the loop falls through to the
  # second, which must get ITS profile (not a first-candidate guess). Real
  # read_resource()/read_first_parseable_resource() run; only the network
  # (profile) and file steps are mocked.
  dataset <- mock_dataset(
    resources = list(
      mock_resource("csv", id = "first-rid", title = "first.csv"),
      mock_resource("csv", id = "second-rid", title = "second.csv")
    )
  )
  seen <- character()
  local_mocked_bindings(
    tabular_profile = function(rid) {
      list(
        columns = list(
          col = list(
            python_type = if (rid == "second-rid") "int" else "string"
          )
        )
      )
    },
    download_resource = function(resource) tempfile(fileext = ".csv"),
    parse_resource_file = function(path, fmt, col_types = NULL) {
      seen <<- c(seen, col_types[["col"]])
      if (col_types[["col"]] == "character") {
        stop("parse failure")
      }
      mock_csv_data()
    }
  )
  out <- read_first_parseable_resource(dataset, use_tabular_types = TRUE)
  # Both resources were parsed; only the second had an integer-typed column and
  # thus succeeded.
  expect_equal(out$resource$id, "second-rid")
  expect_equal(seen, c("character", "integer"))
})

test_that("dg_pull_dataset() threads tabular types into the parse step (default on)", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"
  dataset <- mock_dataset(
    id = did,
    resources = list(mock_resource("csv", id = rid))
  )
  captured <- NULL
  local_mocked_bindings(
    find_dataset = function(id) dataset,
    tabular_profile = function(rid) {
      list(
        columns = list(
          a = list(python_type = "int"),
          b = list(python_type = "string")
        )
      )
    },
    download_resource = function(resource) tempfile(fileext = ".csv"),
    parse_resource_file = function(path, fmt, col_types = NULL) {
      captured <<- col_types
      mock_csv_data()
    }
  )
  out <- dg_pull_dataset(did)
  expect_equal(captured, c(a = "integer", b = "character"))
  expect_s3_class(out, "tbl_df")
})

test_that("dg_pull_dataset() honors explicit col_types over tabular types (default on)", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"
  dataset <- mock_dataset(
    id = did,
    resources = list(mock_resource("csv", id = rid))
  )
  captured <- NULL
  local_mocked_bindings(
    find_dataset = function(id) dataset,
    tabular_profile = function(rid) {
      list(
        columns = list(
          a = list(python_type = "int"),
          b = list(python_type = "string")
        )
      )
    },
    download_resource = function(resource) tempfile(fileext = ".csv"),
    parse_resource_file = function(path, fmt, col_types = NULL) {
      captured <<- col_types
      mock_csv_data()
    }
  )
  dg_pull_dataset(did, col_types = c(a = "double"))
  # `a` keeps the user type (double); `b` is seeded from the profile.
  expect_equal(captured, c(a = "double", b = "character"))
})

test_that("dg_refetch() threads tabular types for a single-file resource (default on)", {
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
    tabular_profile = function(rid) {
      list(
        columns = list(
          a = list(python_type = "int"),
          b = list(python_type = "string")
        )
      )
    },
    download_resource = function(resource) tempfile(fileext = ".csv"),
    parse_resource_file = function(path, fmt, col_types = NULL) {
      captured <<- col_types
      mock_csv_data()
    }
  )
  out <- dg_refetch(uri)
  expect_equal(captured, c(a = "integer", b = "character"))
  expect_equal(dg_table_id(out), uri)
})
