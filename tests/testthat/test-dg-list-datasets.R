test_that("dg_list_datasets() returns a tibble with the expected columns", {
  local_mocked_bindings(
    fetch_all_datasets = function(
      page_size = 1000,
      q = NULL,
      n = 1000,
      format = catalog_formats()
    ) {
      list(
        mock_dataset(title = "A", id = "a1"),
        mock_dataset(title = "B", id = "b2"),
        mock_dataset(title = "C", id = "c3")
      )
    }
  )

  out <- dg_list_datasets()

  expect_s3_class(out, "tbl_df")
  expect_named(
    out,
    c(
      "title",
      "id",
      "description",
      "slug",
      "n_resources",
      "formats",
      "has_table",
      "has_schema"
    )
  )
  expect_equal(out$title, c("A", "B", "C"))
  expect_equal(out$id, c("a1", "b2", "c3"))
})

test_that("dg_list_datasets() derives resource columns", {
  local_mocked_bindings(
    fetch_all_datasets = function(
      page_size = 1000,
      q = NULL,
      n = 1000,
      format = catalog_formats()
    ) {
      list(
        mock_dataset(
          title = "A",
          id = "a1",
          resources = list(
            mock_resource(format = "csv", id = "r1"),
            mock_resource(format = "XLSX", id = "r2")
          )
        ),
        mock_dataset(
          title = "Doc only",
          id = "b2",
          resources = list(mock_resource(format = "pdf", id = "r3"))
        ),
        mock_dataset(
          title = "No resource",
          id = "c3",
          resources = list()
        )
      )
    }
  )

  out <- dg_list_datasets()

  expect_equal(out$n_resources, c(2, 1, 0))
  expect_equal(out$formats, c("csv, xlsx", "pdf", ""))
  expect_equal(out$has_table, c(TRUE, FALSE, FALSE))
})

test_that("dg_list_datasets() flags resources carrying a schema pointer", {
  no_schema <- mock_resource(format = "csv", id = "r1")
  with_schema <- mock_resource(format = "csv", id = "r2")
  with_schema$schema <- list(
    name = "etalab/schema-bal",
    url = NULL,
    version = NULL
  )
  with_url <- mock_resource(format = "csv", id = "r3")
  with_url$schema <- list(name = NULL, url = "https://example.org/schema.json")

  local_mocked_bindings(
    fetch_all_datasets = function(
      page_size = 1000,
      q = NULL,
      n = 1000,
      format = catalog_formats()
    ) {
      list(
        mock_dataset(title = "Plain", id = "p1", resources = list(no_schema)),
        mock_dataset(title = "Named", id = "p2", resources = list(with_schema)),
        mock_dataset(title = "URL", id = "p3", resources = list(with_url))
      )
    }
  )

  out <- dg_list_datasets()

  expect_equal(out$has_schema, c(FALSE, TRUE, TRUE))
})

test_that("dg_list_datasets(schema_only = TRUE) keeps only documented datasets", {
  no_schema <- mock_resource(format = "csv", id = "r1")
  with_schema <- mock_resource(format = "csv", id = "r2")
  with_schema$schema <- list(
    name = "etalab/schema-bal",
    url = NULL,
    version = NULL
  )

  local_mocked_bindings(
    fetch_all_datasets = function(
      page_size = 1000,
      q = NULL,
      n = 1000,
      format = catalog_formats()
    ) {
      list(
        mock_dataset(title = "Plain", id = "p1", resources = list(no_schema)),
        mock_dataset(title = "Named", id = "p2", resources = list(with_schema))
      )
    }
  )

  out <- dg_list_datasets(schema_only = TRUE)

  expect_equal(out$id, "p2")
})

test_that("dg_list_datasets() returns an empty tibble when the API is empty", {
  local_mocked_bindings(
    fetch_all_datasets = function(
      page_size = 1000,
      q = NULL,
      n = 1000,
      format = catalog_formats()
    ) {
      list()
    }
  )

  out <- dg_list_datasets()

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0)
})

test_that("dg_list_datasets() coerces missing fields to NA", {
  local_mocked_bindings(
    fetch_all_datasets = function(
      page_size = 1000,
      q = NULL,
      n = 1000,
      format = catalog_formats()
    ) {
      list(
        mock_dataset(title = "A", id = "a1"),
        list(id = "b2", slug = "b", description = NULL)
      )
    }
  )

  out <- dg_list_datasets()

  expect_equal(out$title, c("A", NA))
  expect_equal(out$id, c("a1", "b2"))
})

test_that("dg_list_datasets() forwards the search query and the limit", {
  seen <- NULL
  local_mocked_bindings(
    fetch_all_datasets = function(
      page_size = 1000,
      q = NULL,
      n = 1000,
      format = catalog_formats()
    ) {
      seen <<- list(q = q, n = n, format = format)
      list(mock_dataset(title = "Cyclable", id = "c1"))
    }
  )

  out <- dg_list_datasets(q = "vélo", n = 7)

  expect_equal(out$title, "Cyclable")
  expect_equal(seen$q, "vélo")
  expect_equal(seen$n, 7)
})

test_that("dg_list_datasets() forwards the requested formats", {
  seen <- NULL
  local_mocked_bindings(
    fetch_all_datasets = function(
      page_size = 1000,
      q = NULL,
      n = 1000,
      format = catalog_formats()
    ) {
      seen <<- format
      list(mock_dataset(title = "Parquet", id = "p1"))
    }
  )

  out <- dg_list_datasets(format = c("parquet", "csv"), n = 5)

  expect_equal(out$title, "Parquet")
  expect_equal(seen, c("parquet", "csv"))
})

test_that("dg_list_datasets(format = NULL) defaults to the catalog formats", {
  seen <- NULL
  local_mocked_bindings(
    fetch_all_datasets = function(
      page_size = 1000,
      q = NULL,
      n = 1000,
      format = catalog_formats()
    ) {
      seen <<- format
      list(mock_dataset(title = "A", id = "a1"))
    }
  )

  dg_list_datasets()

  expect_equal(seen, catalog_formats())
})
