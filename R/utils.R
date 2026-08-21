# Internal helpers for the datagouv package.
# These functions are not exported.

# Base URL of the data.gouv public API.
datagouv_base_url <- function() {
  "https://www.data.gouv.fr/api/1/"
}

# Base URL of the data.gouv public API v2.
datagouv_base_url_v2 <- function() {
  "https://www.data.gouv.fr/api/2/"
}

# Build a configured httr2 request against the data.gouv API.
# Adds a polite user agent, a timeout, retry on transient errors and a
# friendly error message extracted from the JSON error body.
#
# data.gouv's API (behind nginx) intermittently answers 5xx for otherwise
# valid requests, so we retry genuinely transient statuses (429 and 5xx).
# 4xx responses are NOT retried: a real 400/404/408 is a permanent
# condition, and re-sending it with backoff would multiply the latency of an
# already-slow page crawl for no gain. Low-level failures (timeouts, dropped
# connections, DNS) are retried too, but within a tight global budget so a
# flaky endpoint cannot stall the whole enumeration for minutes.
req_data_gouv <- function(req) {
  httr2::req_retry(
    httr2::req_error(
      httr2::req_timeout(
        # A hung reply must not block dg_pull_dataset() indefinitely.
        httr2::req_user_agent(
          req,
          "datagouv R package (https://github.com/stamm-a/datagouv)"
        ),
        seconds = 30
      ),
      is_error = function(resp) httr2::resp_status(resp) >= 400,
      body = function(resp) {
        tryCatch(
          httr2::resp_body_json(resp)$message,
          error = function(e) ""
        )
      }
    ),
    is_transient = function(resp) {
      httr2::resp_status(resp) %in% c(429, 500, 502, 503, 504)
    },
    # Also retry low-level failures (timeouts, dropped connections, DNS).
    retry_on_failure = TRUE,
    max_tries = 3,
    # Caps total retry time so a failing endpoint cannot stall the call
    # for minutes on end.
    max_seconds = 8
  )
}

# Perform a prepared request. A thin internal wrapper around
# httr2::req_perform() so callers avoid @importFrom directives while keeping a
# single, easily mockable seam for tests.
http_perform <- function(req) {
  httr2::req_perform(req)
}

# Fetch a single page of datasets from the API for a single resource format.
#
# The API only honours one `format` value per query (a comma-joined or repeated
# `format` is not unioned), so a page is always fetched for exactly one format;
# `fetch_all_datasets()` issues one query per requested format and unions them.
fetch_datasets_page <- function(page, page_size, q = NULL, format) {
  req <- httr2::req_url_query(
    httr2::req_url_path_append(
      req_data_gouv(httr2::request(datagouv_base_url())),
      "datasets"
    ),
    page = page,
    page_size = page_size,
    format = format
  )
  if (!is.null(q)) {
    req <- httr2::req_url_query(req, q = q)
  }
  httr2::resp_body_json(http_perform(req))
}

# Fetch a single page of datasets from the API V2 for a single resource format.
#
# The API only honours one `format` value per query (a comma-joined or repeated
# `format` is not unioned), so a page is always fetched for exactly one format;
# `fetch_all_datasets()` issues one query per requested format and unions them.
fetch_datasets_page_v2 <- function(page, page_size, q = NULL, format) {
  req <- httr2::req_url_query(
    httr2::req_url_path_append(
      req_data_gouv(httr2::request(datagouv_base_url_v2())),
      "datasets/search"
    ),
    page = page,
    page_size = page_size,
    format = format
  )
  if (!is.null(q)) {
    req <- httr2::req_url_query(req, q = q)
  }
  httr2::resp_body_json(http_perform(req))
}

