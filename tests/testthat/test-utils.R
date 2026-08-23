# Tests for the internal utility helpers.

# Build a fake httr2 response carrying a JSON body.
fake_json_response <- function(json, status = 200) {
  httr2::response(
    status_code = status,
    url = "https://example.org/",
    headers = list("Content-Type" = "application/json"),
    body = charToRaw(json)
  )
}

# Mock http_perform() so the package's network calls are intercepted. The
# package wraps httr2::req_perform() in the internal http_perform() helper
# (avoids @importFrom directives), so mocking that binding at the package
# level replaces every outbound request.
local_mock_req_perform <- function(response_fun, env = parent.frame()) {
  testthat::local_mocked_bindings(http_perform = response_fun, .env = env)
}

test_that("%||% returns the fallback when the value is NULL", {
  expect_equal(NULL %||% "fallback", "fallback")
  expect_equal(1 %||% "fallback", 1)
})

test_that("req_data_gouv() sets a timeout and bounded retries", {
  req <- req_data_gouv(httr2::request("https://example.org"))

  expect_equal(req$options$timeout_ms, 30000)
  expect_equal(req$policies$retry_max_tries, 3)
  expect_equal(req$policies$retry_max_wait, 8)
  expect_true(req$policies$retry_on_failure)
})

test_that("req_data_gouv() treats only gateway 429/5xx as transient", {
  is_transient <- req_data_gouv(httr2::request(
    "https://example.org"
  ))$policies$retry_is_transient

  transient <- c(429, 500, 502, 503, 504)
  expect_true(all(sapply(transient, function(st) {
    is_transient(httr2::response(status_code = st, url = "https://example.org"))
  })))

  # Non-transient statuses (including 4xx client errors) must not be retried.
  not_transient <- c(200, 400, 404, 408, 425)
  expect_false(any(sapply(not_transient, function(st) {
    is_transient(httr2::response(status_code = st, url = "https://example.org"))
  })))
})

test_that("download_resource() routes through req_data_gouv() hardening", {
  local_mock_req_perform(function(req, ...) {
    httr2::response(
      status_code = 200,
      url = "https://example.org/data.csv",
      headers = list("Content-Type" = "text/csv"),
      body = charToRaw("a,b\n1,2\n")
    )
  })

  path <- download_resource(mock_resource("csv"))

  expect_match(path, "\\.csv$")
  expect_true(file.exists(path))
  unlink(path)
})

test_that("fetch_datasets_page() parses the JSON response", {
  local_mock_req_perform(function(req, ...) {
    fake_json_response(
      '{"data": [{"title": "A"}], "next_page": null, "total": 1}'
    )
  })

  body <- fetch_datasets_page(page = 1, page_size = 20, format = "csv")

  expect_equal(body$total, 1)
  expect_equal(body$data[[1]]$title, "A")
})

test_that("fetch_datasets_page() forwards the search query", {
  seen_query <- NULL
  local_mock_req_perform(function(req, ...) {
    seen_query <<- httr2::url_parse(req$url)$query$q
    fake_json_response('{"data": [], "next_page": null, "total": 0}')
  })

  fetch_datasets_page(page = 1, page_size = 20, q = "vélo", format = "csv")

  expect_equal(seen_query, "vélo")
})

test_that("fetch_datasets_page() requests a single format server-side", {
  seen <- NULL
  local_mock_req_perform(function(req, ...) {
    # `format` is a single value per page: the API filters one format at a time
    # and fetch_all_datasets() unions across formats.
    seen <<- httr2::url_parse(req$url)$query$format
    fake_json_response('{"data": [], "next_page": null, "total": 0}')
  })

  fetch_datasets_page(page = 1, page_size = 20, format = "csv")

  expect_equal(seen, "csv")
})

test_that("catalog_formats() is the official data.gouv tabular set", {
  expect_equal(catalog_formats(), c("csv", "csv.gz", "xls", "xlsx", "parquet"))
  # Every catalog format must be directly parseable (no JSON/TSV/TXT here).
  expect_true(all(catalog_formats() %in% supported_formats()))
  # The discovery catalog is deliberately narrower than what can be parsed.
  expect_true(length(catalog_formats()) < length(supported_formats()))
})

