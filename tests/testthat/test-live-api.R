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

# A real single-file CSV dataset whose resource is indexed by the tabular
# service, so it carries a csv-detective profile. Used to exercise
# use_tabular_types = TRUE (profile-based column typing) against real data.
# "Indices Qualité de l'air (Citeair) journaliers - Réglementaire" — the
# resource's profile declares all five columns above the confidence threshold,
# so `dg_pull_dataset()` should materialise them with the advertised types.
# Update the ids if the dataset or its CSV resource changes.
live_profile_dataset_id <- "5a4651eb88ee380bb9eff81e"
live_profile_rid <- "da7a4869-b584-48ad-8a81-784a02eb297a"

# A dataset whose tabular CSV resource carries BOTH a resolvable schema pointer
# and a tabular (csv-detective) profile. "Base nationale des IRVE data.gouv"
# (dataset 5448d3e0c751df01f85d0572) publishes the IRVE-station table as a CSV
# resource (rid eb76d20a-...) whose `schema` pointer resolves to the
# irve-statique Table Schema (schema.data.gouv.fr), and which the tabular
# service also indexes (so it has a profile). This lets us pin the design
# decision that the profile — not the schema — seeds column types even when a
# schema is co-present. Update the ids if the dataset or its CSV resource
# changes.
live_coexist_dataset_id <- "5448d3e0c751df01f85d0572"
live_coexist_rid <- "eb76d20a-8501-400e-b336-d85724de5435"

