# Design proposal — discovery-first refresh

Reframed primary goal: *let students/data scientists find a dataset matching
their interests, judge whether it is usable, fetch it, and re-fetch the exact
same table reproducibly.*

Current public API: `dg_list_datasets(q, n, format, schema_only, organization,
geozone, access_type, license, tag, granularity, last_update, producer_type,
resources)`, `dg_pull_dataset(id, all_files, remove_na)`,
`dg_refetch(x, remove_na)`, `dg_table_id(x)`, `dg_schema(x)`,
`dg_glimpse(id, table)`, `dg_summary(x, name)`,
`dg_summarise(datasets, n)`. (All functions share the `dg_*` prefix;
`dg_download_many()` was removed — its role is covered by
`dg_pull_dataset()` + `dg_summarise()`.)

> **2026-08 v2 switch:** `dg_list_datasets()` now queries the v2
> `datasets/search` API (pointer-based string `next_page` pagination, rich
> inline metadata, multiple `format` values as repeated params). v2 does not
> inline a dataset's resources, so `n_resources`/`formats`/`has_table`/
> `has_schema` are `NA` unless `resources = TRUE` (N+1 per-dataset fetch of the
> resources subsection). `dg_glimpse()` exposes v2-only dataset metadata.
> Pull/refetch/schema/summary remain on v1. See AGENTS.md for the authoritative
> description.
>
> **Implemented (2026-08): filter-argument validation.** The closed-vocabulary
> server-side filters of `dg_find_datasets()` (`access_type`, `license`,
> `granularity`, `last_update`, `producer_type`) are now validated client-side
> by `validate_filter_args()`, which errors with the exhaustive list of valid
> options on an unknown value (replacing a cryptic server error for
> `producer_type`, silent zero hits for `license`/`granularity`/`access_type`,
> and a silently-ignored filter for `last_update`). `geozone` (an open-ended
> territory code, format documented only) and `tag` (open vocabulary) are not
> enumerated or validated. The exhaustive option sets live in the
> `dg_*_values` constants in `R/dg-find-datasets.R` and are mirrored in the
> roxygen docs.
>
> **Implemented (2026-08): `col_types` + parsing-problem surfacing.**
> `dg_pull_dataset()`/`dg_refetch()` gain a `col_types` argument (named vector
> of shorthand strings, e.g. `c(date_mise_en_service = "Date")`, translated to
> a vroom cols() spec by internal `col_types_to_spec()` — no readr dependency)
> to force specific column types instead of vroom's inference. The noisy
> per-cell vroom parsing warnings are muffled by default via
> `withCallingHandlers`, and the underlying issues are captured with
> `vroom::problems()` and attached to the returned table as an
> `rdatagouv_problems` attribute (a plain data frame — the temp-file path is
> stripped and, unlike a vroom class, it survives `tibble::as_tibble()` in
> `format_tibble()`), read with the new export `dg_problems(x)`. Root cause
> that motivated this: the vignette's dynamic-pull live chunks (e.g. the IRVE
> dataset) hit mostly-padded ISO date columns with a few non-padded stragglers
> (`2021-7-01`), which vroom flags and warns about per cell; the warning was a
> dead-end because `as_tibble()` strips the vroom class so `vroom::problems()`
> failed on the returned table. See AGENTS.md.
>
> **Implemented (2026-08): tabular-profile-backed column typing
> (`use_tabular_types`, default `TRUE`).** `dg_pull_dataset()`/`dg_refetch()`
> gain a `use_tabular_types` argument (default `TRUE`) that seeds column types
> from data.gouv's tabular service per-resource profile
> (`tabular-api.data.gouv.fr/api/resources/<rid>/profile/`); the detected types
> are used as vroom's `col_types` for any column `col_types` does not already
> pin (explicit `col_types` always win on collision). Internal helpers in
> `R/utils.R`: `python_type_to_col()` (csv-detective `python_type` →
> shorthand: `string`→character, `int`→integer, `float`→double, `bool`→logical,
> `date`→Date, `datetime`/`timestamp`/`time`→datetime, else character);
> `tabular_profile(rid)` (HTTP fetch via `req_data_gouv()`/`http_perform()`);
> `tabular_profile_col_types(profile)` (named shorthand vector, `NULL` when
> empty); `tabular_types_for_resource(resource, use_tabular_types)` (no-op
> unless opted in; skips ZIP; `tryCatch` 404/network → NULL); and
> `merge_col_types(col_types, tabular)`.
>
> **Resolution moved into the parse loop.** Unlike the prototype (which resolved
> the first candidate's profile *up front* and merged, guessing which resource
> `dg_pull_dataset()` would parse), the final design resolves the profile at the
> **leaf that actually parses the resource**: `read_resource()` now calls
> `tabular_types_for_resource(resource, use_tabular_types)` +
> `merge_col_types()` for its own non-ZIP resource before parsing, and
> `read_first_parseable_resource()` forwards `use_tabular_types` into its loop.
> So a multi-resource dataset uses **each resource's actual profile**, not a
> first-candidate guess — the resource that parses supplies its own types. The
> prototype-only helper `first_tabular_candidate()` was **removed** (it existed
> solely to support the up-front-guess path).
>
> **Open caveats.** (1) The profile only exists for **single-file resources
> indexed by the tabular service** — ZIP members (`read_one_zip_file`,
> `read_zip_resource`) and oversized/unindexed files have no rid-scoped profile
> and fall back to type inference (the `use_tabular_types` arg is a no-op there).
> (2) The profile's per-column confidence `score` is thresholded: a

