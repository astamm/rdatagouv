# Changelog

## rdatagouv 0.0.0.9000

- New technical vignette, *Documentation technique du package rdatagouv*
  — a French architecture/development guide (in French) previously
  maintained as an Rbuildignore’d root document. It now ships as a real
  vignette (`vignettes/rdatagouv-howto.qmd`), is registered under
  `articles` on the pkgdown site, and gains a section on column parsing
  (`col_types`, `use_tabular_types` and the `csv-detective` profile
  seeding, and
  [`dg_problems()`](https://astamm.github.io/rdatagouv/reference/dg_problems.md)).
  Its stale API signatures and recap table were brought in line with the
  current exports. The superseded `TOPIC-SUPPORT-SKETCH.md` decision log
  was removed (its
  `topic =`/[`dg_find_topics()`](https://astamm.github.io/rdatagouv/reference/dg_find_topics.md)
  work is fully shipped).

- All package messages, warnings and errors are now emitted through
  `cli`
  ([`cli::cli_inform()`](https://cli.r-lib.org/reference/cli_abort.html),
  [`cli::cli_warn()`](https://cli.r-lib.org/reference/cli_abort.html)
  and
  [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
  respectively) instead of base R
  [`message()`](https://rdrr.io/r/base/message.html)/[`warning()`](https://rdrr.io/r/base/warning.html)/[`stop()`](https://rdrr.io/r/base/stop.html).
  Conditions get styled inline markup (column/filename/argument names,
  quoted values, function references) and carry `datagouv_*` condition
  classes, so [`tryCatch()`](https://rdrr.io/r/base/conditions.html) and
  `testthat::expect_*()` on the message text keep working while the
  output is prettier and more consistent.

- Documentation refresh. The README now leads with a five-step “find →
  judge → fetch → re-fetch → summarise” quick start rather than a dense
  gallery of every filter, keeping `organization`/`topic`/`format`
  narrowing to a brief mention and pointing readers at the vignette for
  the full tour. The vignette now exemplifies *every* exported function
  — adding a missing
  [`dg_glimpse()`](https://astamm.github.io/rdatagouv/reference/dg_glimpse.md)
  worked example in the “Judging whether a dataset is usable” section —
  and the `col_types` parsing-issues example uses a real fixture (the
  IRVE charging-points dataset) whose `date_mise_en_service`/`date_maj`
  columns genuinely reproduce the mixed-date straggler problem it
  illustrates, instead of pointing at columns that had since drifted on
  the platform.

- [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
  and
  [`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
  gain a `use_tabular_types` argument (default `TRUE`) that seeds column
  types from data.gouv’s tabular API profile
  (`tabular-api.data.gouv.fr/api/resources/<rid>/profile/`), a
  schema-independent per-column type detection computed by data.gouv’s
  own `csv-detective` detector. It is now on by default; pass `FALSE` to
  disable. The profile is resolved *per resource inside the parse loop*
  (at the leaf `read_resource()` that actually parses the addressed
  resource), so a multi-resource dataset uses each resource’s own
  profile rather than a first-candidate guess. The detected types fill
  in any column `col_types` does not pin (explicit `col_types` always
  win); the profile is best-effort — it only exists for single-file
  resources indexed by the tabular service, and a missing profile (or a
  ZIP member) silently falls back to type inference. Each column’s
  detection is also gated on its confidence `score`: a detection below
  the default threshold (`min_score = 0.5`) is left out so vroom infers
  that column instead of pinning a low-confidence type.

- When a resource carries both a tabular profile and a declared schema,
  the *profile* remains the column-typing source even when the schema is
  co-present: the pulled table’s column types come from the empirical
  csv-detective detection, while the schema keeps its separate
  documentation role via
  [`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md).
  (Schema-declared types use a looser vocabulary — e.g. `year`,
  `geopoint`, `array` — outside the `col_types` shorthand, and are often
  all-`string` or stale, so they are not used to seed vroom’s types.)

- [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
  and
  [`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
  gain a `col_types` argument to force the type of specific columns
  instead of letting vroom infer them, e.g.
  `col_types = c(date_mise_en_service = "Date")`. Values are shorthand
  strings (`"character"`, `"double"`/`"numeric"`, `"integer"`,
  `"logical"`, `"Date"`, `"datetime"`, `"skip"`, `"guess"`); unnamed
  columns keep type inference. This resolves the case of a mostly-padded
  ISO date column with a few non-padded stragglers (e.g. `2021-7-01`),
  which vroom would otherwise flag as a parsing issue: forcing `"Date"`
  turns the stragglers into `NA`.

- The noisy per-cell `vroom` parsing warnings are now suppressed by
  default during a pull, and the underlying issues are attached to the
  returned table as an `rdatagouv_problems` attribute instead. Read them
  with the new export `dg_problems(tbl)`, which returns a data frame of
  `{row, col, expected, actual}`, or `NULL` when the table parsed
  cleanly. (Previously the warning told you to call `problems()`, but
  `format_tibble()` stripped vroom’s class, so that call always failed
  on a pulled table.)

- Delimited resources (`csv`, `csv.gz`, `tsv`, `txt`) are now parsed
  with
  [`vroom::vroom()`](https://vroom.tidyverse.org/reference/vroom.html)
  instead of the individual `readr` readers
  (`read_csv`/`read_tsv`/`read_csv2`/`read_delim`). `readr` is no longer
  an import; the delimiter is still probed first by `guess_delimiter()`
  (vroom’s own guesser is comma-first and would mis-read European-style
  files with a semicolon separator and comma decimal mark), and
  semicolon files keep the comma-decimal locale (`read_csv2` behaviour).
  `vroom` reads with `altrep = FALSE` so the returned table materialises
  eagerly and does not reference the temporary file that is unlinked on
  exit.

- The `formats` column of
  [`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md)
  is now a **list-column**: each element is a character vector of the
  dataset’s distinct file formats, instead of a single comma-joined
  string. This makes per-format filtering straightforward
  (e.g. `purrr::map_lgl(formats, ~ "parquet" %in% .x)` or
  `lapply(formats, ...)`) instead of parsing a delimited string. As
  before, the column is only filled when `resources = TRUE` (it is
  `NULL` otherwise, and a dataset with no recorded format has an empty
  vector).

- `dg_find_datasets(schema_only = TRUE)` no longer silently returns an
  unfiltered catalog. Because `schema_only` selects client-side on
  `has_schema` — which needs the per-dataset resource fetch — calling it
  without `resources = TRUE` now forces `resources = TRUE` and emits an
  informative message about the extra requests, so the filter actually
  runs instead of returning every row with `has_schema = NA`.

- New export `dg_find_topics(q = NULL, n = 20, elements = FALSE)`
  queries the v2 `topics/search` endpoint and returns a tibble of
  `{id, name, slug, description, tags, featured, n_elements}` (plus
  `n_datasets`/`n_dataservices`/`n_reuses` when `elements = TRUE`) for
  the curated themes grouping datasets, reuses and dataservices. Use it
  to discover a theme and get its stable 24-hex `id`. The per-kind
  counts require one extra request per topic (an N+1 crawl), so
  `n_elements` is always the topic’s declared total while the breakdown
  defaults to `NA`.

- [`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md)
  gains a `topic` filter: pass the 24-hex id of a theme (found via
  [`dg_find_topics()`](https://astamm.github.io/rdatagouv/reference/dg_find_topics.md))
  to return only datasets grouped under that topic. Matched server-side
  as a single-valued filter, echoing how `organization`/`geozone` narrow
  the catalog. Like `tag`/`geozone`, topic ids form an open vocabulary,
  so the argument is not enumerated or validated; a human-readable topic
  name/slug is not auto-resolved (see
  [`dg_find_topics()`](https://astamm.github.io/rdatagouv/reference/dg_find_topics.md)).

- [`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md)
  now validates its closed-vocabulary filter arguments (`access_type`,
  `license`, `granularity`, `last_update`, `producer_type`) before they
  reach the server, erroring with the exhaustive list of valid options
  on an unknown value. This replaces three silent/cryptic failure modes
  of the v2 search endpoint: an invalid `producer_type` returned a
  cryptic server validation error, an invalid `license`/`granularity`/
  `access_type` silently returned zero hits, and an invalid
  `last_update` was silently ignored. The roxygen docs now enumerate the
  full option set for each closed-vocabulary filter (and document the
  territory-code format for `geozone`, whose codes are open-ended).

- `dg_list_datasets()` is renamed to
  [`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md)
  for a verb-first API that pairs with the other discovery functions.
  The old name is removed without a deprecation shim (the package has
  never been released).

- New export `dg_find_organization(q = NULL, n = 20)` queries the v2
  `organizations/search` endpoint and returns a tibble of
  `{id, name, slug, acronym, description, datasets, badges, business_number_id}`
  for matching producers. Use it to discover an organization and get its
  stable 24-hex `id`.

- `dg_find_datasets(organization =)` now accepts an organization’s
  `name` or `slug` as well as a 24-hex id. Names and slugs are resolved
  to their id via the organizations endpoint using an exact match; if
  zero or several organizations match, the call errors and lists the
  candidates so you can disambiguate. A bare 24-hex id is passed
  straight through without a lookup.

- `dg_list_datasets()` now talks to the v2 `datasets/search` API instead
  of the v1 `datasets` endpoint. In v2, multiple `format` values are
  sent as repeated query parameters (a server-side union) in a single
  call, pagination follows the pointer-based string `next_page`, and the
  API returns much richer per-dataset metadata inline. The return tibble
  therefore adds new columns: `organization`, `license`,
  `quality_score`, `quality_flags`, `views`, `resources_downloads`,
  `access_type`, `frequency`, `spatial_granularity`, `temporal_start`,
  `temporal_end`, `archived` and `featured`.

- `dg_list_datasets()` gains new server-side filter arguments:
  `organization` (a 24-hex producer id — v2 does not accept a slug or
  name here), `geozone`, `access_type`, `license`, `tag`, `granularity`,
  `last_update` and `producer_type`.

- Because v2 search does **not** inline a dataset’s resources, the
  resource-derived columns `n_resources`, `formats`, `has_table` and
  `has_schema` are now `NA` by default. Pass `resources = TRUE` to opt
  into a per-dataset fetch of each resources subsection (one extra
  request per dataset) so those columns are computed exactly.
  `schema_only` still filters client-side on `has_schema`, so it only
  selects reliably when `resources = TRUE`.

- New export `dg_glimpse(id, table = NULL)` surfaces the v2-inline
  dataset metadata that the v1 pull path does not expose: `quality`
  (score + flags), `metrics` (views, downloads, followers, discussions,
  reuses, dataservices) and `context` (organization, license, frequency,
  temporal/spatial coverage, access_type, archived, featured).
  `table = TRUE` additionally returns the per-resource list via the
  dataset’s resources subsection.

- Tables pulled with
  [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)/[`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
  are now addressed by a proper URI instead of a `::`-composed id: the
  `id` attribute (read with
  [`dg_table_id()`](https://astamm.github.io/rdatagouv/reference/dg_table_id.md))
  is now `https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>`
  (plus `/<file>` for a file inside a ZIP). The address still carries
  the platform’s stable dataset/resource ids — so
  [`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)/[`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md)
  stay reproducible — and, as a URI, it is now href-able and opens the
  right dataset page in a browser. Legacy composed ids of the form
  `<dataset_id>::<resource_id>` / `<dataset_id>::<resource_id>::<file>`
  remain accepted by
  [`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)/[`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md)
  for backwards compatibility.

- Added opt-in live integration tests (`tests/testthat/test-live-api.R`)
  that verify a file inside a real data.gouv ZIP is addressable and
  re-fetchable via its composed URI on the live API — the one thing the
  mocked unit tests cannot prove. Skipped unless the environment
  variable `DATAGOUV_LIVE=1` is set; run with
  `DATAGOUV_LIVE=1 Rscript -e 'devtools::test(filter = "live")'`.

- `get_summary()` and `summarise_datasets()` are renamed to
  [`dg_summary()`](https://astamm.github.io/rdatagouv/reference/dg_summary.md)
  and
  [`dg_summarise()`](https://astamm.github.io/rdatagouv/reference/dg_summarise.md)
  for a uniform `dg_*` API.

- `dg_download_many()` is removed; its functionality is covered by
  [`dg_summarise()`](https://astamm.github.io/rdatagouv/reference/dg_summarise.md)
  (to get both the raw tables and the metrics, call
  [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
  then
  [`dg_summarise()`](https://astamm.github.io/rdatagouv/reference/dg_summarise.md)).

- `dg_list_datasets()` gains a `format` argument to keep only datasets
  that have a resource in one of the requested formats (defaults to the
  full set of tabular formats). The API filters a single format per
  query, so the requested formats are queried server-side one by one and
  the results are combined and de-duplicated by dataset id. This also
  fixes a latent bug where the multi-format request was effectively
  honoured as `csv` only.

- The v2 discovery crawl scales its page size adaptively:
  `dg_list_datasets()` requests small, fast pages (`page_size = 100`) by
  default, but a large or infinite `n` (e.g. a full-catalog `n = Inf`
  crawl) automatically scales each page up to ~250 and clamps the final
  page to the remaining budget. This keeps individual requests well
  under the client timeout while cutting a full 10,000-row crawl to ~40
  requests.

- [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)/[`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
  now prefer the lightest advertised file when a dataset offers the
  *same table* in several formats (same base file name, different
  extension, e.g. `data.csv` vs `data.xlsx`): among such duplicates, the
  resource with the smallest `filesize` is downloaded to speed up the
  pull. Resources with distinct names keep their declared order.

- Initial development version.

- `dg_list_datasets()` lists all datasets available on data.gouv.fr and
  returns a tibble with `title`, `id`, `description` and `slug`.

- `format_tibble()` converts a data frame to a tibble and can drop rows
  containing missing values.

- `get_summary()` computes key metrics (weight, number of variables,
  number of rows, missing-value proportion) for a dataset.

- `summarise_datasets()` computes summary metrics over a collection of
  datasets, disambiguating duplicate titles in the output by appending
  each dataset’s id.

- [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
  downloads a dataset by its stable, unique `id` (and, as a fallback, by
  exact title) and parses it.

- `read_resource()` auto-detects the delimiter of CSV/TXT resources
  (comma, semicolon, tab, pipe, …) and dispatches to the matching
  `readr` reader (`read_csv()`, `read_csv2()` for European files,
  `read_tsv()`, `read_delim()`), and adds support for JSON resources
  (array or newline-delimited) via `jsonlite`.

- `wrapper_datasets()` downloads several datasets by `id` and returns
  both the raw tables and the summary metrics.

- `dg_download_many()` replaces `wrapper_datasets()` (renamed);
  `wrapper_datasets()` is no longer available.

- [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
  now tags every returned table with a stable, unique `id` column of the
  form `<dataset>::<resource>` (or `<dataset>::<resource>::<file>` for a
  file inside a ZIP), built from the platform’s own identifiers.

- [`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
  re-fetches a single table from its composed `id`, reproducibly
  returning the same table across calls.

- `dg_list_datasets()` now also reports `n_resources` (file count),
  `formats` (distinct file formats) and `has_table` (whether a resource
  can be parsed to a table) for each dataset.

- `summarise_datasets()` accepts a tibble returned by
  `dg_list_datasets()` (identified by its `id` column) and summarises
  the matching datasets.

- [`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md)
  returns the documented column metadata (`name`, `title`,
  `description`, `type`, `example`) declared in the dataset’s data
  schema on schema.data.gouv.fr, resolved from a resource’s schema
  pointer, or `NULL` (with a message) when the resource carries no
  schema.

- [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
  now returns a single tibble by default instead of a one-element list,
  with the table’s stable id stored as an `id` attribute rather than a
  per-row `.id` column; a multi-file ZIP is returned via
  `all_files = TRUE` and each file keeps its own id attribute.

- [`dg_table_id()`](https://astamm.github.io/rdatagouv/reference/dg_table_id.md)
  returns the stable composed id stored as an attribute on a pulled or
  re-fetched table.

- [`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
  and
  [`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md)
  now accept either a table (its `id` attribute is read automatically)
  or a composed id string.

- `dg_list_datasets()` now reports `has_schema` (whether at least one
  resource carries a pointer to a declared data schema) and gains a
  `schema_only` argument to keep only schema-documented datasets.

- The discovery catalog (`dg_list_datasets()`) is now restricted to
  data.gouv’s official tabular formats (`csv`, `csv.gz`, `xls`, `xlsx`,
  `parquet`) so every listed dataset is in principle openable as a
  table.

- `supported_formats()` now also parses `xls` (legacy Excel) and
  `parquet` resources; `nanoparquet` is a new hard dependency.

- `get_summary()` and `summarise_datasets()` exclude the `.id` column
  from variable and missing-value metrics.

- [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
  now skips a dataset resource whose declared format cannot actually be
  parsed into a table (e.g. a `json` resource serving an API metadata
  document) and falls back to the next tabular resource, instead of
  erroring on the first candidate.

- `read_json_file()` now reports a clear, actionable error when a
  top-level JSON object is not tabular data (e.g. an API metadata
  document with variable-length fields) rather than a cryptic
  tibble-size error.