# Fetch dataset objects, following pagination until the last page or until `n`
# datasets have been collected (whichever comes first).
#
# `q` is an optional full-text query forwarded to the API, so the search is
# done server-side instead of downloading and filtering the whole catalog.
#
# `n` bounds the number of datasets returned; the default caps the work so a
# caller cannot accidentally trigger a huge crawl of the entire platform. Pass
# `n = Inf` to enumerate everything.
#
# `format` is one or more resource formats to keep. Because the API filters
# only one format per query, one query per requested format is issued and the
# results are combined, removing datasets that matched more than one format
# (the full dataset object is returned identically whichever format matched, so
# deduplication by dataset id keeps a single copy).
fetch_all_datasets <- function(
  page_size = 1000,
  q = NULL,
  n = 1000,
  format = catalog_formats(),
  api_version = 1
  ){
  
  if( api_version == 2) { fetch_api <- fetch_datasets_page_v2 }
  else { fetch_api <- fetch_datasets_page }

  all <- list()
  seen_ids <- character()
  for (fmt in format) {
    if (length(all) >= n) {
      break
    }
    datasets <- list()
    page <- 1
    repeat {
      if (length(all) + length(datasets) >= n) {
        break
      }
      remaining <- n - length(all) - length(datasets)
      this_size <- min(page_size, remaining)
      body <- fetch_api(page, this_size, q = q, format = fmt)
      items <- body$data
      if (length(items) == 0) {
        break
      }
      datasets <- c(datasets, items)
      if (is.null(body$next_page)) {
        break
      }
      page <- page + 1
    }
    # Keep only datasets not already yielded by an earlier format query, and
    # drop duplicates within this format's pages (full objects are identical,
    # so either copy is equivalent).
    ids <- vapply(datasets, function(d) d$id %||% NA_character_, character(1))
    keep <- !(ids %in% seen_ids) & !duplicated(ids)
    all <- c(all, datasets[keep])
    seen_ids <- c(seen_ids, ids[keep])
  }
  all
}

# Test whether a string is a data.gouv dataset identifier (a MongoDB
# ObjectId: 24 hexadecimal characters).
is_dataset_id <- function(x) {
  !is.na(x) && grepl("^[0-9a-fA-F]{24}$", x)
}

# Make the names of a named list unique by appending each element's value to
# names that are shared by several elements. This keeps human-readable titles
# as labels while guaranteeing every row remains distinguishable even when
# titles collide (the values, typically dataset identifiers, are unique).
uniquify_names <- function(x) {
  nm <- names(x)
  dup <- duplicated(nm) | duplicated(nm, fromLast = TRUE)
  nm[dup] <- paste0(nm[dup], " [", x[dup], "]")
  names(x) <- nm
  x
}

# Fetch a single dataset object by its identifier.
#
# Unlike title-based lookup (which searches and filters, and can be ambiguous
# when titles collide), identifiers are unique and stable, so a direct GET on
# the `/datasets/{id}/` endpoint always returns exactly the right dataset.
fetch_dataset <- function(id) {
  httr2::resp_body_json(
    http_perform(
      httr2::req_url_path_append(
        req_data_gouv(httr2::request(datagouv_base_url())),
        "datasets",
        id
      )
    )
  )
}

# Find a dataset object by its identifier, or, as a fallback kept for
# backwards compatibility, by its exact title.
find_dataset <- function(id) {
  if (is_dataset_id(id)) {
    return(fetch_dataset(id))
  }
  body <- httr2::resp_body_json(
    http_perform(
      httr2::req_url_query(
        httr2::req_url_path_append(
          req_data_gouv(httr2::request(datagouv_base_url())),
          "datasets"
        ),
        q = id,
        page_size = 50
      )
    )
  )

  hits <- Filter(function(d) identical(d$title, id), body$data)
  if (length(hits) == 0) {
    stop(
      "No dataset titled '",
      id,
      "' was found on data.gouv.fr. Check the name with dg_list_datasets().",
      call. = FALSE
    )
  }
  hits[[1]]
}

# Resource formats that can be parsed into a table. A "zip" resource is
# itself unreadable, but its archive can hold files in any of the other
# supported formats, so it is included here so that a ZIP is picked up as a
# candidate and read_resource() unpacks it.
#
# The first block is the official set of tabular formats data.gouv.fr indexes
# in its tabular service (csv, csv.gz, xls, xlsx, parquet). The full vector is
# wider because direct pulls (dg_pull_dataset()/dg_refetch()) still parse
# trivially-tabular TSV/TXT and JSON that data.gouv does not guarantee is
# tabular at catalog time.
supported_formats <- function() {
  c("zip", "csv", "csv.gz", "xls", "xlsx", "parquet", "tsv", "txt", "json")
}

# Formats a dataset must contain at least one resource of to be listed in the
# discovery catalog. This is data.gouv's own set of tabular formats (see
# https://www.data.gouv.fr/dataservices/api-tabulaire-data-gouv-fr-beta); it is
# deliberately narrower than supported_formats() because only these are
# guaranteed tabular by the platform.
catalog_formats <- function() {
  c("csv", "csv.gz", "xls", "xlsx", "parquet")
}

# Whether a resource points at a declared data schema. data.gouv attaches the
# schema as a pointer (a `schema` node carrying `name` and/or `url`); the actual
# `fields` documentation lives in the referenced schema document on
# schema.data.gouv.fr. NULL fields mean no schema has been declared.
resource_has_schema <- function(resource) {
  schema <- resource$schema %||% list()
  !is.null(schema$name) || !is.null(schema$url)
}

