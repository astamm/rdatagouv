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
ignored by R CMD build). The README and the vignette `vignettes/datagouv.qmd`
document usage for end users.

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

**Composed table id.** Each parsed table's address is
`<dataset_id>::<resource_id>` (single file) or
`<dataset_id>::<resource_id>::<file>` (a file inside a ZIP). `dataset_id` is a
24-hex ObjectId, `resource_id` a UUID, `<file>` a base name; `::` never appears
in those fields. Built from the platform's own identifiers, so it is stable and
re-fetchable, unlike human-readable titles. Stored as the `id` **attribute** of
each table by `dg_pull_dataset()`/`dg_refetch()` (not a column); `dg_table_id()`
and `dg_refetch()`/`dg_schema()` consume it. Set *after* parsing so low-level
readers stay untouched.

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

- Source files use **hyphens**, not underscores (`dg-list-datasets.R`, not
  `dg_list_datasets.R`).
- All HTTP goes through `req_data_gouv()` + `http_perform()` (consistent
  user-agent, timeouts, retries).
- Tests: testthat edition 3, files in `tests/testthat/`
  (`test-dg-*.R`, `test-dg-summary.R`, `test-dg-summarise.R`, `test-utils.R`);
  mocks in `helper-data.R` (`mock_dataset`, `mock_resource`, `mock_csv_data`);
  snapshots under `_snaps/`. Run `devtools::test()`.
- **Examples in roxygen**: use `@examples` for network-free code (e.g.
  `dg_summary`, and the in-memory branch of `dg_summarise`) and
  `@examplesIf interactive()` for anything that hits the live API (a live call
  in `@examples` breaks `R CMD check`).

## Documentation / build

- README is Quarto: edit `README.qmd`, regenerate `README.md` via
  `quarto::quarto_render("README.qmd", "gfm")`. Do not hand-edit README.md.
- One Quarto vignette: `vignettes/datagouv.qmd`. It uses a knitr chunk hook so
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

`vignettes/datagouv.qmd` sets `knitr::opts_hooks` for `live` (DATAGOUV_LIVE=1)
and `dg`. The `dg` hook gates the two network-free in-memory chunks so a bad
environment degrades to a skip instead of failing `R CMD build`. Each chunk sets
`#| dg: <function name>` (e.g. `dg: dg_summarise`) **and** `#| error: true`, and
wraps its call in `try()` (the actual robustness guarantee — see below); the
hook evaluates the chunk only when `DATAGOUV_LIVE=1` **and**
`"package:datagouv" %in% search()` **and** the named export forces to a real
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
`Quitting from datagouv.qmd:286-291`, `could not find function
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
