# AGENTS.md

Guidance for AI agents (and returning humans) working on the `datagouv` R
package. Establishes the package's intent, architecture and conventions so
future sessions can pick up context quickly.

## Purpose

`datagouv` is an R client for the public API of data.gouv.fr, the French
government's open-data platform. Its **primary intent** (the reframed goal that
drives the design):

> Let students/data scientists find a dataset matching their interests, judge
> whether it is usable, fetch it, and re-fetch the exact same table
> reproducibly.

Four workflow steps, each mapping to exported functions:

| Step | Function |
|------|----------|
| Find / search the catalog | `dg_list_datasets()` |
| Judge documented columns | `dg_schema()` |
| Download tabular resources | `dg_pull_dataset()` |
| Summarise table contents | `dg_summary()`, `dg_summarise()` |
| Re-fetch a table reproducibly | `dg_refetch()` |

The design rationale and full history live in `DESIGN-discovery.md` (top-level,
ignored by R CMD build). Treat that file as a proposal/decision log: its
`*(implemented)*` phasing markers and change map reflect status, but the
"Core design concepts", [Public API](#public-api-7-exports) and architecture
sections of *this* AGENTS.md are the source of truth for how the package
currently behaves; exploratory/optional and superseded-alternative sections in
the design doc are historical, not normative. The README and the vignette
`vignettes/datagouv.qmd` document usage for end users.

## Public API (7 exports)

- `dg_list_datasets(q = NULL, n = 1000, format = catalog_formats(),
  schema_only = FALSE)` -> tibble with columns `title, id, description, slug,
  n_resources, formats, has_table, has_schema`. `q` is server-side full-text
  search; `n = Inf` fetches the whole catalog; `format` narrows to datasets
  holding a resource in one of the given formats (queried server-side one
  format at a time, then unioned and de-duplicated by id — the API honors only
  a single `format` value per query, so passing several is *not* an OR on the
  server); `schema_only = TRUE` keeps only datasets declaring a schema.
  `fetch_all_datasets()`/`fetch_datasets_page()` page at `page_size = 1000` by
  default (up from 100).
- `dg_pull_dataset(id, all_files = FALSE, remove_na = FALSE)` -> a **single
  tibble** (the first parseable resource; a ZIP yields its first parseable
  file). `all_files = TRUE` returns a named list (one element per ZIP file).
  Every table carries its composed id as an `id` **attribute** (not a column),
  set by `table_attr()` and read by `dg_table_id()`/`table_id_from_attr()`.
- `dg_refetch(x, remove_na = FALSE)` -> a **single tibble** re-fetched from a
  composed id; `x` may be a table (its `id` attribute is read) or a bare id
  string.
- `dg_schema(x)` -> tibble (`name, title, description, type, example`) of a
  table's documented columns, with `schema_title`/`schema_name` attributes;
  `NULL` + message when the resource declares no schema; errors if the resource
  is not found. `x` may be a table or a composed id string.
- `dg_table_id(x)` -> the composed id string of a pulled/re-fetched table, or
  `NULL` for an ordinary data frame.
- `dg_summary(x, name = NULL)` -> one-row metrics tibble: `dataset, size_kb,
  n_vars, n_numeric, n_non_numeric, n_rows, prop_missing`.
- `dg_summarise(datasets = NULL, n = 100)` -> metrics over many tables.
  Accepts a named list of tibbles, a nested list (ZIP), a `dg_list_datasets()`
  tibble, a character vector of ids, or `NULL` (first `n` of the catalog).

Note: `format_tibble()` is **not exported** (used internally and in tests).

## Source layout

- `R/utils.R` — internal HTTP + parsing helpers: `req_data_gouv()` (user-agent,
  30s timeout, retry on 429/5xx), `fetch_datasets_page`, `fetch_all_datasets`,
  `fetch_dataset`, `find_dataset`, `supported_formats()`,
  `catalog_formats()`, `resource_has_schema()`,
  `read_first_parseable_resource`, `prefer_lightest_file`,
  `guess_delimiter`, `read_json_file`,
  `parse_resource_file`, `read_zip_resource`, `read_one_zip_file`,
  `read_resource`, `download_resource`, `format_tibble`, `compose_table_id` /
  `parse_table_id`, `table_attr` / `table_id_from_attr` / `resolve_table_id`,
  `%||%`, `uniquify_names`, `is_dataset_id`.
- `R/dg-list-datasets.R` — `dg_list_datasets()`.
- `R/dg-pull-dataset.R` — `dg_pull_dataset()`.
- `R/dg-table-id.R` — `dg_table_id()`.
- `R/dg-refetch.R` — `dg_refetch()` + `parse_table_id` validation.
- `R/dg-schema.R` — `dg_schema()` + `field_attr()` + `resolve_schema_url()`.
- `R/dg-summary.R` — `dg_summary()` (single-table metrics).
- `R/dg-summarise.R` — `dg_summarise()` + internal `flatten_tables`.
- `R/datagouv-package.R` — package-level `.Rd`.

## Core design concepts

**Composed table id (URI form).** Each parsed table's address is a URI —
`https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>` (single file) or
`https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>/<file>` (a file
inside a ZIP), built by `compose_table_id()`. `dataset_id` is a 24-hex ObjectId,
`resource_id` a UUID, `<file>` a base name; `#`/`/` never appear in those fields.
Built from the platform's own identifiers (and href-able to the dataset page),
so it is stable and re-fetchable, unlike human-readable titles. Stored as the
`id` **attribute** of each table by `dg_pull_dataset()`/`dg_refetch()` (not a
column); `dg_table_id()` and `dg_refetch()`/`dg_schema()` consume it. Parsed
by `parse_table_id()` (URI form only — the legacy `<dataset>::<resource>(::<file>)`
delimited form was removed; the URI fragment `#<resource_id>(/<file>)` covers
all the single-file and ZIP-member cases the legacy form did). Set *after*
parsing so low-level readers stay untouched.

**Format handling — two lists, deliberately different.**
- `catalog_formats()` = `c("csv", "csv.gz", "xls", "xlsx", "parquet")` — the
  official tabular formats data.gouv.fr indexes. The **discovery catalog**
  (`dg_list_datasets()`) is restricted to these so every listed dataset is in
  principle openable as a table. The API honors a single `format` value per
  query, so `fetch_all_datasets()` queries each requested format separately and
  unions/deduplicates by dataset id.
- `supported_formats()` = `c("zip", "csv", "csv.gz", "xls", "xlsx", "parquet",
  "tsv", "txt", "json")` — everything a direct pull can parse. JSON/TSV/TXT are
  intentionally NOT in the catalog (not guaranteed tabular) but remain
  parseable when addressed directly.

**Lightest-file selection.** When a dataset offers the *same table* in several
formats (same base file name, different extension), `read_first_parseable_resource()`
reduces the candidates to the one with the smallest advertised `filesize`
(`prefer_lightest_file()`), so `dg_pull_dataset()`/`dg_refetch()` download the
lighter copy. Resources with distinct names keep their declared order.

**Schema resolution.** data.gouv attaches a schema only as a *pointer*
(`resource$schema = {name, url, version}`). `dg_schema()` resolves the pointer —
the `url` directly, or the `name` via `resolve_schema_url()` against
`schema.data.gouv.fr` — to a Table Schema document and returns its `fields`.
Real per-column descriptions live here, not in the main API (coverage surveyed:
~36.9% of datasets tabular, ~5.1% carry a schema pointer, ~4.5% both). Schemas
are inconsistent: some omit per-field `title` or `description`; `field_attr()`
coerces absent/empty values to `NA` (jsonlite turns an empty `description=NULL`
into `{}`, i.e. a zero-length list, not `NULL` — handle both).

**Metrics and the id attribute.** Because the composed id is a table
*attribute*, not a column, `dg_summary()`/`dg_summarise()` need no
special exclusion — it never inflates `n_vars`/`n_numeric`/`n_non_numeric`/
`prop_missing`.

## Architecture / division of labour

Main API (`www.data.gouv.fr/api/1`) is the **backbone**: catalog keyword search,
discovery metadata, and raw file downloads. The tabular API
(`tabular-api.data.gouv.fr`) is a **supplement** but is NOT used by the current
implementation: `dg_schema()` pulls documented fields from
`schema.data.gouv.fr` instead of the tabular API `/profile/` endpoint that an
early design sketch mentioned. `dg_pull_dataset()` downloads raw files itself to
preserve full format/coverage (unindexed resources 404 on the tabular service).

## Conventions & gotchas

- **Format with `air`.** R code is formatted with the `air` formatter.
  **Systematically run `air format .` at the root of the package at the end of
  every task that involves changes to any R files** (source under `R/`, tests,
  or any other `.R` file). Do this before committing so all code stays
  consistently formatted.
- Source files use **hyphens**, not underscores (`dg-list-datasets.R`, not
  `dg_list_datasets.R`).
- All HTTP goes through `req_data_gouv()` + `http_perform()` (consistent
  user-agent, timeouts, retries).
- Tests: testthat edition 3, files in `tests/testthat/`
  (`test-dg-*.R`, `test-dg-summary.R`, `test-dg-summarise.R`, `test-utils.R`);
  mocks in `helper-data.R` (`mock_dataset`, `mock_resource`, `mock_csv_data`);
  snapshots under `_snaps/`. Run `devtools::test()`.
- **Opt-in live tests** (`test-live-api.R`): verify URL addressing against the
  real data.gouv API — the one thing mocks cannot prove. Skipped unless
  `DATAGOUV_LIVE=1`; run with
  `DATAGOUV_LIVE=1 Rscript -e 'devtools::test(filter = "live")'`. The live
  connectivity probe targets data.gouv itself, *not* testthat's default
  `skip_if_offline()` (which probes `captive.apple.com` and can be unreachable
  even when data.gouv works). Fixtures: dataset
  `6a6be5976a05df136d48fb7a` (Caen GTFS), ZIP resource
  `a5a8f046-e282-4010-91c5-82bc1f70ff73`, member `stops.txt`.
- **Examples in roxygen**: use `@examples` for network-free code (e.g.
  `dg_summary`, and the in-memory branch of `dg_summarise`) and
  `@examplesIf interactive()` for anything that hits the live API (a live call
  in `@examples` breaks `R CMD check`).

## Documentation / build

- **README is Quarto and README.md is always generated.** Make all content
  changes in `README.qmd`, never in `README.md` directly. Whenever README.md
  needs updating, regenerate it from `README.qmd` with
  `devtools::build_readme()` (which renders with `format: gfm`) and commit
  both files together. Do not hand-edit README.md — edits there are lost on the
  next regeneration and make it drift from the source. This applies
  systematically to any change touching the README.
- One Quarto vignette: `vignettes/datagouv.qmd`. It uses a knitr chunk hook so
  live-API chunks (marked `#| live: true`) run only interactively and are
  skipped during `R CMD check`. DESCRIPTION needs `VignetteBuilder: quarto`,
  `Config/Quarto/version`, and `knitr`/`quarto` in Suggests.
- `_pkgdown.yml` lists all 7 exports in the reference sections and registers
  the vignette under `articles`.
- Regenerate docs with `devtools::document()`; verify with `devtools::test()`
  and `devtools::check()`.