# Among candidate resources, when several appear to carry the *same data* in
# different formats (same base file name, different extension), keep only the
# one with the smallest advertised file size so a later download is as light as
# possible. Resources with distinct names keep their declared order. This speeds
# up dg_pull_dataset()/dg_refetch(), which choose the first resource that
# parses: a light duplicate avoids downloading a heavier twin that holds the
# same table.
prefer_lightest_file <- function(resources) {
  stem <- function(r) {
    nm <- r$title %||% r$url %||% ""
    tools::file_path_sans_ext(basename(sub("^.*/", "", nm)))
  }
  st <- vapply(resources, stem, character(1))
  dup <- duplicated(st) | duplicated(st, fromLast = TRUE)
  if (!any(dup)) {
    return(resources)
  }
  out <- list()
  for (s in unique(st)) {
    idx <- which(st == s)
    if (length(idx) == 1) {
      out[[length(out) + 1]] <- resources[[idx]]
      next
    }
    sizes <- vapply(
      resources[idx],
      function(r) r$filesize %||% NA_real_,
      numeric(1)
    )
    pick <- idx[[1]]
    if (!all(is.na(sizes))) {
      pick <- idx[which.min(sizes)]
    }
    out[[length(out) + 1]] <- resources[[pick]]
  }
  out
}

# Walk a dataset's tabular candidates in declared order and return the first
# that actually parses into a table.
#
# data.gouv declares a format on every resource, but the declaration is not
# always reliable: a resource tagged `json` can in practice serve an API
# metadata document (e.g. `{"links": ..., "dataset": ...}`) rather than tabular
# data, and such a resource cannot be read as a table. Because real
# parseability is only knowable after downloading, we try each candidate in
# order and keep the first that succeeds. If none parse, we error naming the
# dataset and the first failure so the user is not left guessing which resource
# was at fault.
#
# Candidates offering the same data in several formats are first reduced to
# their lightest copy (see prefer_lightest_file()), so a dataset published as
# both .csv and .xlsx downloads the smaller file.
read_first_parseable_resource <- function(dataset) {
  candidates <- Filter(
    function(r) tolower(r$format %||% "") %in% supported_formats(),
    dataset$resources %||% list()
  )
  if (length(candidates) == 0) {
    supported <- paste(supported_formats(), collapse = ", ")
    stop(
      "Dataset '",
      dataset$title,
      "' has no resource in a supported format (",
      supported,
      ").",
      call. = FALSE
    )
  }
  candidates <- prefer_lightest_file(candidates)
  first_error <- NULL
  for (res in candidates) {
    data <- tryCatch(read_resource(res), error = function(e) e)
    if (!inherits(data, "error")) {
      return(list(data = data, resource = res))
    }
    if (is.null(first_error)) {
      first_error <- data
    }
  }
  stop(
    "None of the ",
    length(candidates),
    " tabular resource(s) of dataset '",
    dataset$title,
    "' could be parsed into a table. First failure: ",
    conditionMessage(first_error),
    call. = FALSE
  )
}

# `x %||% y` returns x unless x is NULL, in which case it returns y.
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

# Guess the field separator of a delimited text file by counting candidate
# delimiters in the first lines. The extension (.csv, .txt, ...) says little
# about the actual delimiter, so we sniff it from the data. Candidates are
# tried in a fixed order and the one with the most occurrences wins; ties are
# broken by that order (tab > semicolon > comma > pipe > colon).
guess_delimiter <- function(path, n = 20) {
  lines <- readLines(path, n = n, warn = FALSE)
  candidates <- c("\t", ";", ",", "|", ":")
  counts <- vapply(
    candidates,
    function(d) {
      sum(lengths(regmatches(lines, gregexpr(d, lines, fixed = TRUE))))
    },
    integer(1)
  )
  candidates[which.max(counts)]
}

