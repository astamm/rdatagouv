# Opt-in integration tests against the live data.gouv.fr API.
#
# These hit the real platform and are skipped unless the caller asks for them
# by setting the environment variable DATAGOUV_LIVE=1, so R CMD check (and a
# default `devtools::test()`) stays network-free and deterministic. They verify
# the one thing unit tests cannot: that a composed table URI built from the
# platform's own identifiers really re-fetches the same bytes from data.gouv.
#
# Run them with, e.g.:
#
#   DATAGOUV_LIVE=1 Rscript -e 'devtools::test(filter = "live")'
#
# The fixtures are chosen for stability: "Caen La Mer - Réseau Twisto - GTFS &
# SIRI" (dataset 6a6be5976a05df136d48fb7a) publishes a multi-file GTFS ZIP whose
# members are plain tabular .txt files. If that dataset later disappears or is
# reorganised on the platform, update the ids below.
skip_unless_live <- function() {
  testthat::skip_if_not(
    identical(Sys.getenv("DATAGOUV_LIVE"), "1"),
    "live API test requires DATAGOUV_LIVE=1"
  )
  # Probe the actual data.gouv host (not testthat's default captive.apple.com,
  # which may be unreachable even when data.gouv works).
  reachable <- tryCatch(
    {
      resp <- httr2::req_perform(httr2::request(
        paste0("https://www.data.gouv.fr/api/1/datasets/", live_dataset_id, "/")
      ))
      httr2::resp_status(resp) == 200
    },
    error = function(e) FALSE
  )
  testthat::skip_if_not(isTRUE(reachable), "data.gouv API not reachable")
}

# A real dataset exposing a multi-file tabular ZIP, plus one member file in it.
live_dataset_id <- "6a6be5976a05df136d48fb7a"
live_zip_rid <- "a5a8f046-e282-4010-91c5-82bc1f70ff73"
live_zip_member <- "stops.txt"

live_zip_uri <- function(file = live_zip_member) {
  paste0(
    "https://www.data.gouv.fr/datasets/",
    live_dataset_id,
    "#",
    live_zip_rid,
    "/",
    file
  )
}

test_that("the v2 datasets/search endpoint has the expected envelope", {
  skip_unless_live()

  body <- getFromNamespace("fetch_search_page", "datagouv")(
    q = "vélo",
    page_size = 1
  )

  expect_true(is.list(body$data))
  expect_true(is.numeric(body$total))
  # v2 pagination is pointer-based: next_page is a URL string (or NULL), never
  # the v1 object shape.
  expect_true(is.null(body$next_page) || is.character(body$next_page))
  expect_true(is.list(body$facets))
})

test_that("v2 organization and geozone filters narrow the total", {
  skip_unless_live()

  unfiltered <- getFromNamespace("fetch_search_page", "datagouv")(page_size = 1)
  # A current, live producer: "Ministère de l'intérieur". (The v2 API matches
  # `organization` by its 24-hex id; a slug is not accepted.)
  narrowed <- getFromNamespace("fetch_search_page", "datagouv")(
    organization = "534fff91a3a7292c64a77f53",
    page_size = 1
  )

  # A genuine narrowing, not merely non-increasing: the filter selects a
  # specific producer, so it must return a positive count strictly below the
  # unfiltered catalog.
  expect_gt(narrowed$total, 0)
  expect_lt(narrowed$total, unfiltered$total)
})

test_that("a file inside a ZIP is addressable live via its composed URI", {
  skip_unless_live()

  tbl <- dg_refetch(live_zip_uri())

  expect_s3_class(tbl, "tbl_df")
  # It is genuinely the addressed member (a non-trivial table), not an error
  # page or an empty archive.
  expect_gt(nrow(tbl), 0)
  expect_true(all(nzchar(names(tbl))))
  expect_equal(dg_table_id(tbl), live_zip_uri())
})

test_that("re-fetching a ZIP-member URI is reproducible on the live API", {
  skip_unless_live()

  first <- dg_refetch(live_zip_uri())
  again <- dg_refetch(live_zip_uri())

  expect_identical(again, first)
})

test_that("a refetched ZIP member matches a direct read of that file", {
  skip_unless_live()

  tbl <- dg_refetch(live_zip_uri())

  # Cross-check against reading the same member straight out of the archive,
  # the low-level path dg_refetch() wraps.
  dataset <- getFromNamespace("fetch_dataset", "datagouv")(live_dataset_id)
  resource <- Filter(function(r) r$id == live_zip_rid, dataset$resources)[[1]]
  direct <- getFromNamespace("read_one_zip_file", "datagouv")(
    resource,
    live_zip_member
  )
  direct <- tibble::as_tibble(getFromNamespace("format_tibble", "datagouv")(
    direct
  ))
  direct <- structure(direct, id = live_zip_uri())

  expect_identical(tbl, direct)
})

# A stable, current producer used for the live organization-resolution tests.
# SNCF (id 534fffb0a3a7292c64a78115) publishes many datasets as both `SNCF`
# (name) and `sncf` (slug); these are exact matches, so resolution is
# unambiguous. Update the id if the producer ever changes.
live_org_id <- "534fffb0a3a7292c64a78115"

test_that("dg_find_organization() returns the expected tibble live", {
  skip_unless_live()

  orgs <- dg_find_organization(q = "SNCF", n = 5)

  expect_s3_class(orgs, "tbl_df")
  expect_true(all(
    c(
      "id",
      "name",
      "slug",
      "acronym",
      "description",
      "datasets",
      "badges",
      "business_number_id"
    ) %in%
      names(orgs)
  ))
  # SNCF is a large producer and must surface when searched by its name.
  expect_true(live_org_id %in% orgs$id)
})

test_that("dg_find_datasets(organization =) resolves a name and a slug live", {
  skip_unless_live()

  by_name <- dg_find_datasets(organization = "SNCF", n = 5)
  by_slug <- dg_find_datasets(organization = "sncf", n = 5)
  by_id <- dg_find_datasets(organization = live_org_id, n = 5)

  # All three spellings address the same producer, so they must return the
  # same catalog of its datasets.
  expect_s3_class(by_name, "tbl_df")
  expect_gt(nrow(by_name), 0)
  expect_identical(sort(by_name$id), sort(by_slug$id))
  expect_identical(names(by_name), names(by_id))
})

test_that("each discovered organization id is directly filterable", {
  skip_unless_live()

  # Every id listed by dg_find_organization() should narrow dg_find_datasets()
  # to that producer without error and return a positive count.
  orgs <- dg_find_organization(q = "SNCF", n = 5)
  for (oid in orgs$id) {
    res <- dg_find_datasets(organization = oid, n = 5)
    expect_s3_class(res, "tbl_df")
    expect_gt(nrow(res), 0)
  }
})
