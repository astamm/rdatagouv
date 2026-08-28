# AGENTS.md

Guidance for AI agents (and returning humans) working on the `rdatagouv` R
package. Establishes the package's intent, architecture and conventions so
future sessions can pick up context quickly.

## Purpose

`rdatagouv` is an R client for the public API of data.gouv.fr, the French
government's open-data platform. Its **primary intent** (the reframed goal that
drives the design):

> Let students/data scientists find a dataset matching their interests, judge
> whether it is usable, fetch it, and re-fetch the exact same table
> reproducibly.

Four workflow steps, each mapping to exported functions:

| Step | Function |
|------|----------|
| Find / search the catalog | `dg_find_datasets()` |
| Find / identify producers | `dg_find_organization()` |
| Find / identify themes | `dg_find_topics()` |
| Judge documented columns | `dg_schema()` |
| Download tabular resources | `dg_pull_dataset()` |
| Summarise table contents | `dg_summary()`, `dg_summarise()` |
| Re-fetch a table reproducibly | `dg_refetch()` |

The design rationale and full history live in `DESIGN-discovery.md` (top-level,
ignored by R CMD build). Treat that file as a proposal/decision log: its
`*(implemented)*` phasing markers and change map reflect status, but the
`TOPIC-SUPPORT-SKETCH.md` (top-level) is a related decision log that sketched
and confirmed the topic-support work (`dg_find_topics()` + the `topic` filter on
`dg_find_datasets()`); like `DESIGN-discovery.md` it is also Rbuildignore'd so
it never trips `R CMD check`. Both logs track status/decisions, but the
"Core design concepts", [Public API](#public-api-7-exports) and architecture
sections of *this* AGENTS.md are the source of truth for how the package
currently behaves; exploratory/optional and superseded-alternative sections in
the design doc are historical, not normative. The README and the vignette
`vignettes/rdatagouv.qmd` document usage for end users.

## Public API (10 exports)

- `dg_find_datasets(q = NULL, n = 1000, format = catalog_formats(),
  schema_only = FALSE, organization = NULL, geozone = NULL, access_type = NULL,
  license = NULL, tag = NULL, topic = NULL, granularity = NULL,
  last_update = NULL, producer_type = NULL, resources = FALSE)` -> tibble with robust columns
  `title, id, description, slug, organization, license, quality_score,
  quality_flags, views, resources_downloads, access_type, frequency,
  spatial_granularity, temporal_start, temporal_end, archived, featured` plus
  the resource-derived `n_resources, formats, has_table, has_schema` (`formats`
  is a **list-column** — each element a `character` vector of distinct file
  formats, `NULL` when `resources = FALSE`). `q` is
  server-side full-text search; `n = Inf` fetches as much as the API allows
  (**capped at 10,000** by data.gouv); `format` narrows to datasets holding a
  resource in one of the given formats — the v2 API matches **multiple `format`
  values as repeated params** (`format=csv&format=parquet`, a server-side
  union; a bare comma-joined value is *not* parsed, so pass a vector);
  `schema_only = TRUE` stays **client-side** (v2 has no "declares any schema"
  boolean) and now **forces `resources = TRUE`** with an informative message —
  calling it with the default `resources = FALSE` used to silently return the
  unfiltered catalog with `has_schema = NA` (a no-op filter); the filter args (`geozone`,
  `access_type`, `license`, `tag`, `topic`, `granularity`, `last_update`,
  `producer_type`) are forwarded as server-side filters. `organization` accepts
  a 24-hex producer id **or** an organization `name`/`slug`; a name/slug is
  auto-resolved to its 24-hex id via the v2 `organizations/search` endpoint
  using an **exact match only** (`resolve_organization_id()`) and errors with
  the candidate list on zero or multiple exact matches, while a bare 24-hex id
  is passed straight through without a lookup. `topic` accepts the **24-hex id
  of a theme** (found via `dg_find_topics()`); like `tag`/`geozone` it is an
  open vocabulary, so it is **not validated or name/slug-resolved** (unlike
  `organization`) — discover the id with `dg_find_topics()` and pass it
  directly. **Resource fidelity is
  opt-in**: because v2 search does NOT inline resources, `n_resources`,
  `formats`, `has_table` and `has_schema` are `NA` unless `resources = TRUE`
  (which N+1-fetches each dataset's resources subsection). `id` and `title` are
  always non-`NA` (contract with `dg_summarise()`). Backed by
  `fetch_search_all()`/`fetch_search_page()` on the v2 `datasets/search`
  endpoint (string `next_page` pointer pagination; `fetch_search_all()` uses
  `adaptive_page_size()` — default `page_size = 100`, scaled up to ~250 for
  large/`Inf` `n` to cut round-trips on a full catalog crawl, and clamped to
  the remaining budget for a finite `n`. It stays low because the v2 search
  endpoint's latency scales with page_size and `page_size = 1000` consistently
  trips the 30s timeout in `req_data_gouv()`).
- `dg_find_organization(q = NULL, n = 20)` -> tibble
  `id, name, slug, acronym, description, datasets, badges,
  business_number_id`, listing producers matching `q` from the v2
  `organizations/search` endpoint (`q` is server-side full-text; default
  `n = 20`). `datasets` is the org's dataset count coerced to integer,
  `badges` a comma-joined string; absent fields coerce to `NA` via internal
  `organization_empty_columns()`. Use it to discover a producer and get its
  stable 24-hex `id`, which you can pass to `dg_find_datasets(organization =)`.
  Backed by `fetch_organizations_all()`/`fetch_organization_page()` (same
  pointer-pagination envelope as `fetch_search_page()`).
- `dg_find_topics(q = NULL, n = 20, elements = FALSE)` -> tibble
  `id, name, slug, description, tags, featured, n_elements` plus
  `n_datasets, n_dataservices, n_reuses`, listing themes matching `q` from the
  v2 `topics/search` endpoint (`q` is server-side full-text; default `n = 20`).
  `n_elements` is always the topic's declared `elements$total`; the per-kind
  breakdown is `NA` unless `elements = TRUE`, which N+1-fetches each topic's
  `topics/<id>/elements/` subsection and counts the **nested `element$class`**
  (Dataset/Reuse/Dataservice); external-link (NULL-class) entries are excluded.
  Use it to discover a theme and get its stable 24-hex `id`, which you pass to
  `dg_find_datasets(topic =)`. Backed by `fetch_topics_all()`/
  `fetch_topic_page()` (same pointer-pagination envelope as organizations),
  plus `fetch_topic_elements()`/`topic_element_counts()`.
- `dg_glimpse(id, table = NULL)` -> a named list surfacing v2-inline
  dataset-level metadata that the v1 fetch path does not expose:
  `quality` (score + boolean flags), `metrics` (views, resources_downloads,
  followers, discussions, reuses, dataservices) and `context`
  (organization, license, frequency, temporal/spatial coverage, access_type,
  archived, featured). `id` may be a dataset id (24-hex), a composed table id
  or a pulled table (its `id` attribute is read); `table = TRUE` also includes
  the resource list via `fetch_resource_subsection(id)` (N+1). Uses internal
  `fetch_dataset_v2(id)`.
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
  Accepts a named list of tibbles, a nested list (ZIP), a `dg_find_datasets()`
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
  `%||%`, `uniquify_names`, `is_dataset_id`, plus the organization-source
  helpers `datagouv_organizations_url()`, `fetch_organization_page()`,
  `fetch_organizations_all()` and `resolve_organization_id()`, and the
  topic-source helpers `datagouv_topics_url()`, `fetch_topic_page()`,
  `fetch_topics_all()`, `fetch_topic_elements()` and `topic_element_counts()`.
- `R/dg-find-datasets.R` — `dg_find_datasets()`.
- `R/dg-find-organization.R` — `dg_find_organization()` + internal
  `organization_empty_columns()`.
- `R/dg-find-topics.R` — `dg_find_topics()` + internal
  `topic_empty_columns()`.
- `R/dg-pull-dataset.R` — `dg_pull_dataset()`.
- `R/dg-table-id.R` — `dg_table_id()`.
- `R/dg-refetch.R` — `dg_refetch()` + `parse_table_id` validation.
- `R/dg-schema.R` — `dg_schema()` + `field_attr()` + `resolve_schema_url()`.
- `R/dg-summary.R` — `dg_summary()` (single-table metrics).
- `R/dg-summarise.R` — `dg_summarise()` + internal `flatten_tables`.
- `R/rdatagouv-package.R` — package-level `.Rd`.

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
  (`dg_find_datasets()`) is restricted to these so every listed dataset is in
  principle openable as a table. The API honors a single `format` value per
  query, so `fetch_all_datasets()` queries each requested format separately and
  unions/deduplicates by dataset id.
- `supported_formats()` = `c("zip", "csv", "csv.gz", "xls", "xlsx", "parquet",
  "tsv", "txt", "json")` — everything a direct pull can parse. JSON/TSV/TXT are
  intentionally NOT in the catalog (not guaranteed tabular) but remain
  parseable when addressed directly.

**Delimited-text parsing (`parse_resource_file()`).** All delimited formats
(CSV, CSV.GZ, TSV, TXT) are read with a single `vroom::vroom()` call instead of
the individual `readr` readers; `readr` is **not** an import. The delimiter is
still probed first by `guess_delimiter()` because vroom's own guesser is
comma-first and would silently corrupt European-style files (semicolon
separator with a comma decimal mark — the commas in the numbers would be read
as extra field separators); `.csv` with a `;` delimiter gets a comma-decimal
locale via `vroom::locale(decimal_mark = ",")`, reproducing the `read_csv2`
behaviour it replaces. `vroom` is invoked with `altrep = FALSE` so the returned
table is materialised eagerly and does not lazily reference the temporary file
that `download_resource()` unlinks on exit.

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
- Source files use **hyphens**, not underscores (`dg-find-datasets.R`, not
  `dg_find_datasets.R`).
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
- One Quarto vignette: `vignettes/rdatagouv.qmd`. It uses a knitr chunk hook so
  live-API chunks (marked `#| live: true`) run only when the `DATAGOUV_LIVE=1`
  env var is set (the pkgdown workflow sets it so the site shows real output).
  They are skipped otherwise — including during `R CMD build`/`R CMD check`,
  which render the vignette in a subprocess where `_R_CHECK_PACKAGE_NAME_` is
  NOT set and so cannot be used to gate live code. DESCRIPTION needs `VignetteBuilder: quarto`,
  `Config/Quarto/version`, and `knitr`/`quarto` in Suggests.
- `_pkgdown.yml` lists all 7 exports in the reference sections and registers
  the vignette under `articles`.
- Regenerate docs with `devtools::document()`; verify with `devtools::test()`
  and `devtools::check()`.
- **Keep docs in sync on every change.** At the end of each task, audit the
  package-level docs and fill in relevant files to reflect the changes made —
  whether a function or feature was added, removed, or changed signature.
  Cover at minimum: vignettes (`vignettes/rdatagouv.qmd`), pkgdown-related
  files (`_pkgdown.yml`, `.github/workflows/pkgdown.yaml`), `DESCRIPTION`,
  `NEWS.md`, `DESIGN-discovery.md`, and the `README.qmd`/`README.md` pair
  (regenerate `README.md` from `README.qmd` with `devtools::build_readme()`).
  And check function-level roxygen-generated docs: update the roxygen comments
  in the source files under `R/` and run `devtools::document()` to regenerate
  the `.Rd` files under `man/`. Do this on every task, not only when a doc
  update is explicitly requested, so the documentation never drifts from the
  code.

## R-hub CI troubleshooting (as of 2026-08-21)

The R-hub GitHub Actions workflow (`.github/workflows/rhub.yaml`) has been
fighting three distinct, mostly *upstream* R-devel container problems. All are
transient platform artifacts — none reflect a defect in the package (local
`R CMD build` + test suite, 0 errors, are green):

- **Stale R-devel snapshots break rlang from source.** Containers `c23`,
  `clang16`–`clang20`, `gcc13`–`gcc15` carry R-devel r89629/r89623 (2026-03),
  which predate the `R_envSymbols` header (added r89633) by hours, so current
  rlang (>=1.1.7, e.g. 1.3.0) fails to compile from source (`use of undeclared
  identifier 'R_envSymbols'`). These are excluded from the Linux matrix until
  r-hub rebuilds them past r89633.
- **gcc16** (GCC trunk aka 16.0 | Fedora 44 | R-devel r90447, 2026-08-25 — a
  *healthy* fresh snapshot and the successor of the deprecated gcc15) failed
  at `setup-deps` with a pak **sysreqs install** error: `Librepo error: Cannot
  download Packages/m/mesa-dri-drivers-26.1.7-1.fc44.x86_64.rpm: All mirrors
  were tried` (run 32949887407, 2026-08-26). This is NOT a compiler-compat or
  sanitizer issue (unlike the other exclusions) — pak's `plan$install_sysreqs()`
  ran DNF to install a system RPM and the Fedora 44 mirror could not serve the
  `mesa-dri-drivers` RPM (transient/unstable repo or the RPM was removed/
  replaced). It is an upstream mirror/RPM-availability failure, not a package
  defect. gcc16 is otherwise valuable coverage (newest compiler), so it is
  excluded only until the Fedora 44 repo stabilizes — re-enable (drop it from
  `RHUB_EXCLUDED`) when a re-run of the `setup-deps`-only stage succeeds.
- **clang21** (healthy newer snapshot r90185) breaks because the r-hub CRAN
  *binary* `bit64` links against `libclang_rt.ubsan_standalone`, missing at load
  time -> readr-based parsing fails in tests + vignette. **Resolved 2026-08-22:**
  the source-only flag (`pkg.platforms = "source"` + `R_PROFILE`) *is* honored —
  the repo table in `setup-deps` shows pak solving for `source src/contrib` — but
  it is silently defeated by the r-lib `actions/cache`. The cache key is stable
  (it hashes OS/R-version + RHUB repo path + `.github/r-depends.rds`, and
  bit64's version 4.8.4 is unchanged), so the poisoned *binary* `bit64.so`
  (dated 2026-08-20) is *restored from cache* every run; pak's `lockfile_install`
  then only installs the 1-package gap and never recompiles the cache-restored
  bit64. (Root cause is thus the cache restore, not the platform flag.)
  **Fix refinement 2026-08-22 (run 32561306626):** the first repair attempt
  — remove `bit64` from `R_LIBS_USER` then `pak::pkg_install("bit64=?source")`
  — did *not* work: the step ran (bit64 detected, `remove.packages` called)
  but pak finished in ~1.3s with "No downloads are needed" and never
  recompiled, because pak's solver treats the already-installed 4.8.4 as
  satisfying `=?source` regardless of source/binary origin. The reliable fix
  is to bypass pak's up-to-date check entirely and install the CRAN **source
  tarball** directly: `install.packages(<bit64_4.8.4.tar.gz>, lib=R_LIBS_USER,
  repos=NULL, type="source")`, which always compiles against the container's
  native toolchain. That clang21-only step sits between `setup-deps` and
  `run-check`; the post-run cache step then saves the repaired library so
  later runs restore the good bit64.
- **nosuggests** (fedora-42/4.7, R-devel r90185 — a *healthy* fresh snapshot, so
  NOT part of the stale-snapshot family) breaks because the container's
  `libR.so` is built with Address/UndefinedBehaviour sanitization: its link
  propagates `libasan.so.8`/`libubsan.so.1` as DT_NEEDED onto *every* package
  `.so` compiled against it, and those runtime libraries are absent from the
  container. Loading any such `.so` (processx, pulled in by rcmdcheck -> callr)
  fails with `libasan.so.8: cannot open shared object file` before the test
  suite runs. **This is NOT a cache problem** (contrary to an early 2026-08-22
  hypothesis). Forcing a clean source rebuild of processx via
  `install.packages(type="source", repos=NULL)` (run 32599565727) *did*
  recompile the package, but the rebuilt `processx.so` still linked
  `libasan.so.8 => not found`/`libubsan.so.1 => not found` (confirmed by the
  step's own `ldd`), and run-check then failed identically — so the cache-delete
  fix (as for clang21/bit64) is inapplicable. Resolved: exclude `nosuggests`
  from the matrix until r-hub rebuilds the container to drop the sanitizer
  instrumentation or ship the missing runtime libraries.
- **valgrind** (debian/R-devel, run 32601275200) fails for the **same**
  sanitizer reason as `nosuggests` (confirmed 2026-08-23): `rcmdcheck` pulls in
  callr -> processx, and `dyn.load(processx.so)` aborts with
  `libasan.so.8: cannot open shared object file` before the test suite runs.
  The valgrind container's `libR.so` is instrumented (it runs
  `R CMD check --use-valgrind`), so every dependency `.so` linked against it
  carries the ASan runtime as a DT_NEEDED that is absent at load time. Not
  reproducible package-side (pure-R package, no native code for valgrind to
  check anyway). Excluded from the matrix alongside `nosuggests`; re-enable
  only when r-hub ships the missing `libasan.so.8` in that image.
  `requireNamespace()` yet did not expose `dg_summarise` (while `dg_summary`
  was callable) in the build subprocess. Reproduced across runs 32387247290,
  32462190016, and 32561358512; neither the `exists()`- nor the `get()`-based
  `dg` hook caught it, pointing to a *present-but-unforceable* lazy-load entry
  that reports "callable" yet throws at call time. R-devel-Windows-specific;
  not reproducible on macOS. **Resolved 2026-08-22:** the `dg` hook fails
  closed on `DATAGOUV_LIVE` *and* the two decorative chunks set `#| error: true`
  (see below), so the in-memory chunks can never abort `R CMD build`. Note run
  32579232283: after the DATAGOUV_LIVE gate was committed, chunk 10 still ran
  and threw during `R CMD build` — the gate alone was not sufficient, because
  either `DATAGOUV_LIVE` was set/leaked in that Windows build subprocess or the
  hook failed to fire there. The `error: true` hardening is environment-
  independent and catches whichever mechanism let the chunk run.

### The `dg` opts_hook (vignette) — why and how

`vignettes/rdatagouv.qmd` sets `knitr::opts_hooks` for `live` (DATAGOUV_LIVE=1)
and `dg`. The `dg` hook gates the two network-free in-memory chunks so a bad
environment degrades to a skip instead of failing `R CMD build`. Each chunk sets
`#| dg: <function name>` (e.g. `dg: dg_summarise`) **and** `#| error: true`, and
wraps its call in `try()` (the actual robustness guarantee — see below); the
hook evaluates the chunk only when `DATAGOUV_LIVE=1` **and**
`"package:rdatagouv" %in% search()` **and** the named export forces to a real
function — checked with `get(<fn>, inherits = TRUE)` inside `tryCatch`, NOT
`exists()`.

**Why fail closed on `DATAGOUV_LIVE`:** the pkgdown site render alone sets
`DATAGOUV_LIVE=1` (see `.github/workflows/pkgdown.yaml`), where the installed
package is guaranteed usable; `R CMD build`/`check` never set it. History:
`requireNamespace()` passed yet the export was missing; `exists(fun,
inherits=TRUE)` also passed on the affected Windows/R-devel installs where the
export is a *broken/unforceable lazy-load entry* — the binding is present but
resolving it at call time throws `could not find function "dg_summarise"` and
aborts the build (run 32462190016). The hook was therefore upgraded to force
the value with `get()` inside `tryCatch`, which reproduced correctly locally
(an active binding that throws on force: `exists()` said TRUE while the
`get()`-based hook returned FALSE). But run 32561358512 (which carried the
`get()`-based hook) *still* aborted on chunk 10 — `get()` returned the unforced
lazy-load promise without error, so the hook judged the export "callable" and
the subsequent call threw. No `get()`/`exists()` prediction reliably catches a
present-but-unforceable lazy-load entry, so the hook now gates on
`DATAGOUV_LIVE` as well. **This environment gate alone proved insufficient:**
run 32579232283 (which carried the DATAGOUV_LIVE-gated hook from commit
`1130f56`) *still* executed chunk 10 during `R CMD build` and aborted — meaning
`DATAGOUV_LIVE` was set/leaked in that Windows build subprocess, or the hook did
not fire there.

**`error: true` alone is NOT a sufficient backstop (run 32594354116, head
`9bf4b6f`).** The follow-up commit added `#| error: true` to both decorative
chunks and still aborted identically — `* creating vignettes ... ERROR`,
`Quitting from rdatagouv.qmd:286-291`, `could not find function
"dg_summarise"`. Reproduced locally with `quarto_render()`: knitr's `error`
option does contain a *normal function-body error*, but it does **not** contain
the unforceable-export hard failure. The error is raised while forcing the
lazy-load promise during call/frame setup — a level knitr's `withCallingHandlers`
around the chunk expression never sees — so it hard-quits regardless of
`error: true`. Neither the DATAGOUV_LIVE gate nor the `get()` callability test
nor `error: true` can stop a broken-export chunk that executes.

**The robust fix is `try()`, which lower-level-contains everything.** Both
decorative chunk bodies are now wrapped in `try(<call>)` (e.g.
`try(dg_summarise(...))`), a base-R catch-all that converts the
unforceable-export hard failure into printed `try-error` output instead of an
abort. Verified three ways with `quarto_render()`/`R CMD build`: (1) healthy
install with `DATAGOUV_LIVE=1` shows the real metrics tables (try() does not
swallow correct output); (2) normal `R CMD build` with `DATAGOUV_LIVE` unset
skips the chunks and builds clean; (3) a broken binding that hard-quits a bare
`error: true` chunk renders to completion when the identical body is wrapped in
`try()`. This removes the failure class from the packaging build while keeping
the examples live on the website.

**Assessment: does the gate mask a real partial-install bug?** No package-side
mechanism can drop a single export (namespaces load atomically; `dg-summarise.R`
is the only source file with no non-ASCII, no load-time side effects; all 7
exports resolve to callable functions locally). The anomaly fits the known
run of R-hub install/hash artifacts. Caveat: runs 32387247290, 32462190016,
32561358512, and 32594354116 all aborted at the vignette before the Windows
*test suite* ran, so there is still no Windows test signal confirming
`dg_summarise`. The DATAGOUV_LIVE-gated hook + `try()`-wrapped bodies let the
vignette render even with the broken export, so the Windows check can finally
proceed to the test suite. If a future Windows/R-devel run shows the *tests*
failing on `dg_summarise` specifically, that would point to a real
platform-specific bug the gate would hide. The gate only controls whether the
*decorative in-memory chunks* display on the website; it is a
vignette-display guard, not a package-correctness check (the test suite is the
right place for that).
