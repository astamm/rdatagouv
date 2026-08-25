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
[`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md)
searches titles and descriptions server-side:

``` r

library(datagouv)

hits <- dg_find_datasets(q = "vélo", n = 5)
hits[, c("title", "id", "organization", "quality_score", "views")]
#> # A tibble: 5 × 5
#>   title                                   id    organization quality_score views
#>   <chr>                                   <chr> <chr>                <dbl> <int>
#> 1 "Statistiques de subventions d’achat d… 63a3… ile-de-fran…         0.889  7137
#> 2 "Fréquentation mesurée dans les Parkin… 63a3… ile-de-fran…         0.889  7955
#> 3 "Nombre de places de stationnement vél… 67ca… ecolab-1             0.889  2252
#> 4 "Vélib - Vélos et bornes - Disponibili… 5a4e… ville-de-pa…         0.889 16121
#> 5 "Plan Vélo 2021-2026"                   6271… ville-de-pa…         0.778  8559
```

`id` is the stable identifier you use to download; `quality_score` and
`views` are among the rich per-dataset metadata the v2 search API embeds
inline (see `license`, `access_type`, `frequency`,
`temporal_start`/`end` and `featured` too). Because v2 search does not
inline a dataset’s resources, the resource-based columns `n_resources`,
`formats`, `has_table` and `has_schema` are `NA` by default; pass
`resources = TRUE` to opt into the per-dataset resource fetch and fill
them exactly. `schema_only = TRUE` forces that fetch (and tells you
about it) so the filter works out of the box. You can restrict the
catalog to datasets that carry at least one resource in a given format —
e.g. only the more compact `parquet` files, which are quicker to
download:

``` r

parquet_only <- dg_find_datasets(format = "parquet", n = 5)
parquet_only$title
#> [1] "Bases statistiques communale, départementale et régionale de la délinquance enregistrée par la police et la gendarmerie nationales "
#> [2] "Géolocalisation des établissements du répertoire SIRENE-pour les études statistiques"                                               
#> [3] "Bureaux de vote et adresses de leurs électeurs"                                                                                     
#> [4] "Base Sirene des entreprises et de leurs établissements (SIREN, SIRET)"                                                              
#> [5] "Données sur la localisation et l’accès de la population aux équipements"
```

You can also narrow a search to a single producer. Pass the producer’s
exact name or slug — it is resolved to its stable id for you — or look
producers up first with
[`dg_find_organization()`](https://astamm.github.io/rdatagouv/reference/dg_find_organization.md)
to see which exist and how their names are spelled:

``` r

orgs <- dg_find_organization(q = "SNCF")
orgs[, c("id", "name", "datasets")]
#> # A tibble: 17 × 3
#>    id                       name                                        datasets
#>    <chr>                    <chr>                                          <int>
#>  1 534fffb0a3a7292c64a78115 SNCF                                             183
#>  2 568e5e9488ee38033aaf0bf4 Île-de-France Mobilités                           97
#>  3 5d823fd98b4c411e38e820b4 Fluo Grand Est                                    50
#>  4 5db983ac8b4c4167f275d526 AlertesRER                                         1
#>  5 5d0b7e3f6f44412d6d301778 Etablissement public d'aménagement Bordeau…        1
#>  6 66f6b1c0668db6794d377dfb SFERIS                                             1
#>  7 5a2023c388ee383e1dea3b3f Mairie de St NICOLAS DE REDON                      1
#>  8 5f8581d1414580f029f22ec7 Isomaps                                            0
#>  9 693fcf26eb48b48f67a2fbf6 SNCF Connect                                       0
#> 10 679df2bff83a64dbfdf3ea6b Fleury-sur-Orne                                   37
#> 11 6788e513830b33588b9529c2 SNCF Gares & Connexions                            0
#> 12 5b87edb0634f41368b820b86 Toucan Toco                                        0
#> 13 5d00c25a8b4c417012fd62c2 Tictactrip                                         0
#> 14 5d6a3fef634f417b657b2279 viaTransit                                         0
#> 15 6a0de9ce491d351c8f8764f0 MaxRail                                            0
#> 16 5d56018d6f444123160357a1 Kombo                                              0
#> 17 6a21d93a76e2d715124ebcc8 Trayn                                              0

sncf <- dg_find_datasets(organization = "sncf", n = 5)
sncf$title
#> [1] "HORAIRES SNCF"                                        
#> [2] "Fichier de formes des voies du Réseau Ferré National" 
#> [3] "Horaires des gares"                                   
#> [4] "Liste des gares"                                      
#> [5] "Fichier de formes des lignes du Réseau Ferré National"
```

You can likewise narrow a search to a curated *theme*. Discover which
themes exist with
[`dg_find_topics()`](https://astamm.github.io/rdatagouv/reference/dg_find_topics.md)
(which also reports how many elements each groups), then filter the
catalog by a theme’s id:

``` r

topics <- dg_find_topics(q = "mobilité", n = 3)
topics[, c("id", "name", "n_elements")]
#> # A tibble: 3 × 3
#>   id                       name                                       n_elements
#>   <chr>                    <chr>                                           <int>
#> 1 6811e889b455bf5bbde45517 Indicateurs du tableau de bord des mobili…         27
#> 2 68da7823bc643f6ea5cae5a0 🚎 Tarification sociale/solidaire des tran…          0
#> 3 673cba35210c475e77ef3e38 Catalogue des données sur l'immobilier lo…        135

mobility <- dg_find_datasets(topic = topics$id[1], n = 5)
mobility$title
#> [1] "Nombre de places de stationnement vélo "                                  
#> [2] "Flux domicile-travail selon le mode de transport principal utilisé"       
#> [3] "Distance domicile-travail moyenne, selon le mode de déplacement principal"
#> [4] "Nombre de stations de transports en commun selon le type de réseau"       
#> [5] "Nombre de flux domicile-travail"
```

Glimpse a dataset’s health and engagement metadata before deciding to
pull it.
[`dg_glimpse()`](https://astamm.github.io/rdatagouv/reference/dg_glimpse.md)
surfaces the v2-inline `quality` score and flags, `metrics` (views,
downloads, followers, …) and context that the fetch path does not
expose:

``` r

g <- dg_glimpse("6a6be5976a05df136d48fb7a")
g$quality
#> $score
#> [1] 0.5555556
#> 
#> $flags
#> $flags$license
#> [1] TRUE
#> 
#> $flags$temporal_coverage
#> [1] FALSE
#> 
#> $flags$spatial
#> [1] FALSE
#> 
#> $flags$update_frequency
#> [1] FALSE
#> 
#> $flags$dataset_description_quality
#> [1] TRUE
#> 
#> $flags$has_resources
#> [1] TRUE
#> 
#> $flags$has_open_format
#> [1] TRUE
#> 
#> $flags$all_resources_available
#> [1] TRUE
#> 
#> $flags$resources_documentation
#> [1] TRUE
g$metrics
#> $views
#> [1] 549
#> 
#> $resources_downloads
#> [1] 39
#> 
#> $followers
#> [1] 0
#> 
#> $discussions
#> [1] 0
#> 
#> $reuses
#> [1] 0
#> 
#> $dataservices
#> [1] 2
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
[`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md)
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

[`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
downloads the first tabular resource of a dataset among CSV, CSV.GZ,
XLS, XLSX, PARQUET, TSV, TXT and JSON, and returns the parsed table as a
single tibble. A ZIP resource is unpacked and its first parseable file
is returned by default; `all_files = TRUE` keeps every contained file in
one of these formats as a named list — one element per file. The
delimiter of CSV/TXT resources is auto-detected (comma, semicolon, tab,
pipe, …), so both standard and European-style (semicolon/comma-decimal)
files are handled without special configuration.

The discovery catalog
([`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md))
is restricted to the official tabular formats data.gouv.fr itself
indexes (`csv`, `csv.gz`, `xls`, `xlsx`, `parquet`), so every listed
dataset is in principle openable as a table. Use the `format` argument
to narrow the catalog to datasets with a resource in a specific format
(the v2 search API matches several formats as a server-side union). The
exact `n_resources`/`formats`/`has_table`/`has_schema` resource columns
are populated by passing `resources = TRUE`. Direct pulls additionally
accept `tsv`, `txt` and `json` resources.

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
