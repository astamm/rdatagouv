# datagouv 0.0.0.9000

- `dg_list_datasets()` now talks to the v2 `datasets/search` API instead of the
  v1 `datasets` endpoint. In v2, multiple `format` values are sent as repeated
  query parameters (a server-side union) in a single call, pagination follows
  the pointer-based string `next_page`, and the API returns much richer
  per-dataset metadata inline. The return tibble therefore adds new columns:
  `organization`, `license`, `quality_score`, `quality_flags`, `views`,
  `resources_downloads`, `access_type`, `frequency`, `spatial_granularity`,
  `temporal_start`, `temporal_end`, `archived` and `featured`.
- `dg_list_datasets()` gains new server-side filter arguments: `organization`
  (a 24-hex producer id — v2 does not accept a slug or name here), `geozone`,
  `access_type`, `license`, `tag`, `granularity`, `last_update` and
  `producer_type`.
- Because v2 search does **not** inline a dataset's resources, the
  resource-derived columns `n_resources`, `formats`, `has_table` and
  `has_schema` are now `NA` by default. Pass `resources = TRUE` to opt into a
  per-dataset fetch of each resources subsection (one extra request per
  dataset) so those columns are computed exactly. `schema_only` still filters
  client-side on `has_schema`, so it only selects reliably when
  `resources = TRUE`.
- New export `dg_glimpse(id, table = NULL)` surfaces the v2-inline dataset
  metadata that the v1 pull path does not expose: `quality` (score + flags),
  `metrics` (views, downloads, followers, discussions, reuses, dataservices)
  and `context` (organization, license, frequency, temporal/spatial coverage,
  access_type, archived, featured). `table = TRUE` additionally returns the
  per-resource list via the dataset's resources subsection.

- Tables pulled with `dg_pull_dataset()`/`dg_refetch()` are now addressed by a
  proper URI instead of a `::`-composed id: the `id` attribute (read with
  `dg_table_id()`) is now
  `https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>` (plus
  `/<file>` for a file inside a ZIP). The address still carries the platform's
  stable dataset/resource ids — so `dg_refetch()`/`dg_schema()` stay
  reproducible — and, as a URI, it is now href-able and opens the right dataset
  page in a browser. Legacy composed ids of the form
  `<dataset_id>::<resource_id>` / `<dataset_id>::<resource_id>::<file>` remain
  accepted by `dg_refetch()`/`dg_schema()` for backwards compatibility.
- Added opt-in live integration tests (`tests/testthat/test-live-api.R`) that
  verify a file inside a real data.gouv ZIP is addressable and re-fetchable via
  its composed URI on the live API — the one thing the mocked unit tests cannot
  prove. Skipped unless the environment variable `DATAGOUV_LIVE=1` is set; run
  with `DATAGOUV_LIVE=1 Rscript -e 'devtools::test(filter = "live")'`.
- `get_summary()` and `summarise_datasets()` are renamed to `dg_summary()` and
  `dg_summarise()` for a uniform `dg_*` API.
- `dg_download_many()` is removed; its functionality is covered by
  `dg_summarise()` (to get both the raw tables and the metrics, call
  `dg_pull_dataset()` then `dg_summarise()`).
- `dg_list_datasets()` gains a `format` argument to keep only datasets that
  have a resource in one of the requested formats (defaults to the full set of
  tabular formats). The API filters a single format per query, so the requested
  formats are queried server-side one by one and the results are combined and
  de-duplicated by dataset id. This also fixes a latent bug where the
  multi-format request was effectively honoured as `csv` only.
- The v2 discovery crawl scales its page size adaptively: `dg_list_datasets()`
  requests small, fast pages (`page_size = 100`) by default, but a large or
  infinite `n` (e.g. a full-catalog `n = Inf` crawl) automatically scales each
  page up to ~250 and clamps the final page to the remaining budget. This keeps
  individual requests well under the client timeout while cutting a full
  10,000-row crawl to ~40 requests.