test_that("resource_has_schema() detects a schema pointer by name or url", {
  by_name <- mock_resource("csv")
  by_name$schema <- list(name = "etalab/schema-bal", url = NULL, version = NULL)
  by_url <- mock_resource("csv")
  by_url$schema <- list(name = NULL, url = "https://example.org/schema.json")
  empty <- mock_resource("csv")
  empty$schema <- list(name = NULL, url = NULL)
  none <- mock_resource("csv") # no $schema node at all

  expect_true(resource_has_schema(by_name))
  expect_true(resource_has_schema(by_url))
  expect_false(resource_has_schema(empty))
  expect_false(resource_has_schema(none))
})

test_that("fetch_all_datasets() stops once n datasets are collected", {
  # Simulate a server that honours page_size: each call returns at most
  # page_size items from a shared (large) pool, each with a unique id.
  titles <- letters[1:20]
  requested_sizes <- integer()
  formats_seen <- character()
  local_mocked_bindings(
    fetch_datasets_page = function(page, page_size, q = NULL, format) {
      requested_sizes <<- c(requested_sizes, page_size)
      formats_seen <<- c(formats_seen, format)
      start <- (page - 1) * page_size + 1
      end <- min(page * page_size, length(titles))
      list(
        data = Map(
          mock_dataset,
          title = titles[start:end],
          id = paste0("id", start:end)
        ),
        next_page = if (end < length(titles)) paste0("page", page + 1) else NULL
      )
    }
  )

  out <- fetch_all_datasets(page_size = 100, n = 5, format = "csv")

  expect_length(out, 5)
  expect_equal(
    unname(vapply(out, function(x) x$title, character(1))),
    letters[1:5]
  )
  # The first request is capped at n (5), and no further page is fetched.
  expect_equal(requested_sizes, 5)
  expect_equal(formats_seen, "csv")
})

test_that("fetch_all_datasets() fetches all pages when n is Inf", {
  titles <- letters[1:7]
  local_mocked_bindings(
    fetch_datasets_page = function(page, page_size, q = NULL, format) {
      start <- (page - 1) * page_size + 1
      end <- min(page * page_size, length(titles))
      list(
        data = Map(
          mock_dataset,
          title = titles[start:end],
          id = paste0("id", start:end)
        ),
        next_page = if (end < length(titles)) paste0("page", page + 1) else NULL
      )
    }
  )

  out <- fetch_all_datasets(page_size = 3, n = Inf, format = "csv")

  expect_length(out, 7)
  expect_equal(
    unname(vapply(out, function(x) x$title, character(1))),
    letters[1:7]
  )
})

test_that("fetch_all_datasets() honors the search query", {
  seen <- list()
  local_mocked_bindings(
    fetch_datasets_page = function(page, page_size, q = NULL, format) {
      seen <<- c(seen, list(q))
      list(data = list(mock_dataset(title = "A")), next_page = NULL)
    }
  )

  fetch_all_datasets(page_size = 100, q = "vélo", n = 1000, format = "csv")

  expect_equal(seen, list("vélo"))
})

test_that("fetch_all_datasets() pages until there is no next page", {
  pages <- list(
    list(data = list(mock_dataset(title = "A", id = "a")), next_page = "page2"),
    list(data = list(mock_dataset(title = "B", id = "b")), next_page = NULL)
  )
  local_mocked_bindings(
    fetch_datasets_page = function(page, page_size, q = NULL, format) {
      pages[[page]]
    }
  )

  out <- fetch_all_datasets(format = "csv")

  expect_length(out, 2)
  expect_equal(vapply(out, function(x) x$title, character(1)), c("A", "B"))
})

test_that("fetch_all_datasets() stops on an empty page", {
  local_mocked_bindings(
    fetch_datasets_page = function(page, page_size, q = NULL, format) {
      list(data = list(), next_page = NULL)
    }
  )

  out <- fetch_all_datasets(format = "csv")

  expect_length(out, 0)
})

test_that("fetch_all_datasets() unions multiple formats and deduplicates by id", {
  # csv query yields dataset x1 (csv only) and shared (csv+xlsx); xlsx query
  # yields shared and x2 (xlsx only). The shared dataset has a different id from
  # x2 but the same data under a different format.
  by_format <- list(
    csv = list(
      mock_dataset(title = "Only CSV", id = "x1"),
      mock_dataset(title = "Both", id = "shared")
    ),
    xlsx = list(
      mock_dataset(title = "Both", id = "shared"),
      mock_dataset(title = "Only XLSX", id = "x2")
    )
  )
  formats <- character()
  local_mocked_bindings(
    fetch_datasets_page = function(page, page_size, q = NULL, format) {
      formats <<- c(formats, format)
      list(
        data = switch(format, csv = by_format$csv, xlsx = by_format$xlsx),
        next_page = NULL
      )
    }
  )

  out <- fetch_all_datasets(n = 100, format = c("csv", "xlsx"))

  # Both formats are queried, and the shared dataset is returned only once.
  expect_equal(formats, c("csv", "xlsx"))
  expect_length(out, 3)
  expect_equal(
    vapply(out, function(x) x$id, character(1)),
    c("x1", "shared", "x2")
  )
})