> detected type whose `score` is below the default `min_score = 0.5` is left
> out of the `col_types` map so vroom infers that column instead of pinning the
> low-confidence type (a missing score passes through). (3) `tabular_profile()`
> is best-effort: a 404 or network failure silently degrades to inference.
>
> **Schema vs profile — why the profile stays the column-typing source when a
> schema is co-present.** A resource may carry both a tabular profile (empirical)
> and a declared schema (`resource$schema` pointer resolved via `dg_schema()`).
> These answer different questions — "what type are these bytes" vs "what does
> the producer say this column means" — and only the profile is usable as a
> vroom `col_types` seed. Survey of 20 resolvable schemas / 386 fields on
> `schema.data.gouv.fr`: producer-declared `type` values are
> `string` (252), `integer` (38), `date` (36), `boolean` (23), `number` (21),
> `array` (12), `year` (2), `datetime` (1), `geopoint` (1). Several are outside
> the csv-detective/`col_types` vocabulary (`year`, `geopoint`, `array`; the
> `integer`/`number` split has no csv-detective counterpart), most schemas are
> all-`string` or stale, and only ~5% of datasets carry a resolvable pointer
> (many such pointers are empty: `name`/`url` `NULL`). The profile, by contrast,
> is computed from the real file bytes with a per-column confidence `score`
> (verified on the live Citeair fixture: `o3/no2/pm10/ninsee→integer`,
> `date→Date`, scores 1.0–1.5), so it matches what vroom actually reads. Hence:
> prefer the profile for typing when available; the schema keeps its distinct
> documentation role via `dg_schema()`; `col_types`/`use_tabular_types` already
> provides the opt-out knob when a profile's per-file HTTP request is unwanted.

## Target flow

```mermaid
flowchart LR
    A["dg_list_datasets(q)"] -->|"formats / n_resources / has_table / has_schema"| B{"pick candidate"}
    B --> C["dg_pull_dataset(id)"]
    C --> C2["single tibble with `id` attribute"]
    C2 --> D["dg_schema( tbl )"]
    D --> D2["documented columns (or NULL)"]
    C2 --> E["dg_summarise( tbl )"]
    E --> F["metrics tibble"]
    C2 -. "stable id (attribute)" .-> G["dg_refetch(tbl) / dg_refetch(id)"]
    G --> H["same exact table"]
```

---

## Baseline (agreed): stable per-table ID + re-fetch

### 1.1 Composed table id encoding (URI form)

