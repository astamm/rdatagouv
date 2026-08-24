test_that("dg_find_organization() returns a tibble with the expected columns", {
  local_mocked_bindings(
    fetch_organizations_all = function(...) {
      list(
        mock_organization(
          id = "a1",
          name = "SNCF",
          slug = "sncf",
          datasets = 100
        ),
        mock_organization(
          id = "b2",
          name = "Île-de-France Mobilités",
          slug = "ile-de-france-mobilites",
          acronym = "IDFM",
          datasets = 50,
          badges = list(
            list(kind = "public-service"),
            list(kind = "certified")
          ),
          business_number_id = "123456789"
        )
      )
    }
  )

  out <- dg_find_organization(q = "SNCF")

  expect_s3_class(out, "tbl_df")
  expect_named(
    out,
    c(
      "id",
      "name",
      "slug",
      "acronym",
      "description",
      "datasets",
      "badges",
      "business_number_id"
    )
  )
  expect_equal(out$id, c("a1", "b2"))
  expect_equal(out$name, c("SNCF", "Île-de-France Mobilités"))
  expect_equal(out$datasets, c(100L, 50L))
  expect_equal(out$badges, c("public-service", "public-service, certified"))
  expect_equal(out$acronym, c(NA_character_, "IDFM"))
})

test_that("dg_find_organization() forwards the query and limit", {
  seen <- NULL
  local_mocked_bindings(
    fetch_organizations_all = function(q = NULL, n = 20, ...) {
      seen <<- list(q = q, n = n)
      list(mock_organization(id = "a1", name = "SNCF", slug = "sncf"))
    }
  )

  dg_find_organization(q = "mobilite", n = 5)

  expect_equal(seen$q, "mobilite")
  expect_equal(seen$n, 5)
})

test_that("dg_find_organization() returns an empty tibble when nothing matches", {
  local_mocked_bindings(
    fetch_organizations_all = function(...) list()
  )

  out <- dg_find_organization(q = "nonexistent")

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0)
  expect_true("id" %in% names(out))
  expect_true("datasets" %in% names(out))
})

test_that("dg_find_organization() coerces absent fields to NA", {
  local_mocked_bindings(
    fetch_organizations_all = function(...) {
      list(
        mock_organization(
          id = "a1",
          name = "Minimal",
          slug = "minimal",
          acronym = NULL,
          description = NULL,
          badges = list(),
          business_number_id = NULL,
          datasets = NULL
        )
      )
    }
  )

  out <- dg_find_organization()

  expect_true(is.na(out$acronym[1]))
  expect_true(is.na(out$badges[1]))
  expect_true(is.na(out$business_number_id[1]))
  expect_equal(out$datasets, NA_integer_)
})
