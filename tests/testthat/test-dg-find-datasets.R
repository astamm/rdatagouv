test_that("dg_find_datasets() returns a tibble with the expected columns", {
  local_mocked_bindings(
    fetch_search_all = function(...) {
      list(
        mock_dataset_v2(title = "A", id = "a1"),
        mock_dataset_v2(title = "B", id = "b2"),
        mock_dataset_v2(title = "C", id = "c3")
      )
    }
  )

  out <- dg_find_datasets()

  expect_s3_class(out, "tbl_df")
  expect_named(
    out,
    c(
      "title",
      "id",
      "description",
      "slug",
      "organization",
      "license",
      "quality_score",
      "quality_flags",
      "views",
      "resources_downloads",
      "access_type",
      "frequency",
      "spatial_granularity",
      "temporal_start",
      "temporal_end",
      "archived",
      "featured",
      "n_resources",
      "formats",
      "has_table",
      "has_schema"
    )
  )
  expect_equal(out$title, c("A", "B", "C"))
  expect_equal(out$id, c("a1", "b2", "c3"))
})

test_that("dg_find_datasets() surfaces v2-inline metadata columns", {
  local_mocked_bindings(
    fetch_search_all = function(...) {
      list(
        mock_dataset_v2(
          title = "A",
          id = "a1",
          organization = list(id = "o1", slug = "mairie", name = "Mairie"),
          license = "odc-odbl",
          quality = list(
            score = 0.9,
            license = TRUE,
            spatial = FALSE,
            update_frequency = TRUE
          ),
          metrics = list(views = 123, resources_downloads = 45),
          access_type = "restricted",
          frequency = "annual",
          spatial = list(granularity = "fr:epci"),
          temporal_coverage = list(start = "2019", end = "2022"),
          archived = TRUE
        )
      )
    }
  )

  out <- dg_find_datasets()

  expect_equal(out$organization, "mairie")
  expect_equal(out$license, "odc-odbl")
  expect_equal(out$quality_score, 0.9)
  expect_equal(out$quality_flags, "license, update_frequency")
  expect_equal(out$views, 123)
  expect_equal(out$resources_downloads, 45)
  expect_equal(out$access_type, "restricted")
  expect_equal(out$frequency, "annual")
  expect_equal(out$spatial_granularity, "fr:epci")
  expect_equal(out$temporal_start, "2019")
  expect_equal(out$temporal_end, "2022")
  expect_true(out$archived)
  expect_false(out$featured)
})

test_that("resource columns are NA when resources = FALSE (default)", {
  local_mocked_bindings(
    fetch_search_all = function(...) {
      list(mock_dataset_v2(title = "A", id = "a1"))
    }
  )

  out <- dg_find_datasets()

  expect_true(is.na(out$n_resources))
  expect_equal(out$formats, list(NULL))
  expect_true(is.na(out$has_table))
  expect_true(is.na(out$has_schema))
})

test_that("resources = TRUE fills the resource columns via the subsection", {
  subsection_url <- "https://x/api/2/datasets/a1/resources/"
  local_mocked_bindings(
    fetch_search_all = function(...) {
      list(mock_dataset_v2(
        title = "A",
        id = "a1",
        resources_href = subsection_url
      ))
    },
    fetch_resource_subsection = function(subsection) {
      expect_equal(subsection$href, subsection_url)
      list(
        mock_resource(format = "csv", id = "r1"),
        mock_resource(format = "XLSX", id = "r2")
      )
    }
  )

  out <- dg_find_datasets(resources = TRUE)

  expect_equal(out$n_resources, 2)
  expect_equal(out$formats, list(c("csv", "xlsx")))
  expect_true(out$has_table)
  expect_false(out$has_schema)
})

test_that("resources = TRUE flags resources carrying a schema pointer", {
  with_schema <- mock_resource(format = "csv", id = "r1")
  with_schema$schema <- list(
    name = "etalab/schema-bal",
    url = NULL,
    version = NULL
  )
  local_mocked_bindings(
    fetch_search_all = function(...) {
      list(mock_dataset_v2(title = "A", id = "a1"))
    },
    fetch_resource_subsection = function(subsection) list(with_schema)
  )

  out <- dg_find_datasets(resources = TRUE)

  expect_true(out$has_schema)
})