Each parsed table gets a stable, parseable, globally unique address — a URI:

- Single-file resource:
  `https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>`
- File inside a multi-file ZIP:
  `https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>/<file>`

`dataset_id` is a 24-hex ObjectId; `resource_id` is a UUID; `file` is the base
name. The base is data.gouv's own dataset page, so the address is href-able and
opens the right page in a browser, while the fragment carries the two stable
platform identifiers (`#` and `/` never appear in those fields, so the fragment
is unambiguous). This is the platform's own identity, so it is stable and
re-fetchable, unlike filenames. *(An earlier design used a `<dataset_id>::
<resource_id>(::<file>)` delimiter form; the implementation composes URIs, and
the legacy `::` form was subsequently removed — the URI fragment
`#<resource_id>(/<file>)` already covers all the single-file and ZIP-member
cases the legacy form did.)*

### 1.2 Store the ID as a table attribute (`dg_pull_dataset`)

Each tibble returned by `dg_pull_dataset()` carries its composed ID as an `id`
**attribute** (added by the internal `table_attr()`), *not* a per-row column.
Injected in `dg_pull_dataset()` *after* `read_resource()`/`format_tibble()`, so
the low-level parsers stay untouched.

- Single resource: the returned table gets the URI for `dataset$id` +
  `resource$id` (`compose_table_id(dataset$id, resource$id)`).
- Multi-file ZIP: by default the first parseable file is returned as a single
  tibble (`compose_table_id(dataset$id, resource$id, <file>)`);
  `all_files = TRUE` returns one tibble per parseable file, each with its own
  URI.

The new exported getter `dg_table_id(x)` reads the attribute and returns `NULL`
for an ordinary data frame. Because the id is an attribute, not a column, it
**cannot** inflate `n_vars`/`n_numeric`/`n_non_numeric`/`prop_missing` in
`dg_summary()` — no exclusion hack is needed (the old `.id` column design
required one).

**Attribute survival.** On the tibbles this package returns, the `id` attribute
survives row/column verbs (`dplyr::select`, `filter`, `mutate`, `slice`,
`arrange`, `rename`, `distinct`, `head()`, base `[`) because `[.tbl_df` keeps
extra attributes. It is dropped only by verbs that build a structurally
different table (`pivot_longer`, `nest`, `summarise`) — the intended behaviour,
since those objects are no longer the same logical table. After a drop,
`dg_table_id()` returns `NULL` and `dg_refetch()`/`dg_schema()` raise a clear
"carries no table id" error.

### 1.3 `dg_refetch(x, remove_na = FALSE)` — new export

```r
dg_refetch(x, remove_na = FALSE)
```

Re-fetch the exact table addressed by a table id (URI) and return **one
tibble** (the id addresses a single table, not a multi-file list). `x` may be a
table returned by `dg_pull_dataset()`/`dg_refetch()` (its `id` attribute is read
by `resolve_table_id()`) or a bare id string — the canonical URI.

Steps:
1. `resolve_table_id(x)` → table id string (the URI).
2. `parse_table_id(id)` → `dataset_id` (+ optional `resource_id` + `file`).
3. `fetch_dataset(dataset_id)`.
4. Locate the resource by `resource_id`; error if absent.
5. Read it; if a `file` segment is present, unpack the ZIP and parse **only
   that file** (`read_one_zip_file(zip, file)`); otherwise
   `read_resource(resource)`.
6. `format_tibble(..., remove_na)`, re-attach the `id` attribute, and return a
   single tibble.

Validation: `resolve_table_id()` errors on anything that is neither a table with
an `id` attribute nor a bare id string; `parse_table_id()` rejects malformed ids
(wrong segment count / non-hex dataset id) with a clear message.

---

## Discovery improvement 1: usable-at-a-glance search

`dg_list_datasets()` currently keeps only title/id/description/slug and
**discards `resources`**, so students can't tell whether a hit holds a real
table. Fix: keep the `resources` metadata and derive a compact availability
summary.

New columns on the returned tibble (resource-derived):

