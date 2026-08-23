# datagouv

`datagouv` is an R client for the public API of
[data.gouv.fr](https://www.data.gouv.fr), the French government’s open
data platform. It helps you *find* a dataset that matches your
interests, *judge* whether it is usable, *download* it, and later
*re-fetch the exact same table* reproducibly. Requests are built on top
of the [`httr2`](https://httr2.r-lib.org) package.

## Installation

``` r

# From GitHub once the package is published
# remotes::install_github("astamm/datagouv")
```

## Try it in seconds

The examples below hit the live data.gouv.fr API and show real results.

Find datasets matching a topic —
[`dg_list_datasets()`](https://astamm.github.io/datagouv/reference/dg_list_datasets.md)
searches titles and descriptions server-side:

``` r

library(datagouv)

hits <- dg_list_datasets(q = "vélo", n = 5)
hits[, c("title", "formats", "n_resources", "has_table", "has_schema")]
#> # A tibble: 5 × 5
#>   title                                 formats n_resources has_table has_schema
#>   <chr>                                 <chr>         <int> <lgl>     <lgl>     
#> 1 Stations du réseau vélo libre-servic… csv, g…           9 TRUE      FALSE     
#> 2 Comptages vélo à Nantes par Place au… csv, j…           2 TRUE      FALSE     
#> 3 Arceau vélo                           arcgis…          16 TRUE      FALSE     
#> 4 Stationnements vélo                   csv               1 TRUE      TRUE      
#> 5 Prime vélo                            csv, j…           2 TRUE      FALSE
```

`id` is the stable identifier you use to download; `has_schema` tells
you whether the dataset declares per-column documentation (see below).
You can restrict the catalog to datasets that carry at least one
resource in a given format — e.g. only the more compact `parquet` files,
which are quicker to download:

``` r

parquet_only <- dg_list_datasets(format = "parquet", n = 5)
parquet_only$formats
#> [1] "csv, json, ld+json, n3, parquet, rdf+xml, turtle, vnd.openxmlformats-officedocument.spreadsheetml.sheet"           
#> [2] "csv, csv.gz, geojson, parquet"                                                                                     
#> [3] "parquet"                                                                                                           
#> [4] "csv, gpx+xml, json, ld+json, n3, octet-stream, parquet, plain, rdf+xml, turtle, vnd.google-earth.kml+xml, xls, zip"
#> [5] "parquet"
```

Download a dataset and inspect it. The result is a single table whose
stable address is attached as an `id` attribute:

``` r

tbl <- dg_pull_dataset("6397c0ff56d3963118a18345")     # C.vélo bike stations
head(tbl[, 1:6])
#> # A tibble: 6 × 6
#>   station_id name                  physical_configuration    lat    lon altitude
#>        <dbl> <chr>                 <chr>                   <dbl>  <dbl> <chr>   
#> 1          4 04 UCA - Campus Céze… REGULAR                4.58e8 3.11e7 0.0     
#> 2          7 07 - Delille          REGULAR                4.58e7 3.09e5 0.0     
#> 3          8 08A - Gaillard        REGULAR                4.58e7 3.08e6 0.0     
#> 4          9 09 - Chamalières Mai… REGULAR                4.58e7 3.07e6 0.0     
#> 5         14 14 - Les Carmes       REGULAR                4.58e7 3.09e6 0.0     
#> 6         19 19 - Amboise          REGULAR                4.58e7 3.09e6 0.0
dg_table_id(tbl)
#> [1] "https://www.data.gouv.fr/datasets/6397c0ff56d3963118a18345#01f5b3da-8d58-42c6-a07d-202538ad6672"
```

Judge whether the columns mean what you think.
[`dg_schema()`](https://astamm.github.io/datagouv/reference/dg_schema.md)
resolves the dataset’s declared schema and returns human-readable column
documentation (pass the table directly — its id is read automatically):

``` r

# Find a schema-documented dataset, then look at its documented columns.
irve <- dg_pull_dataset("6a84778d27ac6d44d5fabe1f")     # IRVE charging points
dg_schema(irve)[, c("name", "description", "type", "example")]
#> # A tibble: 40 × 4
#>    name                  description                               type  example
#>    <chr>                 <chr>                                     <chr> <chr>  
#>  1 nom_amenageur         "La dénomination sociale du nom de l'amé… stri… Sociét…
#>  2 siren_amenageur       "Le numero SIREN de l'aménageur issue de… stri… 130025…
#>  3 contact_amenageur     "Adresse courriel de l'aménageur. Favori… stri… contac…
#>  4 nom_operateur         "La dénomination sociale de l'opérateur.… stri… Sociét…
#>  5 contact_operateur     "Adresse courriel de l'opérateur. Favori… stri… contac…
#>  6 telephone_operateur   "Numéro de téléphone permettant de conta… stri… 011111…
#>  7 nom_enseigne          "Le nom commercial du réseau."            stri… Réseau…
#>  8 id_station_itinerance "L'identifiant de la station délivré sel… stri… FRA68P…
#>  9 id_station_local      "Identifiant de la station utilisé local… stri… 01F2KM…
#> 10 nom_station           "Le nom de la station."                   stri… Picpus…
#> # ℹ 30 more rows
```

Re-fetch the exact same table later, reproducibly, from its stored id —
no matter how the catalog changes underneath you:

``` r

again <- dg_refetch(tbl)

identical(again, tbl)
#> [1] TRUE
```

And compute summary metrics — size, columns, rows and missing-value rate
— on one table or several at once:

``` r

dg_summarise(datasets = list(iris = iris, mtcars = mtcars))
#> # A tibble: 2 × 7
#>   dataset size_kb n_vars n_numeric n_non_numeric n_rows prop_missing
#> * <chr>     <dbl>  <int>     <int>         <int>  <int>        <dbl>
#> 1 iris       7.09      5         4             1    150            0
#> 2 mtcars     7.04     11        11             0     32            0
```

## Supported formats

[`dg_pull_dataset()`](https://astamm.github.io/datagouv/reference/dg_pull_dataset.md)
downloads the first tabular resource of a dataset among CSV, CSV.GZ,
XLS, XLSX, PARQUET, TSV, TXT and JSON, and returns the parsed table as a
single tibble. A ZIP resource is unpacked and its first parseable file
is returned by default; `all_files = TRUE` keeps every contained file in
one of these formats as a named list — one element per file. The
delimiter of CSV/TXT resources is auto-detected (comma, semicolon, tab,
pipe, …), so both standard and European-style (semicolon/comma-decimal)
files are handled without special configuration.

The discovery catalog
([`dg_list_datasets()`](https://astamm.github.io/datagouv/reference/dg_list_datasets.md))
is restricted to the official tabular formats data.gouv.fr itself
indexes (`csv`, `csv.gz`, `xls`, `xlsx`, `parquet`), so every listed
dataset is in principle openable as a table. Use the `format` argument
to narrow the catalog to datasets with a resource in a specific format.
Direct pulls additionally accept `tsv`, `txt` and `json` resources.

See the
[vignette](https://astamm.github.io/datagouv/articles/datagouv.html) for
the full workflow and API reference.

## Disclaimer

This package is not affiliated with or endorsed by data.gouv.fr. It is
an independent project, and the authors are not responsible for the
content of the datasets it indexes. This first version is a proof of
concept and may contain bugs. Please report any issues on the [GitHub
repository](https://github.com/astamm/datagouv/issues).

This package is the result of a joint effort initiated during the French
[Finist’R](https://stateofther.pages-forge.inrae.fr/finistr2026/)
bootcamp which was held in Roscoff in August 2026. It served as a
complex task to benchmark R package development assisted by AI. The
refinements that came up during the bootcamp were made with the
assistance of `deepseek-v4-flash` as provided by Albert API, the French
government’s AI platform. The author is grateful to the Finist’R
organizers and the Albert API team for their support and guidance.