test_that("fetch_all_datasets() defaults to the catalog formats", {
  formats <- character()
  local_mocked_bindings(
    fetch_datasets_page = function(page, page_size, q = NULL, format) {
      formats <<- c(formats, format)
      list(data = list(mock_dataset(title = "A")), next_page = NULL)
    }
  )

  fetch_all_datasets(n = 1000)

  expect_setequal(formats, catalog_formats())
})

test_that("find_dataset() returns the exact-matching title", {
  local_mock_req_perform(function(req, ...) {
    fake_json_response(
      '{"data": [{"title": "Not it"}, {"title": "Target dataset"}]}'
    )
  })

  out <- find_dataset("Target dataset")

  expect_equal(out$title, "Target dataset")
})

test_that("find_dataset() errors when no title matches exactly", {
  local_mock_req_perform(function(req, ...) {
    fake_json_response('{"data": [{"title": "Something else"}]}')
  })

  expect_snapshot(error = TRUE, find_dataset("Does not exist"))
})

test_that("is_dataset_id() recognises 24-char hex object ids", {
  expect_true(is_dataset_id("6397c0ff56d3963118a18345"))
  expect_true(is_dataset_id("AAAAAAAAAAAAAAAAAAAAAAAA"))
  expect_false(is_dataset_id("A"))
  expect_false(is_dataset_id("This is a dataset title, not an id."))
  expect_false(is_dataset_id("6397c0ff56d3963118a1834")) # too short
  expect_false(is_dataset_id(NA_character_))
})

test_that("uniquify_names() disambiguates duplicated names with their value", {
  x <- c("A" = "id1", "A" = "id2", "B" = "id3", "C" = "id4")
  out <- uniquify_names(x)

  expect_equal(
    names(out),
    c("A [id1]", "A [id2]", "B", "C")
  )
  # Values are preserved unchanged.
  expect_equal(unname(out), c("id1", "id2", "id3", "id4"))
})

test_that("uniquify_names() leaves already-unique names alone", {
  x <- c("A" = "id1", "B" = "id2")
  out <- uniquify_names(x)

  expect_equal(names(out), c("A", "B"))
})

test_that("find_dataset() fetches directly by identifier when given an id", {
  local_mock_req_perform(function(req, ...) {
    # The id path must return a single dataset object, not a search-result page.
    fake_json_response(
      '{"id": "6397c0ff56d3963118a18345", "title": "Vélo", "resources": []}'
    )
  })

  out <- find_dataset("6397c0ff56d3963118a18345")

  expect_equal(out$title, "Vélo")
})

test_that("find_dataset() falls back to title search for non-id input", {
  local_mock_req_perform(function(req, ...) {
    fake_json_response(
      '{"data": [{"title": "Not it"}, {"title": "Target dataset"}]}'
    )
  })

  out <- find_dataset("Target dataset")

  expect_equal(out$title, "Target dataset")
})

test_that("read_first_parseable_resource() returns the first successful candidate", {
  local_mocked_bindings(
    read_resource = function(resource) {
      if (resource$format == "pdf") {
        stop("cannot parse pdf")
      }
      mock_csv_data()
    }
  )
  dataset <- mock_dataset(
    resources = list(
      mock_resource("pdf"),
      mock_resource("csv", title = "data.csv")
    )
  )

  out <- read_first_parseable_resource(dataset)

  expect_equal(out$data, mock_csv_data())
  expect_equal(out$resource$format, "csv")
})

test_that("read_first_parseable_resource() skips a failing candidate and tries the next", {
  # The first candidate (a JSON resource) fails to parse; the helper must move
  # on to the CSV instead of erroring.
  attempt <- 0L
  local_mocked_bindings(
    read_resource = function(resource) {
      if (resource$format == "json") {
        stop("Tibble columns must have compatible sizes")
      }
      mock_csv_data()
    }
  )
  dataset <- mock_dataset(
    resources = list(
      mock_resource("json", title = "metadata"),
      mock_resource("csv", title = "data.csv")
    )
  )

  out <- read_first_parseable_resource(dataset)

  expect_equal(out$data, mock_csv_data())
  expect_equal(out$resource$format, "csv")
})