- `n_resources` — number of resources (integer; `0` when none).
- `formats` — comma-joined, de-duplicated, uppercase formats of the dataset's
  resources, e.g. `"CSV, ZIP"`, or `"—"` when none. (Reuse `supported_formats()`.)
- `has_table` — logical: `TRUE` if any resource is directly parseable (non-ZIP
  supported format). A ZIP is a *maybe*, so it is shown under `formats` but does
  not by itself set `has_table`.
- `has_schema` — logical: `TRUE` if at least one resource carries a pointer to a
  declared data schema.

> **Current behavior note (v2):** v2 search no longer inlines a dataset's
> resources, so these four derived columns are computed only when the caller
> passes `resources = TRUE` (an N+1 fetch of each dataset's resources
> subsection); otherwise they are `NA`. `schema_only` filters client-side on
> `has_schema`, so it only selects reliably with `resources = TRUE`. To remove
> the silent-no-op footgun (previously `schema_only = TRUE` with the default
> `resources = FALSE` returned the unfiltered catalog with `has_schema = NA`),
> `schema_only = TRUE` now forces `resources = TRUE` and emits an informative
> message about the extra requests. The v2
> migration also added the inline metadata columns and server-side filters
> described in the note to the first "Discovery improvement 1" section above.

Adding these makes `dg_list_datasets(q = "vélo", n = 20)` immediately answer
"which of these can I actually open?" before spending a download.

**Lightest-file preference (pull side).** When a dataset offers the *same table*
in several formats (same base file name, different extension), the pull path
(`read_first_parseable_resource()`) reduces those candidates to the one with the
smallest advertised `filesize` (`prefer_lightest_file()`), so `dg_pull_dataset()`/
`dg_refetch()` download the lighter copy — e.g. a `data.csv` rather than a
heavier `data.xlsx` twin. Resources with distinct names keep their declared
order, so distinct tables are never silently swapped.

Note (post-v2 migration): the discovery catalog now runs on the v2
`datasets/search` API, which accepts **multiple formats as repeated query
parameters** in a single call (`format=csv&format=parquet`, a server-side
union) and pages via the pointer-based string `next_page`. Because v2 search
does not inline a dataset's resources, the resource-derived columns
(`n_resources`, `formats`, `has_table`, `has_schema`) are `NA` unless the caller
passes `resources = TRUE`, which opts into a per-dataset fetch of the resources
subsection (one extra request per dataset) so those columns are computed
exactly. The catalog additionally surfaces v2-inline columns (`organization`,
`license`, `quality_score`, `quality_flags`, `views`, `resources_downloads`,
`access_type`, `frequency`, `spatial_granularity`, `temporal_start`/`end`,
`archived`, `featured`) and new server-side filters (`geozone`, `license`,
`tag`, `granularity`, `last_update`, `access_type`, `producer_type`, and
`organization` — matched by 24-hex id only).

## Discovery improvement 2: summarise a search result set

Close the preview loop so students can see rows/variables/missingness across
all matching datasets.

**`dg_summarise()` gains an accepted input:** a data-frame returned by
`dg_list_datasets()` (recognized by its `id` column, which is already present).
Then `dg_summarise(dg_list_datasets(q = "vélo"))` pulls and summarizes
every hit in one call. Character-vector and named-list inputs keep working.

This complements (rather than replaces) the existing `NULL`/default behaviour.

---

## Optional / low priority

- **`dg_pull_dataset()` accepting a search term** — convenience alternative to
  `dg_list_datasets(q) |> ...`; only if we want the pull to own search.

---

## Main API vs tabular API: division of labour

Answering "is the main API even useful if the tabular API also serves the
data?": **yes — the main API is the backbone; the tabular API is a
variable-metadata supplement.** They are not substitutes.

