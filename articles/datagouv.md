# Finding, judging and re-fetching French open data with datagouv

> This vignette assumes you can reach the data.gouv.fr API. Code that
> touches the live API only runs when the vignette is rendered with
> `DATAGOUV_LIVE=1` set (as when building this site with pkgdown); it is
> skipped during `R CMD build`/`R CMD check` so those builds stay clean.
> The worked examples below show real output from a live render.

The examples that hit the live API are marked `#| live: true`; they only
run when the document is rendered with the `DATAGOUV_LIVE=1` environment
variable set (the pkgdown site build sets it), and are skipped otherwise
— in particular during `R CMD build`/`R CMD check`, which render this
vignette in a subprocess where the usual `_R_CHECK_PACKAGE_NAME_` marker
is *not* set and therefore cannot be relied on to suppress live code.
In-memory examples run unconditionally:

## The problem datagouv solves

`datagouv` is a small R client for the public API of
[data.gouv.fr](https://www.data.gouv.fr), the French government’s open
data platform. It was written with a specific user in mind: a student or
a data scientist who wants to *find* a dataset that matches their
interests, *judge* whether it is usable for analysis, *download* it, and
later *re-fetch the exact same table* in a reproducible way.

These four steps may sound trivial, but the platform makes each of them
harder than it should be:

1.  **Finding.** Enumerating “all” published datasets means paging
    through tens of thousands of records. The catalog search is
    server-side and only matches titles and descriptions, which are
    free-form and often uninformative.
2.  **Judging.** The tabular API provides no human-readable variable
    descriptions. The actual descriptions live in separate *schema*
    documents on [schema.data.gouv.fr](https://schema.data.gouv.fr);
    data.gouv.fr only attaches a pointer (`name` / `url`) to a resource.
    Without resolving that pointer, you cannot tell whether a column
    really means what you assume.
3.  **Downloading.** Datasets come in many formats (CSV, Excel, ZIP,
    Parquet, JSON…), the declared format is not always accurate, and a
    “dataset” may contain several files.
4.  **Re-fetching.** Catalog titles and even ordering change over time,
    so a script that reaches for a dataset “by title” is fragile. You
    want an address that always resolves to the same table.

`datagouv` addresses all four. Its functions are organised around that
workflow:

| Step | Function |
|----|----|
| Find / search the catalog | [`dg_list_datasets()`](https://astamm.github.io/datagouv/reference/dg_list_datasets.md) |
| Judge documented columns | [`dg_schema()`](https://astamm.github.io/datagouv/reference/dg_schema.md) |
| Download tabular resources | [`dg_pull_dataset()`](https://astamm.github.io/datagouv/reference/dg_pull_dataset.md) |
| Summarise table contents | [`dg_summary()`](https://astamm.github.io/datagouv/reference/dg_summary.md), [`dg_summarise()`](https://astamm.github.io/datagouv/reference/dg_summarise.md) |
| Re-fetch a table reproducibly | [`dg_refetch()`](https://astamm.github.io/datagouv/reference/dg_refetch.md) |

The approach mirrors what several US cities propose (e.g.
[`nycOpenData`](https://github.com/ropensci/nycOpenData) for New York),
but tailored to the data.gouv.fr API.

## Finding datasets

[`dg_list_datasets()`](https://astamm.github.io/datagouv/reference/dg_list_datasets.md)
returns a tibble with one row per dataset:

``` r

library(datagouv)

datasets <- dg_list_datasets(n = 20)
head(datasets)
```

    # A tibble: 6 × 8
      title         id    description slug  n_resources formats has_table has_schema
      <chr>         <chr> <chr>       <chr>       <int> <chr>   <lgl>     <lgl>
    1 Matrice ouve… 6a89… "Ce jeu de… matr…          15 csv, j… TRUE      FALSE
    2 Informations… 6a89… "Version p… info…           3 csv, j… TRUE      FALSE
    3 Jeu de tests… 6a89… "Ce jeu de… jeu-…           4 csv, j… TRUE      FALSE
    4 Registre Bou… 6a89… "Ce jeu de… regi…           2 csv, t… TRUE      FALSE
    5 AFA Eurobaro… 6a88… "AFA Eurob… afa-…           2 csv, j… TRUE      FALSE
    6 AFA extrait … 6a88… "AFA extra… afa-…           2 csv, j… TRUE      FALSE     

The columns are chosen to help you decide, at a glance, whether a
dataset is worth pulling:

- `id` is the stable, unique identifier used to address the dataset
  later.
- `n_resources` is the number of files the dataset contains.
- `formats` lists the distinct file formats found among them.
- `has_table` is `TRUE` when at least one resource can be parsed into a
  table by this package.
- `has_schema` is `TRUE` when at least one resource declares a data
  schema, i.e. when per-variable documentation is available via
  [`dg_schema()`](https://astamm.github.io/datagouv/reference/dg_schema.md).

By default
[`dg_list_datasets()`](https://astamm.github.io/datagouv/reference/dg_list_datasets.md)
returns the first `n` datasets of the catalog, which is both slow and
fragile when done exhaustively. Prefer a server-side search with `q`:

``` r

cycle <- dg_list_datasets(q = "vélo", n = 10)
cycle[, c("title", "n_resources", "has_table", "has_schema")]
```

    # A tibble: 10 × 4
       title                                        n_resources has_table has_schema
       <chr>                                              <int> <lgl>     <lgl>
     1 Stations du réseau vélo libre-service C.vélo           9 TRUE      FALSE
     2 Comptages vélo à Nantes par Place au Vélo -…           2 TRUE      FALSE
     3 Arceau vélo                                            7 TRUE      FALSE
     4 Stationnement vélo                                     4 TRUE      FALSE
     5 Stationnements vélo                                    1 TRUE      TRUE
     6 Arceau vélo                                           16 TRUE      FALSE
     7 Stationnement vélo                                     1 TRUE      FALSE
     8 Prime vélo                                             2 TRUE      FALSE
     9 Primes « vélo »                                        2 TRUE      FALSE
    10 Beauce à vélo                                          8 TRUE      FALSE     

The discovery catalog is **restricted to data.gouv’s official tabular
formats** (`csv`, `csv.gz`, `xls`, `xlsx`, `parquet`), so every listed
dataset is in principle openable as a table — `has_table` is almost
always `TRUE`. This is a deliberate choice: JSON, TSV and TXT resources
can still be parsed when you address them directly (see
[`dg_pull_dataset()`](https://astamm.github.io/datagouv/reference/dg_pull_dataset.md)),
but they are not guaranteed tabular and are left out of the catalog so
that “the catalog” stays a reliable list of tables.

### Restricting to documented datasets

Because descriptions live in schemas and only a fraction of datasets
declare one,
[`dg_schema()`](https://astamm.github.io/datagouv/reference/dg_schema.md)
only helps on a subset of the catalog. You can target that subset
directly:

``` r

documented <- dg_list_datasets(schema_only = TRUE, n = 10)
documented[, c("title", "n_resources", "has_table", "has_schema")]
```

    # A tibble: 0 × 4
    # ℹ 4 variables: title <chr>, n_resources <int>, has_table <lgl>,
    #   has_schema <lgl>

### Restricting to specific formats

You can narrow the catalog to datasets that carry a resource in a format
of your choice with the `format` argument. This is especially useful to
find lighter files (e.g. `parquet`) that download faster than their CSV
twins:

``` r

parquet <- dg_list_datasets(format = "parquet", n = 10)
parquet[, c("title", "formats")]
```

    # A tibble: 10 × 2
       title                                                                 formats
       <chr>                                                                 <chr>
     1 "Agenda 2030 de la Ville de Fleury-sur-Orne"                          csv, j…
     2 "Bibliothèques publiques"                                             csv, c…
     3 "Brevets d'invention Francais 1981 - 2026 "                           parquet
     4 "BAL - Base Adresses Locales - Bourges - 18033"                       csv, g…
     5 "Profil sociodémographique des bureaux de vote — France métropolitai… parquet
     6 "Subventions de la Ville de Bourges en 2025"                          csv, j…
     7 "Budget Ville de Bourges - 2026 - BP"                                 csv, j…
     8 "Demandes de valeurs foncières 2014-2020 PACA"                        csv, p…
     9 "DVF-2019-Region-Sud"                                                 csv, p…
    10 "Habitats à destination du grand âge (hors accueil familial) en Maye… csv, g…

Multiple formats can be requested at once; each is queried server-side
and the results are combined.

## Judging whether a dataset is usable

The judged usefulness of a dataset hinges on whether the columns mean
what you think they mean. That information comes from the producer’s
*schema* on schema.data.gouv.fr.
[`dg_schema()`](https://astamm.github.io/datagouv/reference/dg_schema.md)
takes a table (its id is read automatically) or a composed table id and
returns the documented fields:

``` r

# schema_only filters client-side, so request a batch and take the first hit.
documented <- dg_list_datasets(schema_only = TRUE, n = 100)
table_id <- documented$id[!is.na(documented$id)][[1]]

# Pull it, then inspect the schema of the returned table.
tbl <- dg_pull_dataset(table_id)
```

    Rows: 1 Columns: 75
    ── Column specification ────────────────────────────────────────────────────────
    Delimiter: ","
    chr  (2): nom, naf
    dbl (72): sirenDeclarant, sirenCouvert, cj, annee, nbVP, nbVPEL, nbVPH2, nbV...
    lgl  (1): zone

    ℹ Use `spec()` to retrieve the full column specification for this data.
    ℹ Specify the column types or set `show_col_types = FALSE` to quiet this message.

``` r

schema <- dg_schema(tbl)

# Human-readable titles and descriptions of every column:
head(schema)
```

    # A tibble: 6 × 5
      name           title description                                 type  example
      <chr>          <chr> <chr>                                       <chr> <chr>
    1 sirenDeclarant <NA>  Numéro SIREN de la personne morale déclara… stri… 130025…
    2 sirenCouvert   <NA>  Numéro SIREN couvert sous la déclaration d… stri… 130025…
    3 nom            <NA>  Dénomination officielle de la personne mor… stri… Direct…
    4 naf            <NA>  Code d'activité principale exercée.         stri… 47.72B
    5 cj             <NA>  Catégorie juridique Insee.                  stri… 5710
    6 annee          <NA>  Année concernée par les données rapportées. year  2021   

The result is a tibble with one row per column and the columns `name`,
`title`, `description`, `type` and `example`, together with the schema’s
own `title` and `name` attached as attributes. Where the schema provides
no title or description (some producers document only some fields), the
corresponding cell is `NA`.

If the resource carries no schema pointer,
[`dg_schema()`](https://astamm.github.io/datagouv/reference/dg_schema.md)
returns `NULL` with a message explaining that no variable documentation
is available.

## Downloading data

[`dg_pull_dataset()`](https://astamm.github.io/datagouv/reference/dg_pull_dataset.md)
downloads the first parseable tabular resource of a dataset and returns
a **single tibble**:

``` r

tbl <- dg_pull_dataset("6397c0ff56d3963118a18345")
```

    ℹ Using "','" as decimal and "'.'" as grouping mark. Use `read_delim()` for more control.

    Rows: 82 Columns: 16
    ── Column specification ────────────────────────────────────────────────────────
    Delimiter: ";"
    chr (8): name, physical_configuration, altitude, address, rental_methods, sh...
    dbl (6): station_id, post_code, capacity, is_charging_station, geofenced_cap...
    num (2): lat, lon

    ℹ Use `spec()` to retrieve the full column specification for this data.
    ℹ Specify the column types or set `show_col_types = FALSE` to quiet this message.

``` r

head(tbl)
```

    # A tibble: 6 × 16
      station_id name          physical_configuration    lat    lon altitude address
           <dbl> <chr>         <chr>                   <dbl>  <dbl> <chr>    <chr>
    1          4 04 UCA - Cam… REGULAR                4.58e8 3.11e7 0.0      26 Ave…
    2          7 07 - Delille  REGULAR                4.58e7 3.09e5 0.0      Place …
    3          8 08A - Gailla… REGULAR                4.58e7 3.08e6 0.0      29 Rue…
    4          9 09 - Chamali… REGULAR                4.58e7 3.07e6 0.0      Rue Ch…
    5         14 14 - Les Car… REGULAR                4.58e7 3.09e6 0.0      12 Pla…
    6         19 19 - Amboise  REGULAR                4.58e7 3.09e6 0.0      25-13 …
    # ℹ 9 more variables: post_code <dbl>, capacity <dbl>,
    #   is_charging_station <dbl>, geofenced_capacity <dbl>, rental_methods <chr>,
    #   is_virtual_station <dbl>, short_name <chr>, rental_uris <chr>,
    #   point_geo <chr>

``` r

dg_table_id(tbl)
```

    [1] "6397c0ff56d3963118a18345::01f5b3da-8d58-42c6-a07d-202538ad6672"

A few things to know about pulling:

- Supported formats are `csv`, `csv.gz`, `xls`, `xlsx`, `parquet`,
  `tsv`, `txt` and `json`. A **ZIP** resource is unpacked and its first
  parseable file is returned by default; `all_files = TRUE` keeps every
  contained file in one of these formats as a named list — one element
  per file.
- The delimiter of CSV/TXT resources is auto-detected (comma, semicolon,
  tab, pipe, …), so both standard and European-style files (semicolon /
  decimal-comma) are handled without configuration.
- Declared formats are not always accurate, and a candidate may fail to
  parse (e.g. a `json` resource that actually serves an API metadata
  document).
  [`dg_pull_dataset()`](https://astamm.github.io/datagouv/reference/dg_pull_dataset.md)
  skips non-parseable resources and falls back to the next tabular one
  instead of erroring.
- When a dataset offers the *same table* in several formats (same file
  name, different extension, e.g. `data.csv` vs `data.xlsx`), the
  lightest advertised file is downloaded so the pull is as small as
  possible; resources with distinct names keep their declared order.
- Every returned table carries its stable, unique address as an `id`
  attribute, readable with
  [`dg_table_id()`](https://astamm.github.io/datagouv/reference/dg_table_id.md).

## Re-fetching the same table reproducibly

This is what makes your analysis reproducible over time. The table’s id
is built from the platform’s own stable identifiers
(`<dataset_id>::<resource_id>`, plus the file name for a file inside a
ZIP). Unlike a human-readable title, this address always resolves to the
same table:

``` r

tbl <- dg_pull_dataset("6397c0ff56d3963118a18345")
```

    ℹ Using "','" as decimal and "'.'" as grouping mark. Use `read_delim()` for more control.

    Rows: 82 Columns: 16
    ── Column specification ────────────────────────────────────────────────────────
    Delimiter: ";"
    chr (8): name, physical_configuration, altitude, address, rental_methods, sh...
    dbl (6): station_id, post_code, capacity, is_charging_station, geofenced_cap...
    num (2): lat, lon

    ℹ Use `spec()` to retrieve the full column specification for this data.
    ℹ Specify the column types or set `show_col_types = FALSE` to quiet this message.

``` r

table_id <- dg_table_id(tbl)
table_id
```

    [1] "6397c0ff56d3963118a18345::01f5b3da-8d58-42c6-a07d-202538ad6672"

``` r

# Re-fetch the exact same table later:
again <- dg_refetch(tbl)
```

    ℹ Using "','" as decimal and "'.'" as grouping mark. Use `read_delim()` for more control.
    Rows: 82 Columns: 16── Column specification ────────────────────────────────────────────────────────
    Delimiter: ";"
    chr (8): name, physical_configuration, altitude, address, rental_methods, sh...
    dbl (6): station_id, post_code, capacity, is_charging_station, geofenced_cap...
    num (2): lat, lon
    ℹ Use `spec()` to retrieve the full column specification for this data.
    ℹ Specify the column types or set `show_col_types = FALSE` to quiet this message.

[`dg_refetch()`](https://astamm.github.io/datagouv/reference/dg_refetch.md)
accepts the composed id directly, so you can store it in a script or a
database and reproduce the pull without re-searching the catalog.

## Summarising datasets

[`dg_summary()`](https://astamm.github.io/datagouv/reference/dg_summary.md)
computes metrics for a single table:

``` r

# The call is wrapped in try() as a low-level backstop: neither knitr's
# `error: true` option nor the DATAGOUV_LIVE/get() gate can contain a
# present-but-unforceable lazy-load export (the Windows/R-devel failure,
# see AGENTS.md), whereas try() degrades even that hard failure to printed
# output instead of aborting R CMD build/check.
try(dg_summary(iris, name = "iris"))
```

    # A tibble: 1 × 7
      dataset size_kb n_vars n_numeric n_non_numeric n_rows prop_missing
      <chr>     <dbl>  <int>     <int>         <int>  <int>        <dbl>
    1 iris       7.09      5         4             1    150            0

The reported columns are `dataset` (a label), `size_kb` (in-memory
weight), `n_vars`, `n_numeric`, `n_non_numeric`, `n_rows` and
`prop_missing` (the proportion of missing values). A table’s id is
carried as an attribute, not a column, so it never inflates these
metrics.

[`dg_summarise()`](https://astamm.github.io/datagouv/reference/dg_summarise.md)
applies
[`dg_summary()`](https://astamm.github.io/datagouv/reference/dg_summary.md)
to a collection of tables. It is flexible about its input, accepting:

- a named list of tibbles (each element is a single table),
- a named list of such lists, as returned by
  `dg_pull_dataset(all_files = TRUE)` (a ZIP may contribute several
  tables),
- a tibble from
  [`dg_list_datasets()`](https://astamm.github.io/datagouv/reference/dg_list_datasets.md)
  (each dataset is downloaded and summarised),
- a character vector of identifiers (or exact titles),
- or `NULL` to download and summarise the first `n` datasets of the
  catalog.

``` r

# In-memory tables — no network needed
#| dg: dg_summarise
#| error: true
try(dg_summarise(datasets = list(iris = iris, mtcars = mtcars)))
```

    # A tibble: 2 × 7
      dataset size_kb n_vars n_numeric n_non_numeric n_rows prop_missing
    * <chr>     <dbl>  <int>     <int>         <int>  <int>        <dbl>
    1 iris       7.09      5         4             1    150            0
    2 mtcars     7.04     11        11             0     32            0

## A complete workflow

Because every step returns something the next one can consume, the whole
“find → judge → fetch” pipeline can be written as a single pipe. See how
the table flows from one step to the next without any intermediate
variables:

``` r

# Find a dataset, take its first id, pull it into a table and read its schema.
dg_list_datasets(q = "recharge électrique", schema_only = TRUE, n = 5) |>
  pull(id) |>
  head(1) |>
  dg_pull_dataset() |>
  dg_schema()
```

    Rows: 308 Columns: 42
    ── Column specification ────────────────────────────────────────────────────────
    Delimiter: ","
    chr  (1): date_realisation_diagnostic
    dbl (14): date_objectifs, code_commune_insee, code_iris_insee, existant_nb_p...
    lgl (27): date_adoption_sdirve, existant_nb_moyen_recharges, existant_duree_...

    ℹ Use `spec()` to retrieve the full column specification for this data.
    ℹ Specify the column types or set `show_col_types = FALSE` to quiet this message.

    # A tibble: 36 × 5
       name                         title description                  type  example
       <chr>                        <chr> <chr>                        <chr> <chr>
     1 date_realisation_diagnostic  <NA>  Date de réalisation du diag… date  2021-0…
     2 date_adoption_sdirve         <NA>  Date d'adoption du schéma d… date  2021-0…
     3 date_objectifs               <NA>  Date fixée pour l'atteinte … date  2023-0…
     4 code_commune_insee           <NA>  Code INSEE de chacune des c… stri… 23150
     5 code_iris_insee              <NA>  Code de chaque IRIS couvert… stri… 2A0040…
     6 existant_nb_pdc_intervalle_1 <NA>  Diagnostic - Nombre de poin… inte… 12
     7 existant_nb_pdc_intervalle_2 <NA>  Diagnostic - Nombre de poin… inte… 12
     8 existant_nb_pdc_intervalle_3 <NA>  Diagnostic - Nombre de poin… inte… 12
     9 existant_nb_pdc_intervalle_4 <NA>  Diagnostic - Nombre de poin… inte… 12
    10 existant_nb_moyen_recharges  <NA>  Diagnostic - Nombre moyen d… numb… 89
    # ℹ 26 more rows

[`dg_pull_dataset()`](https://astamm.github.io/datagouv/reference/dg_pull_dataset.md)
always returns a single tibble (a ZIP yields its first parseable file),
so the pipe keeps flowing whether or not the dataset is an archive —
[`dg_schema()`](https://astamm.github.io/datagouv/reference/dg_schema.md)
and
[`dg_refetch()`](https://astamm.github.io/datagouv/reference/dg_refetch.md)
read the table’s stable id from its attribute automatically. The same id
lets you reproduce the exact table later in a fresh session, no matter
how the catalog changes in the meantime:

``` r

tbl <- dg_list_datasets(q = "recharge électrique", schema_only = TRUE, n = 5) |>
  pull(id) |>
  head(1) |>
  dg_pull_dataset()
```

    Rows: 308 Columns: 42
    ── Column specification ────────────────────────────────────────────────────────
    Delimiter: ","
    chr  (1): date_realisation_diagnostic
    dbl (14): date_objectifs, code_commune_insee, code_iris_insee, existant_nb_p...
    lgl (27): date_adoption_sdirve, existant_nb_moyen_recharges, existant_duree_...

    ℹ Use `spec()` to retrieve the full column specification for this data.
    ℹ Specify the column types or set `show_col_types = FALSE` to quiet this message.

``` r

# Save the stable address, then re-fetch the exact same table later.
tbl_id <- dg_table_id(tbl)
again <- dg_refetch(tbl_id)
```

    Rows: 308 Columns: 42
    ── Column specification ────────────────────────────────────────────────────────
    Delimiter: ","
    chr  (1): date_realisation_diagnostic
    dbl (14): date_objectifs, code_commune_insee, code_iris_insee, existant_nb_p...
    lgl (27): date_adoption_sdirve, existant_nb_moyen_recharges, existant_duree_...

    ℹ Use `spec()` to retrieve the full column specification for this data.
    ℹ Specify the column types or set `show_col_types = FALSE` to quiet this message.

``` r

identical(again, tbl)
```

    [1] TRUE

The table id is the key to reproducibility: save `tbl_id`, and
`dg_refetch(tbl_id)` returns the same table again, regardless of
filename reorganisation or later edits to the dataset on the platform.