test_that("read_first_parseable_resource() auto-selects a zip resource", {
  local_mocked_bindings(
    read_resource = function(resource) mock_csv_data()
  )
  dataset <- mock_dataset(
    resources = list(
      mock_resource("pdf"),
      mock_resource("zip", title = "archive.zip")
    )
  )

  out <- read_first_parseable_resource(dataset)

  expect_equal(out$resource$format, "zip")
})

test_that("read_first_parseable_resource() errors when no resource is supported", {
  dataset <- mock_dataset(resources = list(mock_resource("pdf")))

  expect_snapshot(error = TRUE, read_first_parseable_resource(dataset))
})

test_that("read_first_parseable_resource() picks the lightest of same-data formats", {
  # A dataset offering the same table as both csv and xlsx: the xlsx copy is
  # smaller, so it must be chosen to lighten the download.
  csv <- mock_resource(
    format = "csv",
    title = "data.csv",
    url = "https://x/data.csv",
    filesize = 100000
  )
  xlsx <- mock_resource(
    format = "xlsx",
    title = "data.xlsx",
    url = "https://x/data.xlsx",
    filesize = 40000
  )
  dataset <- mock_dataset(resources = list(csv, xlsx))
  local_mocked_bindings(read_resource = function(resource) mock_csv_data())

  out <- read_first_parseable_resource(dataset)

  expect_equal(out$resource$format, "xlsx")
})

test_that("read_first_parseable_resource() keeps declared order for distinct data", {
  # Distinct files (different base names) must keep their declared order, so the
  # first (population.csv) is chosen even though the second is lighter.
  pop <- mock_resource(
    format = "csv",
    title = "population.csv",
    filesize = 90000
  )
  income <- mock_resource(format = "csv", title = "income.csv", filesize = 1000)
  dataset <- mock_dataset(resources = list(pop, income))
  local_mocked_bindings(read_resource = function(resource) mock_csv_data())

  out <- read_first_parseable_resource(dataset)

  expect_equal(out$resource$title, "population.csv")
})

test_that("prefer_lightest_file() keeps the lightest copy of a duplicated stem", {
  res <- list(
    mock_resource(format = "csv", title = "data.csv", filesize = 500),
    mock_resource(format = "xlsx", title = "data.xlsx", filesize = 50),
    mock_resource(format = "csv", title = "other.csv", filesize = 999)
  )

  out <- prefer_lightest_file(res)

  expect_length(out, 2)
  expect_equal(out[[1]]$title, "data.xlsx")
  expect_equal(out[[2]]$title, "other.csv")
})

test_that("prefer_lightest_file() falls back to the first copy when sizes are absent", {
  res <- list(
    mock_resource(format = "csv", title = "data.csv", filesize = NULL),
    mock_resource(format = "xlsx", title = "data.xlsx", filesize = NULL)
  )

  out <- prefer_lightest_file(res)

  expect_length(out, 1)
  expect_equal(out[[1]]$format, "csv")
})

test_that("prefer_lightest_file() leaves distinct resources in order", {
  res <- list(
    mock_resource(format = "csv", title = "a.csv"),
    mock_resource(format = "csv", title = "b.csv")
  )

  out <- prefer_lightest_file(res)

  expect_length(out, 2)
  expect_equal(
    vapply(out, function(x) x$title, character(1)),
    c("a.csv", "b.csv")
  )
})

test_that("read_first_parseable_resource() errors when every candidate fails", {
  local_mocked_bindings(
    read_resource = function(resource) stop("boom")
  )
  dataset <- mock_dataset(
    resources = list(
      mock_resource("csv", title = "a.csv"),
      mock_resource("tsv", title = "b.tsv")
    )
  )

  expect_snapshot(error = TRUE, read_first_parseable_resource(dataset))
})

local_csv_path <- function(ext, lines) {
  path <- tempfile(fileext = paste0(".", ext))
  writeLines(lines, path)
  path
}

test_that("read_resource() parses a CSV resource", {
  local_mocked_bindings(
    download_resource = function(resource) {
      local_csv_path("csv", c("a,b", "1,x", "2,y"))
    }
  )

  out <- read_resource(mock_resource("csv"))

  expect_named(out, c("a", "b"))
  expect_equal(nrow(out), 2)
})