| Concern | Main API (`www.data.gouv.fr/api/1`) | Tabular API (`tabular-api.data.gouv.fr`) |
|---------|-------------------------------------|------------------------------------------|
| **Keyword search over the catalog** | ✅ `dg_list_datasets(q)` server-side search | ❌ keyed only by resource UUID; no catalog search |
| **Discovery metadata** (title, org, license, frequency, temporal/spatial, description, formats, sizes) | ✅ | ❌ only `dataset_id` link + table profile |
| **Per-column info** (types, formats, stats) | ❌ absent from payloads | ✅ `/resources/{rid}/profile/` + `/swagger/` |
| **Serving the table** | raw file URLs (`static.data.gouv.fr`) | ✅ `/resources/{rid}/data(.csv|.json)/` with filter/paginate/sort |
| **Coverage** | every resource on the platform | only resources indexed by the tabular service (unindexed → **404**) |
| **Non-CSV support** | ✅ own parsing (TSV, TXT, XLSX, JSON, ZIP) | CSV-oriented pipeline |

Implications for this package:

- `dg_list_datasets(q)` remains irreplaceable: the tabular API has no keyword
  search, and discovery metadata (is this dataset about my interest?) comes
  only from the main API. The educational core rests on the main API.
- The pull path (`read_resource`) keeps downloading raw files itself. That
  preserves full format/coverage (xlsx, json, zip; resources the tabular
  service hasn't indexed), which the tabular API cannot guarantee.
- The tabular API's unique value is **variable metadata at pull time**, which
  the main API lacks. The package uses it in two distinct ways: documented
  per-column descriptions come from the producer's schema documents on
  schema.data.gouv.fr (see below, `dg_schema()`), while the profile-backed
  column **types** come from the tabular service's `/resources/{rid}/profile/`
  endpoint (see `use_tabular_types` above) — the pull keeps downloading and
  parsing the raw file itself, only *seeding* vroom's col_types from the
  profile.
- Keying lines up with the ID design: the tabular API is addressed by
  `resource$id` (a UUID), and its profile carries `dataset_id`, so a composed
  table id maps straight onto the `dataset_id`/`resource_id`/`file` triple
  encoded in the id URI.

---

## New phase: variable/profile pull (via schema.data.gouv.fr)

`dg_schema(x)` — documented column metadata for a single table address.

- Input: a table returned by `dg_pull_dataset()`/`dg_refetch()` (its `id`
  attribute is read via `resolve_table_id()`), or a bare table id string (the
  URI).
- Implementation: data.gouv attaches a schema only as a *pointer* (`resource$schema
  = {name, url, version}`). `dg_schema()` resolves the pointer — the `url`
  directly, or the `name` via `resolve_schema_url()` against
  `schema.data.gouv.fr` — to a Table Schema document and returns its `fields`
  as a tibble of `name`, `title`, `description`, `type`, `example`, with the
  schema's `title`/`name` as attributes. *(An early sketch targeted the tabular
  API `/resources/{rid}/profile/` endpoint; the implementation instead reads
  documented fields from schema.data.gouv.fr, which is where producer-written
  per-column descriptions actually live.)*
- Returns `NULL` (with a message) when the resource declares no schema pointer,
  and errors when the resource is not found or the id is malformed.

---

## File-level change map