test_that("dg_find_datasets(schema_only = TRUE) keeps only documented datasets", {
  with_schema <- mock_resource(format = "csv", id = "r1")
  with_schema$schema <- list(name = "etalab/schema-bal", url = NULL)
  no_schema <- mock_resource(format = "csv", id = "r2")
  local_mocked_bindings(
    fetch_search_all = function(...) {
      list(
        mock_dataset_v2(title = "Plain", id = "p1"),
        mock_dataset_v2(title = "Named", id = "p2")
      )
    },
    fetch_resource_subsection = function(subsection) {
      if (grepl("p1", subsection$href, fixed = TRUE)) {
        list(no_schema)
      } else {
        list(with_schema)
      }
    }
  )

  out <- dg_find_datasets(schema_only = TRUE, resources = TRUE)

  expect_equal(out$id, "p2")
})

test_that("schema_only = TRUE forces resources = TRUE and filters", {
  with_schema <- mock_resource(format = "csv", id = "r1")
  with_schema$schema <- list(name = "etalab/schema-bal", url = NULL)
  local_mocked_bindings(
    fetch_search_all = function(...) {
      list(
        mock_dataset_v2(title = "Plain", id = "p1"),
        mock_dataset_v2(title = "Named", id = "p2")
      )
    },
    fetch_resource_subsection = function(subsection) {
      if (grepl("p1", subsection$href, fixed = TRUE)) {
        list()
      } else {
        list(with_schema)
      }
    }
  )

  out <- dg_find_datasets(schema_only = TRUE, resources = FALSE)

  # The resource fetch ran (not a silent no-op on has_schema = NA) and the
  # client-side filter actually applied.
  expect_equal(out$id, "p2")
  expect_false(is.na(out$has_schema))
})

test_that("schema_only = TRUE announces the forced resource fetch", {
  local_mocked_bindings(
    fetch_search_all = function(...) list(),
    fetch_resource_subsection = function(subsection) list()
  )

  expect_snapshot(dg_find_datasets(schema_only = TRUE, resources = FALSE))
})

test_that("dg_find_datasets() forwards filter arguments to the search", {
  seen <- NULL
  local_mocked_bindings(
    fetch_search_all = function(
      q = NULL,
      n = 1000,
      format = catalog_formats(),
      organization = NULL,
      geozone = NULL,
      access_type = NULL,
      license = NULL,
      tag = NULL,
      topic = NULL,
      granularity = NULL,
      last_update = NULL,
      producer_type = NULL,
      ...
    ) {
      seen <<- list(
        q = q,
        n = n,
        format = format,
        organization = organization,
        geozone = geozone,
        access_type = access_type,
        license = license,
        tag = tag,
        topic = topic,
        granularity = granularity,
        last_update = last_update,
        producer_type = producer_type
      )
      list(mock_dataset_v2(title = "Cyclable", id = "c1"))
    }
  )

  out <- dg_find_datasets(
    q = "vélo",
    n = 7,
    organization = "534fff91a3a7292c64a77f53",
    geozone = "country:fr",
    access_type = "open",
    license = "lov2",
    tag = "mobilite",
    topic = "54f5f20f88ee38233f4da0dd",
    granularity = "fr:commune",
    last_update = "last_30_days",
    producer_type = "public-service"
  )

  expect_equal(out$title, "Cyclable")
  expect_equal(seen$q, "vélo")
  expect_equal(seen$n, 7)
  expect_equal(seen$organization, "534fff91a3a7292c64a77f53")
  expect_equal(seen$geozone, "country:fr")
  expect_equal(seen$access_type, "open")
  expect_equal(seen$license, "lov2")
  expect_equal(seen$tag, "mobilite")
  expect_equal(seen$topic, "54f5f20f88ee38233f4da0dd")
  expect_equal(seen$granularity, "fr:commune")
  expect_equal(seen$last_update, "last_30_days")
  expect_equal(seen$producer_type, "public-service")
})

test_that("closed-vocabulary filter args accept every valid value", {
  for (value in dg_access_type_values) {
    expect_silent(validate_filter_args(value, NULL, NULL, NULL, NULL))
  }
  for (value in dg_producer_type_values) {
    expect_silent(validate_filter_args(NULL, NULL, NULL, NULL, value))
  }
  for (value in dg_last_update_values) {
    expect_silent(validate_filter_args(NULL, NULL, NULL, value, NULL))
  }
  for (value in dg_license_values) {
    expect_silent(validate_filter_args(NULL, value, NULL, NULL, NULL))
  }
  for (value in dg_granularity_values) {
    expect_silent(validate_filter_args(NULL, NULL, value, NULL, NULL))
  }
})