test_that("read_resource() supports tsv and txt resources", {
  local_mocked_bindings(
    download_resource = function(resource) {
      local_csv_path("tsv", c("a\tb", "1\tx"))
    }
  )

  out <- read_resource(mock_resource("tsv"))

  expect_named(out, c("a", "b"))
  expect_equal(nrow(out), 1)
})

test_that("read_resource() parses a txt resource with a tab delim", {
  local_mocked_bindings(
    download_resource = function(resource) {
      local_csv_path("txt", c("a\tb", "1\tx"))
    }
  )

  out <- read_resource(mock_resource("txt"))

  expect_named(out, c("a", "b"))
  expect_equal(nrow(out), 1)
})

test_that("read_resource() auto-detects a European semicolon CSV", {
  local_mocked_bindings(
    download_resource = function(resource) {
      local_csv_path("csv", c("a;b", "1,5;x", "2,7;y"))
    }
  )

  out <- read_resource(mock_resource("csv"))

  expect_named(out, c("a", "b"))
  expect_equal(out$a, c(1.5, 2.7))
})

test_that("read_resource() guesses a pipe delimiter as given a csv.gz file", {
  local_mocked_bindings(
    download_resource = function(resource) {
      local_csv_path("csv.gz", c("a|b", "1|x"))
    }
  )

  out <- read_resource(mock_resource("csv.gz"))

  expect_named(out, c("a", "b"))
  expect_equal(nrow(out), 1)
})

test_that("read_json_file() parses one row per object in a JSON array", {
  path <- local_csv_path("json", '[{"a":1,"b":"x"},{"a":2,"b":"y"}]')

  out <- read_json_file(path)

  expect_equal(nrow(out), 2)
  expect_named(out, c("a", "b"))
})

test_that("read_json_file() parses newline-delimited JSON", {
  path <- local_csv_path("json", c('{"a":1,"b":"x"}', '{"a":2,"b":"y"}'))

  out <- read_json_file(path)

  expect_equal(nrow(out), 2)
  expect_named(out, c("a", "b"))
})

test_that("read_json_file() wraps a single JSON object into one row", {
  path <- local_csv_path("json", '{"a":1,"b":"x"}')

  out <- read_json_file(path)

  expect_equal(nrow(out), 1)
  expect_named(out, c("a", "b"))
})

test_that("read_json_file() errors clearly on a non-tabular nested object", {
  # A top-level object whose fields cannot line up into rows (an array of `n`
  # records alongside a nested object with a different number of keys, e.g. an
  # API metadata document) is not a table: fail with an actionable message
  # instead of a cryptic tibble error.
  json <- paste0(
    '{"links":[{"rel":"self"},{"rel":"datasets"},{"rel":"a"},',
    '{"rel":"b"},{"rel":"c"}],',
    '"dataset":{"k1":1,"k2":2,"k3":3,"k4":4,"k5":5,"k6":6,"k7":7,',
    '"k8":8,"k9":9,"k10":10}}'
  )
  path <- local_csv_path("json", json)

  expect_snapshot(error = TRUE, read_json_file(path))
})

test_that("read_resource() parses a JSON resource", {
  local_mocked_bindings(
    download_resource = function(resource) {
      local_csv_path("json", '[{"a":1,"b":"x"},{"a":2,"b":"y"}]')
    }
  )

  out <- read_resource(mock_resource("json"))

  expect_equal(nrow(out), 2)
  expect_named(out, c("a", "b"))
})

test_that("read_resource() parses an xlsx resource", {
  skip_if_not_installed("writexl")
  local_mocked_bindings(
    download_resource = function(resource) {
      path <- tempfile(fileext = ".xlsx")
      writexl::write_xlsx(data.frame(a = 1:2, b = c("x", "y")), path)
      path
    }
  )

  out <- read_resource(mock_resource("xlsx"))

  expect_named(out, c("a", "b"))
  expect_equal(nrow(out), 2)
})