| File | Change |
|------|--------|
| `R/utils.R` | `read_zip_resource()` unchanged; add `read_one_zip_file(zip, file)`; id helpers `compose_table_id()` / `parse_table_id()`, `table_attr()` / `table_id_from_attr()` / `resolve_table_id()`; `prefer_lightest_file()` reduces same-data multi-format candidates to the lightest copy. **v2 switch:** add `datagouv_v2_base_url()` / `datagouv_search_url()`, `fetch_search_page()` (repeated `format` params + new filter args), `fetch_search_all()` (string `next_page` pagination with v1-object fallback), `fetch_resource_subsection()` (fully paginated), `fetch_dataset_v2()`, `append_url_params()`, `replace_url_page()`. **Topics:** `datagouv_topics_url()`; thread `topic` through `fetch_search_page()`/`fetch_search_all()`; topics crawler `fetch_topic_page()` / `fetch_topics_all()` (clone of the organizations crawler), `fetch_topic_elements()` (paginated elements subsection, nested `element$class` classifier), `topic_element_counts()`. **col_types/problems:** internal `col_types_to_spec()` maps named shorthand vectors to a `vroom::cols()` spec; `parse_resource_file()`/`read_resource()`/`read_zip_resource()`/`read_one_zip_file()` thread `col_types`; `parse_resource_file()` muffles vroom's parsing warnings via `withCallingHandlers` and attaches `vroom::problems()` (temp-file path stripped, only when non-empty) as the `rdatagouv_problems` attribute. **Tabular-profile typing:** `python_type_to_col()`, `tabular_profile(rid)`, `tabular_profile_col_types()`, `tabular_types_for_resource(resource, use_tabular_types)`, `merge_col_types(col_types, tabular)`; `read_resource()` gains `use_tabular_types` and resolves the profile + merge at the leaf for non-ZIP resources; `read_first_parseable_resource()`/`read_one_zip_file()` gain `use_tabular_types` (no-op for ZIP members); `first_tabular_candidate()` removed. |
| `R/dg-pull-dataset.R` | `dg_pull_dataset()` returns a single tibble (first parseable file of a ZIP) with the `id` as an attribute; `all_files = TRUE` returns a named list, each element carrying its own id. Adds `col_types` (named shorthand vector, threaded to the parse step) and `use_tabular_types` (default `TRUE`, threaded to `read_first_parseable_resource()`). (Stays on v1.) |
| `R/dg-table-id.R` (new) | Exported `dg_table_id(x)` reads the `id` attribute. |
| `R/dg-problems.R` (new) | Exported `dg_problems(x)` reads the `rdatagouv_problems` attribute on a pulled/re-fetched table. |
| `R/dg-summary.R` / `R/dg-summarise.R` | `dg_summary()` needs no metadata-column exclusion (id is an attribute); `dg_summarise()` accepts a `dg_list_datasets()` tibble. |
| `R/dg-list-datasets.R` | Add `n_resources`, `formats`, `has_table`, `has_schema` columns, and the `format` argument (server-side per-format filtering, unioned and de-duplicated by id). **v2 switch:** rework onto `fetch_search_all()` over `datasets/search`; new server-side filter args (`organization`, `geozone`, `access_type`, `license`, `tag`, `granularity`, `last_update`, `producer_type`); new inline columns; resource columns `NA` unless `resources = TRUE`. |
| `R/dg-find-datasets.R` (formerly `dg-list-datasets.R`) | Renamed verb-first. Adds the `topic` server-side filter (a 24-hex topic id, open vocabulary like `tag`/`geozone`, deliberately not validated and not name/slug-resolved). |
| `R/dg-find-topics.R` (new) | Exported `dg_find_topics(q, n, elements)` mirroring `dg_find_organization()`: tibble `{id, name, slug, description, tags, featured, n_elements}` plus `n_datasets`/`n_dataservices`/`n_reuses` when `elements = TRUE` (N+1 per-topic fetch, counting nested `element$class`); external-link (NULL-class) entries excluded. |
| `R/dg-glimpse.R` (new) | Exported `dg_glimpse(id, table = NULL)` surfaces v2-inline dataset metadata (`quality`, `metrics`, `context`, plus `resources` when `table = TRUE`) via `fetch_dataset_v2()` + `fetch_resource_subsection()`. |
| `R/dg-refetch.R` (new) | `dg_refetch(x)` + `resolve_table_id()` validation; re-attaches the id attribute. Adds `col_types` (threaded to `read_resource()`/`read_one_zip_file()`) and `use_tabular_types` (default `TRUE`, threaded to `read_resource()` for single-file / `read_one_zip_file()` for ZIP members). |
| `R/dg-schema.R` (new) | `dg_schema(x)` via `resolve_table_id()` → schema.data.gouv.fr Table Schema, with `NULL` when no schema pointer. |
| `R/rdatagouv-package.R` / NAMESPACE | Document/export the new functions. |
| `tests/` | Unit + snapshot tests for each change. |
| `tests/test-live-api.R` (new) | Opt-in live integration tests: verify a file inside a real ZIP is addressable and re-fetchable via its composed URI on the live data.gouv API. Skipped unless `DATAGOUV_LIVE=1` (connectivity is probed against data.gouv itself, not `skip_if_offline()`'s `captive.apple.com`). See AGENTS.md. |
| `README.qmd` | Update flow examples; rebuild README. |

---

## Phasing

1. **Baseline only** *(implemented)*: composed ID + `dg_refetch()` + tests.
2. **Search surfacing** *(implemented)*: `dg_list_datasets()` availability columns + tests.
3. **Preview loop** *(implemented)*: `dg_summarise()` accepts a list-datasets tibble + tests.
4. **Column profile** *(implemented)*: `dg_schema(id)` via schema.data.gouv.fr Table Schema,
   `NULL` fallback when no schema pointer + tests.
5. **ID as attribute refactor** *(implemented)*: move the composed ID out of a per-row column
   into a table `id` attribute; `dg_pull_dataset()` returns a single tibble by default and a
   named list only for `all_files = TRUE` on a multi-file ZIP; add `dg_table_id()`; `dg_refetch()`/
   `dg_schema()` accept a table or a bare id string.
6. (Optional) convenience tweaks.
7. **API cleanup** *(implemented)*: `get_summary()`/`summarise_datasets()` renamed to
   `dg_summary()`/`dg_summarise()` for a uniform `dg_*` prefix; `dg_download_many()` removed
   (covered by `dg_pull_dataset()` + `dg_summarise()`); each public function split into its own
   `R/dg-*.R` file (`format_tibble()` moved to `utils.R`).
8. **Live integration tests** *(implemented)*: `tests/test-live-api.R` proves the composed
   URI addressing (incl. a file inside a multi-file ZIP) against the real API, gated behind
   `DATAGOUV_LIVE=1`.
9. **v2 discovery switch** *(implemented)*: `dg_list_datasets()` moves from v1 `datasets` to
   the v2 `datasets/search` API (repeated-format params, string `next_page` pagination, rich
   inline metadata); new server-side filter args and inline columns; resource-derived columns
   become `NA` unless `resources = TRUE`; new export `dg_glimpse()` surfaces v2-only
   dataset metadata. Pull/refetch/schema/summary remain on v1.
   *(Page-size tuning: the v2 search endpoint's latency scales with `page_size` — a
   `page_size = 1000` page consistently tripped the 30s `req_data_gouv()` timeout — so the
   crawl pages at `page_size = 100` by default and scales adaptively to ~250 for large/`Inf`
   `n`, clamping the final page to the remaining budget. Kept out of `n = Inf`'s path so a
   full 10,000-row crawl is ~40 requests instead of ~100.)*
10. **Topic support** *(implemented)*: `dg_find_topics()` (topics/search crawler +
    `${id}` → `elements/` classifier for the per-kind N+1 breakdown) and the `topic =` filter
    on `dg_find_datasets()`. Topics reuse the exact pointer-pagination envelope of
    organizations, so no new pagination machinery. Element kind lives in the nested
    `element$class`; NULL-class entries are curator external links and never counted.
11. **Tabular-profile column typing** *(implemented)*: `dg_pull_dataset()`/`dg_refetch()`
    gain `use_tabular_types` (default `TRUE`), seeding vroom's `col_types` from each
    resource's own csv-detective profile on
    `tabular-api.data.gouv.fr/api/resources/<rid>/profile/` (explicit `col_types` win on
    collision). The profile is resolved at the leaf `read_resource()` inside the parse loop,
    so a multi-resource dataset uses the actual profile of the resource that parses, not a
    first-candidate guess (the prototype-only `first_tabular_candidate()` was removed).
    Best-effort: only single-file indexed resources have a profile (ZIP members are a
    no-op), a 404/network failure degrades to inference, and a per-column detection whose
    confidence `score` falls below `min_score = 0.5` is left for vroom to infer rather
    than pinned. Tests in `tests/testthat/test-tabular-types.R` (all
    network/file steps mocked).