- `dg_pull_dataset()`/`dg_refetch()` now prefer the lightest advertised file
  when a dataset offers the *same table* in several formats (same base file
  name, different extension, e.g. `data.csv` vs `data.xlsx`): among such
  duplicates, the resource with the smallest `filesize` is downloaded to speed
  up the pull. Resources with distinct names keep their declared order.

- Initial development version.
- `dg_list_datasets()` lists all datasets available on data.gouv.fr and returns a
  tibble with `title`, `id`, `description` and `slug`.
- `format_tibble()` converts a data frame to a tibble and can drop rows
  containing missing values.
- `get_summary()` computes key metrics (weight, number of variables, number of
  rows, missing-value proportion) for a dataset.
- `summarise_datasets()` computes summary metrics over a collection of
  datasets, disambiguating duplicate titles in the output by appending each
  dataset's id.
- `dg_pull_dataset()` downloads a dataset by its stable, unique `id` (and, as a
  fallback, by exact title) and parses it.
- `read_resource()` auto-detects the delimiter of CSV/TXT resources (comma,
  semicolon, tab, pipe, ...) and dispatches to the matching `readr` reader
  (`read_csv()`, `read_csv2()` for European files, `read_tsv()`,
  `read_delim()`), and adds support for JSON resources (array or
  newline-delimited) via `jsonlite`.
- `wrapper_datasets()` downloads several datasets by `id` and returns both the
  raw tables and the summary metrics.
- `dg_download_many()` replaces `wrapper_datasets()` (renamed); `wrapper_datasets()`
  is no longer available.
- `dg_pull_dataset()` now tags every returned table with a stable, unique `id`
  column of the form `<dataset>::<resource>` (or `<dataset>::<resource>::<file>`
  for a file inside a ZIP), built from the platform's own identifiers.
- `dg_refetch()` re-fetches a single table from its composed `id`, reproducibly
  returning the same table across calls.
- `dg_list_datasets()` now also reports `n_resources` (file count), `formats`
  (distinct file formats) and `has_table` (whether a resource can be parsed to
  a table) for each dataset.
- `summarise_datasets()` accepts a tibble returned by `dg_list_datasets()`
  (identified by its `id` column) and summarises the matching datasets.
- `dg_schema()` returns the documented column metadata (`name`, `title`,
  `description`, `type`, `example`) declared in the dataset's data schema on
  schema.data.gouv.fr, resolved from a resource's schema pointer, or `NULL`
  (with a message) when the resource carries no schema.
- `dg_pull_dataset()` now returns a single tibble by default instead of a
  one-element list, with the table's stable id stored as an `id` attribute
  rather than a per-row `.id` column; a multi-file ZIP is returned via
  `all_files = TRUE` and each file keeps its own id attribute.
- `dg_table_id()` returns the stable composed id stored as an attribute on a
  pulled or re-fetched table.
- `dg_refetch()` and `dg_schema()` now accept either a table (its `id`
  attribute is read automatically) or a composed id string.
- `dg_list_datasets()` now reports `has_schema` (whether at least one resource
  carries a pointer to a declared data schema) and gains a `schema_only`
  argument to keep only schema-documented datasets.
- The discovery catalog (`dg_list_datasets()`) is now restricted to data.gouv's
  official tabular formats (`csv`, `csv.gz`, `xls`, `xlsx`, `parquet`) so every
  listed dataset is in principle openable as a table.
- `supported_formats()` now also parses `xls` (legacy Excel) and `parquet`
  resources; `nanoparquet` is a new hard dependency.
- `get_summary()` and `summarise_datasets()` exclude the `.id` column from
  variable and missing-value metrics.
- `dg_pull_dataset()` now skips a dataset resource whose declared format cannot
  actually be parsed into a table (e.g. a `json` resource serving an API
  metadata document) and falls back to the next tabular resource, instead of
  erroring on the first candidate.
- `read_json_file()` now reports a clear, actionable error when a top-level JSON
  object is not tabular data (e.g. an API metadata document with
  variable-length fields) rather than a cryptic tibble-size error.