test_that("read_resource() parses an xls (legacy Excel) resource", {
  skip_if_not_installed("writexl")
  local_mocked_bindings(
    download_resource = function(resource) {
      # readxl handles .xls and .xlsx identically; write a real xlsx workbook
      # and serve it under an .xlsx path so the xlsx parser (not the legacy
      # libxls one) is used, while still routing through the "xls" branch.
      path <- tempfile(fileext = ".xlsx")
      writexl::write_xlsx(data.frame(a = 1:2, b = c("x", "y")), path)
      path
    }
  )

  out <- read_resource(mock_resource("xls"))

  expect_named(out, c("a", "b"))
  expect_equal(nrow(out), 2)
})

test_that("read_resource() parses a parquet resource", {
  skip_if_not_installed("nanoparquet")
  local_mocked_bindings(
    download_resource = function(resource) {
      path <- tempfile(fileext = ".parquet")
      nanoparquet::write_parquet(data.frame(a = 1:2, b = c("x", "y")), path)
      path
    }
  )

  out <- read_resource(mock_resource("parquet"))

  expect_named(out, c("a", "b"))
  expect_equal(nrow(out), 2)
})

test_that("read_resource() errors on unsupported formats", {
  local_mocked_bindings(
    download_resource = function(resource) local_csv_path("csv", c("a", "1"))
  )

  expect_snapshot(error = TRUE, read_resource(mock_resource("pdf")))
})

# Write `files` (a named list of path -> lines) into a zip file.
local_zip_path <- function(files, format = "zip") {
  dir <- tempfile(pattern = "zip-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  for (nm in names(files)) {
    writeLines(files[[nm]], file.path(dir, nm))
  }
  zip_path <- tempfile(fileext = paste0(".", format))
  utils::zip(zip_path, files = list.files(dir, full.names = TRUE), flags = "-j")
  zip_path
}

test_that("read_resource() parses every supported file in a ZIP resource", {
  local_mocked_bindings(
    download_resource = function(resource) {
      local_zip_path(list(
        "data.csv" = c("a,b", "1,x", "2,y"),
        "notes.tsv" = c("c\td", "1\te")
      ))
    }
  )

  out <- read_resource(mock_resource("zip"))

  expect_length(out, 2)
  expect_named(out, c("data.csv", "notes.tsv"))
  expect_equal(nrow(out$data.csv), 2)
  expect_named(out$data.csv, c("a", "b"))
  expect_equal(nrow(out$notes.tsv), 1)
  expect_named(out$notes.tsv, c("c", "d"))
})

test_that("read_resource() skips unsupported files inside a ZIP resource", {
  local_mocked_bindings(
    download_resource = function(resource) {
      local_zip_path(list(
        "data.csv" = c("a,b", "1,x"),
        "doc.pdf" = "%PDF-1.4 fake",
        "readme.txt" = "just a note"
      ))
    }
  )

  out <- read_resource(mock_resource("zip"))

  # The pdf is skipped, while the csv and txt (tab-delimited) are parsed.
  expect_length(out, 2)
  expect_named(out, c("data.csv", "readme.txt"))
})

test_that("read_resource() parses a multi-dot csv.gz file inside a ZIP", {
  local_mocked_bindings(
    download_resource = function(resource) {
      local_zip_path(list("data.csv.gz" = c("a;b", "1,5;x")))
    }
  )

  out <- read_resource(mock_resource("zip"))

  expect_named(out, "data.csv.gz")
  expect_equal(out[[1]]$a, 1.5)
})

test_that("read_resource() returns an empty list for an unreadable ZIP", {
  local_mocked_bindings(
    download_resource = function(resource) {
      local_zip_path(list("doc.pdf" = "%PDF-1.4 fake"))
    }
  )

  out <- read_resource(mock_resource("zip"))

  expect_length(out, 0)
})

test_that("download_resource() writes the expected bytes based on format", {
  local_mock_req_perform(function(req, ...) {
    httr2::response(
      status_code = 200,
      url = "https://example.org/data.csv",
      headers = list("Content-Type" = "text/csv"),
      body = charToRaw("a,b\n1,2\n")
    )
  })

  path <- download_resource(mock_resource("csv"))

  expect_match(path, "\\.csv$")
  expect_true(file.exists(path))
  unlink(path)
})

test_that("download_resource() falls back to .bin when the format is missing", {
  res <- mock_resource(format = NULL)
  local_mock_req_perform(function(req, ...) {
    httr2::response(
      status_code = 200,
      url = "https://example.org/data",
      headers = list("Content-Type" = "application/octet-stream"),
      body = charToRaw("hello")
    )
  })

  path <- download_resource(res)

  expect_match(path, "\\.bin$")
  expect_true(file.exists(path))
  unlink(path)
})