test_that("the v2 datasets/search endpoint has the expected envelope", {
  skip_unless_live()

  body <- getFromNamespace("fetch_search_page", "rdatagouv")(
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

  unfiltered <- getFromNamespace("fetch_search_page", "rdatagouv")(
    page_size = 1
  )
  # A current, live producer: "Ministère de l'intérieur". (The v2 API matches
  # `organization` by its 24-hex id; a slug is not accepted.)
  narrowed <- getFromNamespace("fetch_search_page", "rdatagouv")(
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
  dataset <- getFromNamespace("fetch_dataset", "rdatagouv")(live_dataset_id)
  resource <- Filter(function(r) r$id == live_zip_rid, dataset$resources)[[1]]
  direct <- getFromNamespace("read_one_zip_file", "rdatagouv")(
    resource,
    live_zip_member
  )
  direct <- tibble::as_tibble(getFromNamespace("format_tibble", "rdatagouv")(
    direct
  ))
  direct <- structure(direct, id = live_zip_uri())

  expect_identical(tbl, direct)
})

test_that("dg_pull_dataset() seeds column types from the live tabular profile", {
  skip_unless_live()

  # Default use_tabular_types = TRUE reads the resource's csv-detective profile
  # (tabular-api...//resources/<rid>/profile/) and pins each column that passes
  # the confidence threshold before handing the rest to vroom.
  tbl <- dg_pull_dataset(live_profile_dataset_id)

  # The table actually parsed (not an error page / empty download) and its id
  # is the composed single-file URI of the addressed CSV resource.
  expect_s3_class(tbl, "tbl_df")
  expect_gt(nrow(tbl), 0)
  expect_equal(
    dg_table_id(tbl),
    paste0(
      "https://www.data.gouv.fr/datasets/",
      live_profile_dataset_id,
      "#",
      live_profile_rid
    )
  )

  # Every column in the live profile must have been applied to the pulled table
  # (all scores exceed min_score = 0.5). Date stays a real date collector, and
  # the numeric columns are typed integer rather than left as character.
  tabular_profile <- getFromNamespace("tabular_profile", "rdatagouv")
  tabular_profile_col_types <- getFromNamespace(
    "tabular_profile_col_types",
    "rdatagouv"
  )
  prof_types <- tabular_profile_col_types(tabular_profile(live_profile_rid))
  expect_false(is.null(prof_types))

  # Pin the empirical mapping exactly: the five columns resolve to integer for
  # the four pollutant/station-id columns and Date for the date column (all
  # profile scores >= 1.0, i.e. above min_score = 0.5).
  expect_equal(
    prof_types,
    c(
      o3 = "integer",
      no2 = "integer",
      date = "Date",
      pm10 = "integer",
      ninsee = "integer"
    )
  )

  for (nm in names(prof_types)) {
    expected <- switch(
      prof_types[[nm]],
      character = "character",
      integer = "integer",
      double = "double",
      logical = "logical",
      Date = "Date",
      datetime = "POSIXct",
      "character"
    )
    expect_true(
      inherits(tbl[[nm]], expected),
      info = paste("profile type", expected, "applied to", nm)
    )
    expect_true(nm %in% names(tbl), info = paste("column in table:", nm))
  }
})

test_that("with a schema and profile co-present, the profile seeds types", {
  skip_unless_live()

  # The IRVE resource has a resolvable schema (dg_schema() must return real
  # fields) AND is indexed by the tabular service. The schema's own `type`
  # vocabulary is looser than csv-detective's (the irve-statique Table Schema
  # declares `string, geopoint, integer, number, boolean, date` — `geopoint`
  # and `number` have no col_types shorthand). Column typing must therefore
  # come from the empirical profile, not the schema, which serves only its
  # documentation role here.
  schema <- dg_schema(
    paste0(
      "https://www.data.gouv.fr/datasets/",
      live_coexist_dataset_id,
      "#",
      live_coexist_rid
    )
  )
  expect_false(is.null(schema))
  expect_gt(nrow(schema), 0)
  expect_true(all(
    c("name", "title", "description", "type", "example") %in%
      names(schema)
  ))
  # A real, resolved schema bearing non-shorthand types confirms the fixture.
  expect_true(any(schema$type %in% c("geopoint", "number")))

  # The pulled table must apply the profile's types (logical/Date/integer/
  # double), not be left as character or coerced from the schema.
  tbl <- dg_pull_dataset(live_coexist_dataset_id)
  expect_s3_class(tbl, "tbl_df")
  expect_gt(nrow(tbl), 0)
  parse_table_id <- getFromNamespace("parse_table_id", "rdatagouv")
  expect_equal(parse_table_id(dg_table_id(tbl))$resource_id, live_coexist_rid)

  # Sample the columns whose profile type is unambiguous and must have been
  # applied irrespective of the schema's looser vocabulary.
  expect_true(inherits(tbl[["gratuit"]], "logical"))
  expect_true(inherits(tbl[["nbre_pdc"]], "integer"))
  expect_true(inherits(tbl[["puissance_nominale"]], "numeric"))
  expect_true(inherits(tbl[["date_maj"]], "Date"))
  expect_true(inherits(tbl[["date_mise_en_service"]], "Date"))
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

test_that("dg_find_topics() returns the expected tibble live", {
  skip_unless_live()

  topics <- dg_find_topics(q = "environnement", n = 5)

  expect_s3_class(topics, "tbl_df")
  expect_true(all(
    c(
      "id",
      "name",
      "slug",
      "description",
      "tags",
      "featured",
      "n_elements",
      "n_datasets",
      "n_dataservices",
      "n_reuses"
    ) %in%
      names(topics)
  ))
})

test_that("a discovered topic id is directly filterable live", {
  skip_unless_live()

  # Any topic surfaced by dg_find_topics() should be addressable as a single-
  # valued server-side `topic` filter on dg_find_datasets(). Some curated
  # topics may group only reuses/dataservices (no datasets), so we only demand
  # a well-formed tibble, not a positive row count.
  topics <- dg_find_topics(n = 5)
  for (tid in topics$id) {
    res <- dg_find_datasets(topic = tid, n = 5)
    expect_s3_class(res, "tbl_df")
    expect_true(all(c("id", "title") %in% names(res)))
  }
})

test_that("dg_find_topics(elements = TRUE) follows pagination on a large theme live", {
  skip_unless_live()

  # sift through the catalog for a topic whose declared element count exceeds
  # a single page (page_size = 100), guaranteeing the next_page crawl runs.
  # The `n_elements` total comes from the topics/search envelope, so no N+1
  # crawl is needed just to find a large candidate.
  topics <- dg_find_topics(n = 100)
  large <- topics[!is.na(topics$n_elements) & topics$n_elements > 100, ]
  if (nrow(large) == 0) {
    testthat::skip(paste(
      "no topic among the first",
      nrow(topics),
      "has more than 100 elements"
    ))
  }
  big <- large[1, ]

  # `elements = TRUE` N+1-crawls the subsection (and its pagination). Search by
  # the topic's name to surface just that topic; the per-kind breakdown must
  # sum to at most the declared total (external-link NULL-class entries are
  # excluded, hence `<=`), and none of the counts may be NA once fetched.
  elems <- dg_find_topics(q = big$name, n = 1, elements = TRUE)
  row <- elems[elems$id == big$id, ]
  expect_equal(nrow(row), 1)
  expect_false(anyNA(c(
    row$n_datasets,
    row$n_dataservices,
    row$n_reuses
  )))
  expect_true(
    row$n_datasets + row$n_dataservices + row$n_reuses <= row$n_elements
  )
})