# Parse a JSON resource into a data frame. data.gouv JSON files come in two
# shapes: an array of objects (one row per object) or newline-delimited JSON
# (one object per line); both are handled, and a bare single object is wrapped
# into a one-row table so the result is always a data frame. A JSON *array* is
# read with fromJSON(); when that fails the file is newline-delimited JSON
# (concatenated objects), which fromJSON() rejects but stream_in() reads.
read_json_file <- function(path) {
  out <- tryCatch(
    jsonlite::fromJSON(path, flatten = TRUE),
    error = function(e) NULL
  )
  if (is.data.frame(out)) {
    return(out)
  }
  if (is.list(out) && !is.null(names(out))) {
    # A top-level object is normally a single row, e.g. {"a": 1, "b": "x"}.
    # But a nested object with list-valued or variable-length fields (such as
    # an API metadata document describing a resource) is not a table. Fail with
    # a clear, actionable message rather than let tibble::as_tibble() raise a
    # cryptic "incompatible sizes" error.
    return(tryCatch(
      tibble::as_tibble(out),
      error = function(e) {
        stop(
          "JSON object is not tabular data: ",
          conditionMessage(e),
          ". ",
          "This resource declares `json` but does not contain a table (it is ",
          "likely an API metadata document). Try another resource of the ",
          "dataset, e.g. via dg_list_datasets() or dg_refetch().",
          call. = FALSE
        )
      }
    ))
  }
  # fromJSON() returned nothing (empty file) or threw: newline-delimited JSON.
  jsonlite::stream_in(file(path), verbose = FALSE)
}

# Parse a local file of a known supported format into a data frame. The file
# must already be on disk; callers are responsible for downloading (or
# extracting) it and for cleaning it up.
parse_resource_file <- function(path, fmt) {
  if (fmt == "xlsx" || fmt == "xls") {
    return(readxl::read_excel(path))
  }
  if (fmt == "parquet") {
    return(nanoparquet::read_parquet(path))
  }
  if (fmt == "json") {
    return(read_json_file(path))
  }
  # Every other supported format is delimited text (CSV, CSV.GZ, TSV or TXT).
  delim <- guess_delimiter(path)
  if (delim == "\t") {
    return(readr::read_tsv(path))
  }
  if (delim == ";") {
    # European-style CSV: semicolon field separator with a comma decimal mark.
    return(readr::read_csv2(path))
  }
  if (delim == ",") {
    return(readr::read_csv(path))
  }
  # Any other delimiter (e.g. pipe or colon): use the generic reader.
  readr::read_delim(path, delim = delim)
}

# Map a file path to a supported resource format by its extension, or NA if
# the extension is not one of the supported formats. Multi-dot formats such
# as ".csv.gz" are matched as a whole so they are not confused with a plain
# ".gz", which cannot be parsed on its own.
format_from_path <- function(path) {
  sup <- supported_formats()
  hit <- sup[endsWith(tolower(basename(path)), paste0(".", sup))]
  if (length(hit) == 0) NA_character_ else hit[[1]]
}

