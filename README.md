

<!-- README.md is generated from README.qmd. Please edit that file -->

# rdatagouv

<!-- badges: start -->

[![R-CMD-check](https://github.com/astamm/rdatagouv/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/astamm/rdatagouv/actions/workflows/R-CMD-check.yaml)
[![Codecov test
coverage](https://codecov.io/gh/astamm/rdatagouv/graph/badge.svg)](https://app.codecov.io/gh/astamm/rdatagouv)
[![pkgdown](https://github.com/astamm/rdatagouv/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/astamm/rdatagouv/actions/workflows/pkgdown.yaml)
[![CRAN
status](https://www.r-pkg.org/badges/version/rdatagouv.png)](https://CRAN.R-project.org/package=rdatagouv)
<!-- badges: end -->

`rdatagouv` is an R client for the public API of
[data.gouv.fr](https://www.data.gouv.fr), the French government’s open
data platform. It helps you *find* a dataset that matches your
interests, *judge* whether it is usable, *download* it, and later
*re-fetch the exact same table* reproducibly. Requests are built on top
of the [`httr2`](https://httr2.r-lib.org) package.

## Installation

``` r
# From GitHub once the package is published
# remotes::install_github("astamm/rdatagouv")
```

## Quick start

`rdatagouv` revolves around a simple workflow: **find** a dataset,
**judge** whether it is usable, **fetch** it into a table, and later
**re-fetch the exact same table** reproducibly. The examples below hit
the live data.gouv.fr API and show real results.

### 1. Find

`dg_find_datasets()` searches the catalog by keyword and returns one row
per dataset, with metadata (`quality_score`, `views`, `license`, …) to
help you choose:

``` r
library(rdatagouv)

hits <- dg_find_datasets(q = "vélo", n = 5)
hits[, c("title", "id", "organization", "quality_score")]
#> # A tibble: 5 × 4
#>   title                                         id    organization quality_score
#>   <chr>                                         <chr> <chr>                <dbl>
#> 1 "Statistiques de subventions d’achat de vélo… 63a3… ile-de-fran…         0.889
#> 2 "Fréquentation mesurée dans les Parkings Vél… 63a3… ile-de-fran…         0.889
#> 3 "Nombre de places de stationnement vélo "     67ca… ecolab-1             0.889
#> 4 "Vélib - Vélos et bornes - Disponibilité tem… 5a4e… ville-de-pa…         0.889
#> 5 "Plan Vélo 2021-2026"                         6271… ville-de-pa…         0.778
```

You can also discover producers with `dg_find_organization()` or curated
themes with `dg_find_topics()`, and narrow a search to one of them via
the `organization` / `topic` arguments.

### 2. Judge

Before pulling, glimpse a dataset’s health and engagement in one call,
or read its documented columns with `dg_schema()`:

``` r
g <- dg_glimpse("6a6be5976a05df136d48fb7a")
g$quality$score
#> [1] 0.5555556
```

### 3. Fetch

`dg_pull_dataset()` downloads the dataset’s first tabular resource and
returns a single tibble, with a stable table id attached as an
attribute:

``` r
tbl <- dg_pull_dataset("6397c0ff56d3963118a18345")     # C.vélo bike stations
head(tbl[, 1:6])
#> # A tibble: 6 × 6
#>   station_id name                    physical_configuration   lat   lon altitude
#>        <int> <chr>                   <chr>                  <dbl> <dbl>    <dbl>
#> 1          4 04 UCA - Campus Cézeaux REGULAR                   NA    NA       NA
#> 2          7 07 - Delille            REGULAR                   NA    NA       NA
#> 3          8 08A - Gaillard          REGULAR                   NA    NA       NA
#> 4          9 09 - Chamalières Mairie REGULAR                   NA    NA       NA
#> 5         14 14 - Les Carmes         REGULAR                   NA    NA       NA
#> 6         19 19 - Amboise            REGULAR                   NA    NA       NA
dg_table_id(tbl)
#> [1] "https://www.data.gouv.fr/datasets/6397c0ff56d3963118a18345#01f5b3da-8d58-42c6-a07d-202538ad6672"
```

### 4. Re-fetch reproducibly

Save that id, and `dg_refetch()` gets back the exact same table later —
no matter how titles or file names drift on the platform:

``` r
again <- dg_refetch(tbl)

identical(again, tbl)
#> [1] TRUE
```

### 5. Summarise

`dg_summary()` computes metrics for one table (size, columns, rows,
missing-value rate), and `dg_summarise()` does the same for many at once
— even an entire `dg_find_datasets()` result:

``` r
dg_summarise(datasets = list(iris = iris, mtcars = mtcars))
#> # A tibble: 2 × 7
#>   dataset size_kb n_vars n_numeric n_non_numeric n_rows prop_missing
#> * <chr>     <dbl>  <int>     <int>         <int>  <int>        <dbl>
#> 1 iris       7.09      5         4             1    150            0
#> 2 mtcars     7.04     11        11             0     32            0
```

For a deeper tour — including column-type control and handling parsing
problems — see the
[vignette](https://astamm.github.io/rdatagouv/articles/rdatagouv.html).

## Supported formats

`dg_pull_dataset()` downloads the first tabular resource of a dataset
among CSV, CSV.GZ, XLS, XLSX, PARQUET, TSV, TXT and JSON, and returns
the parsed table as a single tibble. A ZIP resource is unpacked and its
first parseable file is returned by default; `all_files = TRUE` keeps
every contained file in one of these formats as a named list — one
element per file. The delimiter of CSV/TXT resources is auto-detected
(comma, semicolon, tab, pipe, …), so both standard and European-style
(semicolon/comma-decimal) files are handled without special
configuration. Column types are inferred by vroom, but seeded by default
from data.gouv’s own `csv-detective` profile
(`use_tabular_types = TRUE`) and you can force specific columns with
`col_types = c(col = "Date")` (e.g. to make a mostly-padded ISO date
column with a few non-padded stragglers read as `Date`, turning the
stragglers into `NA`; explicit `col_types` always win). The profile is a
best-effort signal — it only exists for single-file resources indexed by
the tabular service, and a missing profile (or a ZIP member) falls back
to type inference; pass `use_tabular_types = FALSE` to disable seeding
entirely. Any parsing issues are attached to the returned table as an
`rdatagouv_problems` attribute — read them with `dg_problems(tbl)` —
rather than a noisy per-cell warning.

The discovery catalog (`dg_find_datasets()`) is restricted to the
official tabular formats data.gouv.fr itself indexes (`csv`, `csv.gz`,
`xls`, `xlsx`, `parquet`), so every listed dataset is in principle
openable as a table. Use the `format` argument to narrow the catalog to
datasets with a resource in a specific format (the v2 search API matches
several formats as a server-side union). The exact
`n_resources`/`formats`/`has_table`/`has_schema` resource columns are
populated by passing `resources = TRUE`. Direct pulls additionally
accept `tsv`, `txt` and `json` resources.

## Disclaimer

This package is not affiliated with or endorsed by data.gouv.fr. It is
an independent project, and the authors are not responsible for the
content of the datasets it indexes. This first version is a proof of
concept and may contain bugs. Please report any issues on the [GitHub
repository](https://github.com/astamm/rdatagouv/issues).

This package is the result of a joint effort initiated during the French
[Finist’R](https://stateofther.pages-forge.inrae.fr/finistr2026/)
bootcamp which was held in Roscoff in August 2026. It served as a
complex task to benchmark R package development assisted by AI. The
refinements that came up during the bootcamp were made with the
assistance of `deepseek-v4-flash` as provided by Albert API, the French
government’s AI platform. The author is grateful to the Finist’R
organizers and the Albert API team for their support and guidance.
