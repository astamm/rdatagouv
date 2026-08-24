test_that("dg_glimpse() surfaces v2-inline quality and metrics metadata", {
  local_mocked_bindings(
    fetch_dataset_v2 = function(id) {
      mock_dataset_v2(
        title = "Les horaires de bus",
        id = id,
        organization = list(id = "org-1", slug = "mairie", name = "Mairie"),
        license = "lov2",
        quality = list(
          score = 0.75,
          license = TRUE,
          spatial = FALSE,
          update_frequency = TRUE
        ),
        metrics = list(
          views = 1200,
          resources_downloads = 300,
          followers = 12,
          discussions = 4,
          reuses = 2,
          dataservices = 0
        ),
        frequency = "monthly",
        temporal_coverage = list(start = "2018-01-01", end = "2026-01-01"),
        access_type = "open"
      )
    }
  )

  g <- dg_glimpse("6a6be5976a05df136d48fb7a")

  expect_equal(g$id, "6a6be5976a05df136d48fb7a")
  expect_equal(g$title, "Les horaires de bus")
  expect_equal(g$quality$score, 0.75)
  expect_true(g$quality$flags$license)
  expect_false(g$quality$flags$spatial)
  expect_equal(g$metrics$views, 1200)
  expect_equal(g$metrics$resources_downloads, 300)
  expect_equal(g$metrics$followers, 12)
  expect_equal(g$context$organization$slug, "mairie")
  expect_equal(g$context$license, "lov2")
  expect_equal(g$context$temporal_coverage$start, "2018-01-01")
  expect_equal(g$context$access_type, "open")
})

test_that("dg_glimpse() includes resources only when table = TRUE", {
  id <- "6a6be5976a05df136d48fb7a"
  local_mocked_bindings(
    fetch_dataset_v2 = function(id) mock_dataset_v2(id = id),
    fetch_resource_subsection = function(subsection) {
      list(mock_resource(format = "csv", id = "r1"))
    }
  )

  g_without <- dg_glimpse(id)
  expect_null(g_without$resources)

  g_with <- dg_glimpse(id, table = TRUE)
  expect_length(g_with$resources, 1)
  expect_equal(g_with$resources[[1]]$id, "r1")
})

test_that("dg_glimpse() resolves a dataset id from a composed table id and a table", {
  local_mocked_bindings(
    fetch_dataset_v2 = function(id) mock_dataset_v2(title = "T", id = id)
  )
  composed <- "https://www.data.gouv.fr/datasets/6a6be5976a05df136d48fb7a#a5a8f046-e282-4010-91c5-82bc1f70ff73"

  from_uri <- dg_glimpse(composed)
  expect_equal(from_uri$id, "6a6be5976a05df136d48fb7a")

  tbl <- structure(tibble::tibble(x = 1), id = composed)
  from_table <- dg_glimpse(tbl)
  expect_equal(from_table$id, "6a6be5976a05df136d48fb7a")
})

test_that("dg_glimpse() errors clearly on invalid input", {
  expect_snapshot(error = TRUE, dg_glimpse(123))
})