# Parse a ZIP resource: extract its contents to a temporary directory, then
# parse every contained file whose extension maps to a supported format,
# skipping the rest. The result is a named list with one element per parsed
# file (names made unique in case two files share a base name); it is empty
# when the archive holds nothing readable.
read_zip_resource <- function(resource) {
  zip <- download_resource(resource)
  on.exit(unlink(zip))
  dir <- tempfile(pattern = "datagouv-zip-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  utils::unzip(zip, exdir = dir)

  files <- list.files(dir, full.names = TRUE, recursive = TRUE)
  fmt <- vapply(files, format_from_path, character(1))
  keep <- !is.na(fmt)
  parsed <- Map(parse_resource_file, files[keep], fmt[keep])
  names(parsed) <- uniquify_names(basename(files[keep]))
  parsed
}

# Compose the stable, unique address of a parsed table as a proper URI:
#   "https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>"
#         for a single-file resource
#   "https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>/<file>"
#         for a file inside a ZIP
# The base is data.gouv's own dataset page, so the address is href-able and
# opens the right page in a browser, while the fragment carries the two stable
# platform identifiers (`dataset_id`, 24-hex; `resource_id`, a UUID) plus an
# optional ZIP member. `#` and `/` never appear in those fields, so the
# fragment is unambiguous.
compose_table_id <- function(dataset_id, resource_id, file = NULL) {
  base <- paste0("https://www.data.gouv.fr/datasets/", dataset_id)
  frag <- resource_id
  if (!is.null(file)) {
    frag <- paste(frag, file, sep = "/")
  }
  paste0(base, "#", frag)
}

# Attach a table's composed id as an attribute (the metadata address added by
# dg_pull_dataset()/dg_refetch()). Unlike a per-row column, a table attribute
# does not replicate across rows and is read back with dg_table_id().
table_attr <- function(table, dataset_id, resource_id, file = NULL) {
  attr(table, "id") <- compose_table_id(dataset_id, resource_id, file)
  table
}

# Read a table's composed id from its `id` attribute.
table_id_from_attr <- function(table) {
  attr(table, "id")
}

# Normalise a table reference — either a tibble carrying an `id` attribute (as
# returned by dg_pull_dataset()/dg_refetch()) or a bare composed id string —
# into the composed id string. Errors on anything else with a clear message.
resolve_table_id <- function(x) {
  if (is.data.frame(x)) {
    id <- attr(x, "id")
    if (!is.null(id)) {
      return(id)
    }
    stop(
      "This table carries no table id. Pull it with dg_pull_dataset() so its ",
      "stable id is attached, or pass a composed id string directly.",
      call. = FALSE
    )
  }
  if (is.character(x) && length(x) == 1) {
    return(x)
  }
  stop(
    "`x` must be a table returned by dg_pull_dataset() (with its id attached) ",
    "or a composed id string.",
    call. = FALSE
  )
}

# Split a table address into its (dataset, resource, file) parts. Returns a
# named list; `file` is NULL when absent. Errors on a malformed id.
#
# Accepts the URI form composed by compose_table_id():
#   "https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>(/<file>)"
# The fragment covers both a single resource (`#<resource_id>`) and a file
# inside a ZIP (`#<resource_id>/<file>`).
parse_table_id <- function(id) {
  if (!is.character(id) || length(id) != 1 || is.na(id)) {
    stop("Invalid table id: expected a single non-NA string.", call. = FALSE)
  }
  hex <- "[0-9a-fA-F]{24}"
  uuid <- "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
  # URI form: <base>#<resource_id>(/<file>)
  m <- regexec(
    paste0(
      "^https://www\\.data\\.gouv\\.fr/datasets/(",
      hex,
      ")#(",
      uuid,
      ")(?:/(.+))?$"
    ),
    id,
    perl = TRUE
  )
  m <- regmatches(id, m)[[1]]
  if (length(m) > 0) {
    return(list(
      dataset_id = m[[2]],
      resource_id = m[[3]],
      file = if (length(m) >= 4 && nzchar(m[[4]])) m[[4]] else NULL
    ))
  }
  stop(
    "Invalid table id '",
    id,
    "': expected the URI 'https://www.data.gouv.fr/datasets/<dataset>",
    "#<resource>(/<file>)'.",
    call. = FALSE
  )
}

# Parse a single named file out of a ZIP resource and return its data frame,
# skipping nothing else. Used by dg_refetch() to re-read exactly one table.
# `name` is a base file name within the archive.
read_one_zip_file <- function(resource, name) {
  zip <- download_resource(resource)
  on.exit(unlink(zip))
  dir <- tempfile(pattern = "datagouv-zip-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  utils::unzip(zip, exdir = dir)
  path <- file.path(dir, name)
  fmt <- format_from_path(path)
  if (is.na(fmt)) {
    stop(
      "File '",
      name,
      "' inside the ZIP is not in a supported format.",
      call. = FALSE
    )
  }
  parse_resource_file(path, fmt)
}

# Parse a resource into a tidy tibble.
#
# Converts a data frame (e.g. read with `readr`) into a `tibble::tibble()` and,
# optionally, drops all rows that contain at least one missing value.
format_tibble <- function(x, remove_na = FALSE) {
  if (!is.data.frame(x)) {
    stop("`x` must be a data frame or tibble.", call. = FALSE)
  }
  out <- tibble::as_tibble(x)
  if (remove_na) {
    # Drop any row that contains at least one missing value (tidyr::drop_na equivalent)
    out <- out[stats::complete.cases(out), ]
  }
  out
}

# Download a resource and parse it into a data frame. ZIP resources are
# unpacked first: each contained file in a supported format becomes one
# element of the returned named list.
read_resource <- function(resource) {
  fmt <- tolower(resource$format %||% "")
  if (fmt == "zip") {
    return(read_zip_resource(resource))
  }
  # Guard against formats the candidate filter should have already removed.
  if (!fmt %in% supported_formats()) {
    stop("Unsupported format: ", resource$format, call. = FALSE)
  }
  path <- download_resource(resource)
  on.exit(unlink(path))
  parse_resource_file(path, fmt)
}

# Download a resource to a temporary file and return its path.
# The request goes through `req_data_gouv()` so it benefits from the same
# timeout and retry handling as the API calls (the resources are served
# from a static CDN that can also be slow or flaky).
download_resource <- function(resource) {
  path <- tempfile(
    pattern = "datagouv-",
    fileext = paste0(".", resource$format %||% "bin")
  )
  writeBin(
    httr2::resp_body_raw(
      http_perform(req_data_gouv(httr2::request(resource$url)))
    ),
    path
  )
  path
}