test_that("closed-vocabulary filter args reject an invalid value with the list", {
  bad <- list(
    access_type = "bogus",
    license = "bogus",
    granularity = "bogus",
    last_update = "bogus",
    producer_type = "bogus"
  )
  for (nm in names(bad)) {
    args <- list(NULL, NULL, NULL, NULL, NULL)
    names(args) <- c(
      "access_type",
      "license",
      "granularity",
      "last_update",
      "producer_type"
    )
    args[[nm]] <- bad[[nm]]
    err <- tryCatch(
      do.call(validate_filter_args, args),
      error = identity
    )
    expect_s3_class(err, "datagouv_invalid_filter")
    # The message names the offending argument and points at every valid option
    # (cli reformats the list, so only check it surfaces the diagnostic).
    expect_match(err$message, nm, fixed = TRUE)
    expect_match(err$message, "Valid options are:", fixed = TRUE)
  }
})

test_that("dg_find_datasets() errors on an invalid filter value", {
  local_mocked_bindings(fetch_search_all = function(...) list())
  expect_error(
    dg_find_datasets(producer_type = "bogus"),
    class = "datagouv_invalid_filter"
  )
  expect_error(
    dg_find_datasets(license = "bogus"),
    class = "datagouv_invalid_filter"
  )
  expect_error(
    dg_find_datasets(granularity = "bogus"),
    class = "datagouv_invalid_filter"
  )
})

test_that("closed-vocabulary filter args reject NULL via single-value check", {
  # NA and length > 1 are invalid for these single-valued server-side filters.
  for (nm in c(
    "access_type",
    "license",
    "granularity",
    "last_update",
    "producer_type"
  )) {
    args <- list(NULL, NULL, NULL, NULL, NULL)
    names(args) <- c(
      "access_type",
      "license",
      "granularity",
      "last_update",
      "producer_type"
    )
    args[[nm]] <- c("lov2", "cc-by")
    expect_error(
      do.call(validate_filter_args, args),
      class = "datagouv_invalid_filter"
    )
  }
  expect_error(
    validate_filter_args(NA_character_, NULL, NULL, NULL, NULL),
    class = "datagouv_invalid_filter"
  )
})

test_that("filter arg validation keeps NULL (no filter) passing through", {
  expect_silent(validate_filter_args(NULL, NULL, NULL, NULL, NULL))
})

test_that("geozone and tag are not validated", {
  # geozone is a free territory code and tag an open vocabulary: neither
  # should be rejected by validation, only forwarded to the server.
  seen <- NULL
  local_mocked_bindings(
    fetch_search_all = function(geozone = NULL, tag = NULL, ...) {
      seen <<- list(geozone = geozone, tag = tag)
      list()
    }
  )
  out <- dg_find_datasets(geozone = "country-group:ue", tag = "mobilite")
  expect_equal(seen$geozone, "country-group:ue")
  expect_equal(seen$tag, "mobilite")
})

test_that("dg_find_datasets() forwards format as repeated server-side params", {
  seen <- NULL
  local_mocked_bindings(
    fetch_search_all = function(format = catalog_formats(), ...) {
      seen <<- format
      list(mock_dataset_v2(title = "Parquet", id = "p1"))
    }
  )

  out <- dg_find_datasets(format = c("parquet", "csv"), n = 5)

  expect_equal(out$title, "Parquet")
  expect_equal(seen, c("parquet", "csv"))
})

test_that("dg_find_datasets(format = NULL) defaults to the catalog formats", {
  seen <- NULL
  local_mocked_bindings(
    fetch_search_all = function(format = catalog_formats(), ...) {
      seen <<- format
      list(mock_dataset_v2(title = "A", id = "a1"))
    }
  )

  dg_find_datasets()

  expect_equal(seen, catalog_formats())
})

test_that("dg_find_datasets() forwards the search query and the limit", {
  seen <- NULL
  local_mocked_bindings(
    fetch_search_all = function(q = NULL, n = 1000, ...) {
      seen <<- list(q = q, n = n)
      list(mock_dataset_v2(title = "Cyclable", id = "c1"))
    }
  )

  out <- dg_find_datasets(q = "vélo", n = 7)

  expect_equal(out$title, "Cyclable")
  expect_equal(seen$q, "vélo")
  expect_equal(seen$n, 7)
})

test_that("dg_find_datasets() returns an empty tibble when the API is empty", {
  local_mocked_bindings(
    fetch_search_all = function(...) list()
  )

  out <- dg_find_datasets()

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0)
  # The empty result still carries the full column set.
  expect_true("quality_score" %in% names(out))
  expect_true("has_schema" %in% names(out))
})

test_that("dg_find_datasets() coerces missing v2 fields to NA", {
  local_mocked_bindings(
    fetch_search_all = function(...) {
      list(
        mock_dataset_v2(title = "A", id = "a1", quality = list()),
        mock_dataset_v2(
          title = "B",
          id = "b2",
          organization = list(),
          metrics = list()
        )
      )
    }
  )

  out <- dg_find_datasets()

  expect_equal(out$title, c("A", "B"))
  expect_equal(out$id, c("a1", "b2"))
  expect_true(is.na(out$quality_score[1]))
  expect_true(is.na(out$organization[2]))
  expect_true(is.na(out$views[2]))
})

test_that("dg_find_datasets() resolves an exact organization slug to its id", {
  seen_org <- NULL
  local_mocked_bindings(
    fetch_organizations_all = function(...) {
      list(
        mock_organization(
          id = "534fffb0a3a7292c64a78115",
          name = "SNCF",
          slug = "sncf"
        )
      )
    },
    fetch_search_all = function(..., organization = NULL) {
      seen_org <<- organization
      list(mock_dataset_v2(title = "Horaires", id = "h1"))
    }
  )

  out <- dg_find_datasets(organization = "sncf")

  expect_equal(out$title, "Horaires")
  # The slug was resolved then forwarded as the 24-hex id.
  expect_equal(seen_org, "534fffb0a3a7292c64a78115")
})

test_that("dg_find_datasets() resolves an exact organization name to its id", {
  seen_org <- NULL
  local_mocked_bindings(
    fetch_organizations_all = function(...) {
      list(
        mock_organization(
          id = "534fffb0a3a7292c64a78115",
          name = "SNCF",
          slug = "sncf"
        )
      )
    },
    fetch_search_all = function(..., organization = NULL) {
      seen_org <<- organization
      list(mock_dataset_v2(title = "Horaires", id = "h1"))
    }
  )

  out <- dg_find_datasets(organization = "SNCF")

  expect_equal(out$title, "Horaires")
  expect_equal(seen_org, "534fffb0a3a7292c64a78115")
})

test_that("dg_find_datasets() forwards a 24-hex organization id unchanged", {
  seen_org <- NULL
  local_mocked_bindings(
    fetch_organizations_all = function(...) {
      stop("a 24-hex id must not trigger a resolution lookup")
    },
    fetch_search_all = function(..., organization = NULL) {
      seen_org <<- organization
      list(mock_dataset_v2(title = "A", id = "a1"))
    }
  )

  out <- dg_find_datasets(organization = "534fffb0a3a7292c64a78115")

  expect_equal(out$title, "A")
  expect_equal(seen_org, "534fffb0a3a7292c64a78115")
})

test_that("dg_find_datasets() errors listing candidates when no slug/name matches", {
  local_mocked_bindings(
    fetch_organizations_all = function(...) {
      list(
        mock_organization(
          id = "534fffb0a3a7292c64a78115",
          name = "SNCF",
          slug = "sncf"
        ),
        mock_organization(
          id = "5d823fd98b4c411e38e820b4",
          name = "Fluo Grand Est",
          slug = "fluo-grand-est"
        )
      )
    }
  )

  expect_error(
    dg_find_datasets(organization = "wrong-slug"),
    "No organization named exactly 'wrong-slug'"
  )
  expect_error(
    dg_find_datasets(organization = "wrong-slug"),
    "534fffb0a3a7292c64a78115"
  )
})

test_that("dg_find_datasets() errors when several organizations match exactly", {
  local_mocked_bindings(
    fetch_organizations_all = function(...) {
      list(
        mock_organization(
          id = "aaaaaaaaaaaaaaaaaaaaaaaa",
          name = "Ambiguous",
          slug = "ambig"
        ),
        mock_organization(
          id = "bbbbbbbbbbbbbbbbbbbbbbbb",
          name = "Ambiguous",
          slug = "other"
        )
      )
    }
  )

  expect_error(
    dg_find_datasets(organization = "Ambiguous"),
    "Several organizations match 'Ambiguous' exactly"
  )
})
