# Finding, judging and re-fetching French open data with rdatagouv

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

## The problem rdatagouv solves

`rdatagouv` is a small R client for the public API of
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

`rdatagouv` addresses all four. Its functions are organised around that
workflow:

| Step | Function |
|----|----|
| Find / search the catalog | [`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md), [`dg_find_organization()`](https://astamm.github.io/rdatagouv/reference/dg_find_organization.md), [`dg_find_topics()`](https://astamm.github.io/rdatagouv/reference/dg_find_topics.md) |
| Judge documented columns | [`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md) |
| Download tabular resources | [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md) |
| Inspect parsing problems | [`dg_problems()`](https://astamm.github.io/rdatagouv/reference/dg_problems.md) |
| Summarise table contents | [`dg_summary()`](https://astamm.github.io/rdatagouv/reference/dg_summary.md), [`dg_summarise()`](https://astamm.github.io/rdatagouv/reference/dg_summarise.md) |
| Re-fetch a table reproducibly | [`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md) |

The approach mirrors what several US cities propose (e.g.
[`nycOpenData`](https://github.com/ropensci/nycOpenData) for New York),
but tailored to the data.gouv.fr API.

## Finding datasets

[`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md)
returns a tibble with one row per dataset:

``` r

library(rdatagouv)

datasets <- dg_find_datasets(n = 20)
head(datasets)
```

    # A tibble: 6 × 21
      title id    description slug  organization license quality_score quality_flags
      <chr> <chr> <chr>       <chr> <chr>        <chr>           <dbl> <chr>
    1 "Rép… 5c34… "*Mise à j… repe… ministere-d… lov2            1     license, tem…
    2 "Bas… 5369… "Pour chaq… base… ministere-d… fr-lo           1     license, tem…
    3 "Ser… 5369… "La Base d… serv… premier-min… fr-lo           1     license, tem…
    4 "Fic… 605d… "Les fichi… fich… ministeres-… lov2            0.556 license, upd…
    5 "Don… 5e7e… "**Dans un… donn… sante-publi… lov2            0.889 license, spa…
    6 "Bas… 621d… "Visualise… base… ministere-d… lov2            1     license, tem…
    # ℹ 13 more variables: views <int>, resources_downloads <int>,
    #   access_type <chr>, frequency <chr>, spatial_granularity <chr>,
    #   temporal_start <chr>, temporal_end <chr>, archived <lgl>, featured <lgl>,
    #   n_resources <int>, formats <list>, has_table <lgl>, has_schema <lgl>

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
  [`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md).

The search endpoint does not inline each dataset’s resources, so the
resource-based columns `n_resources`, `formats`, `has_table` and
`has_schema` are `NA` unless you opt in with `resources = TRUE` (which
costs one extra request per dataset):

``` r

cycle <- dg_find_datasets(q = "vélo", n = 10, resources = TRUE)
cycle[, c("title", "n_resources", "has_table", "has_schema")]
```

    # A tibble: 10 × 4
       title                                        n_resources has_table has_schema
       <chr>                                              <int> <lgl>     <lgl>
     1 "Statistiques de subventions d’achat de vél…           2 TRUE      FALSE
     2 "Fréquentation mesurée dans les Parkings Vé…           2 TRUE      FALSE
     3 "Vélib - Vélos et bornes - Disponibilité te…           5 TRUE      FALSE
     4 "Nombre de places de stationnement vélo "              5 TRUE      FALSE
     5 "Plan Vélo 2021-2026"                                  4 TRUE      FALSE
     6 "Aménagements vélo en Île-de-France"                  21 TRUE      FALSE
     7 "Comptages vélo et piétons"                            5 TRUE      FALSE
     8 "Stationnement vélo en Île-de-France"                  8 TRUE      FALSE
     9 "Stationnement vélo en Île-de-France"                  8 TRUE      FALSE
    10 "Aménagements vélo en Île-de-France"                  24 TRUE      FALSE     

The discovery catalog is **restricted to data.gouv’s official tabular
formats** (`csv`, `csv.gz`, `xls`, `xlsx`, `parquet`), so every listed
dataset is in principle openable as a table — `has_table` is almost
always `TRUE`. This is a deliberate choice: JSON, TSV and TXT resources
can still be parsed when you address them directly (see
[`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)),
but they are not guaranteed tabular and are left out of the catalog so
that “the catalog” stays a reliable list of tables.

### Restricting to documented datasets

Because descriptions live in schemas and only a fraction of datasets
declare one,
[`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md)
only helps on a subset of the catalog. You can target that subset
directly. v2 has no boolean “declares a schema” server-side filter, so
`schema_only` filters client-side on `has_schema`, which needs the
per-dataset resource fetch — so calling it forces `resources = TRUE`
(with a message about the extra requests) and the filter just works:

``` r

documented <- dg_find_datasets(schema_only = TRUE, n = 10)
```

    Forcing `resources = TRUE` because `schema_only = TRUE` selects on
    `has_schema`, which needs the per-dataset resource fetch.

``` r

documented[, c("title", "has_schema")]
```

    # A tibble: 0 × 2
    # ℹ 2 variables: title <chr>, has_schema <lgl>

### Restricting to specific formats

You can narrow the catalog to datasets that carry a resource in a format
of your choice with the `format` argument. This is especially useful to
find lighter files (e.g. `parquet`) that download faster than their CSV
twins:

``` r

parquet <- dg_find_datasets(format = "parquet", n = 10)
parquet[, c("title", "formats")]
```

    # A tibble: 10 × 2
       title                                                                 formats
       <chr>                                                                 <list>
     1 "Bases statistiques communale, départementale et régionale de la dél… <NULL>
     2 "Géolocalisation des établissements du répertoire SIRENE-pour les ét… <NULL>
     3 "Bureaux de vote et adresses de leurs électeurs"                      <NULL>
     4 "Base Sirene des entreprises et de leurs établissements (SIREN, SIRE… <NULL>
     5 "Données sur la localisation et l’accès de la population aux équipem… <NULL>
     6 "Base sur la qualité et la sécurité des soins (anciennement Scope Sa… <NULL>
     7 "Données des élections agrégées"                                      <NULL>
     8 "Paris 2024 - Sites de compétition"                                   <NULL>
     9 "Agrégation des fichiers des personnes décédées"                      <NULL>
    10 "Données financières détaillées des entreprises (format parquet)"     <NULL> 

Multiple formats can be requested at once; each is queried server-side
and the results are combined.

### Finding a specific organization’s datasets

`dg_find_datasets(organization =)` can address a producer by its 24-hex
id, its `name`, or its `slug`.
[`dg_find_organization()`](https://astamm.github.io/rdatagouv/reference/dg_find_organization.md)
lists the organizations known to data.gouv so you can discover which one
you want and get its stable id:

``` r

orgs <- dg_find_organization(q = "SNCF")
orgs[, c("name", "slug", "datasets")]
```

    # A tibble: 17 × 3
       name                                                      slug       datasets
       <chr>                                                     <chr>         <int>
     1 SNCF                                                      sncf            183
     2 Île-de-France Mobilités                                   ile-de-fr…       97
     3 Fluo Grand Est                                            fluo-gran…       50
     4 AlertesRER                                                alertesrer        1
     5 Etablissement public d'aménagement Bordeaux Euratlantique etablisse…        1
     6 SFERIS                                                    sferis            1
     7 Mairie de St NICOLAS DE REDON                             mairie-de…        1
     8 Isomaps                                                   isomaps           0
     9 SNCF Connect                                              sncf-conn…        0
    10 Fleury-sur-Orne                                           fleury-su…       37
    11 SNCF Gares & Connexions                                   sncf-gare…        0
    12 Toucan Toco                                               toucan-to…        0
    13 Tictactrip                                                tictactrip        0
    14 viaTransit                                                viatransit        0
    15 MaxRail                                                   maxrail           0
    16 Kombo                                                     kombo             0
    17 Trayn                                                     trayn             0

The slug resolves to the same datasets as the corresponding id — pass
either to
[`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md):

``` r

sncf <- dg_find_datasets(organization = "sncf", n = 10)
sncf[, c("title", "organization")]
```

    # A tibble: 10 × 2
       title                                                 organization
       <chr>                                                 <chr>
     1 HORAIRES SNCF                                         sncf
     2 Fichier de formes des voies du Réseau Ferré National  sncf
     3 Horaires des gares                                    sncf
     4 Liste des gares                                       sncf
     5 Fichier de formes des lignes du Réseau Ferré National sncf
     6 Fréquentation en gares                                sncf
     7 Gares de voyageurs                                    sncf
     8 Points de vente SNCF                                  sncf
     9 Liste des passages à niveau                           sncf
    10 Tarifs TGV INOUI et OUIGO                             sncf        

### Finding datasets grouped under a theme

Beyond producers, data.gouv curates datasets into *themes* (topics) such
as “Mobilité”, “Environnement” or “Énergie”.
[`dg_find_topics()`](https://astamm.github.io/rdatagouv/reference/dg_find_topics.md)
lists these themes — including how many elements each groups — so you
can discover one and get its stable 24-hex id:

``` r

topics <- dg_find_topics(q = "mobilité", n = 5)
topics[, c("name", "n_elements")]
```

    # A tibble: 5 × 2
      name                                                                n_elements
      <chr>                                                                    <int>
    1 Indicateurs du tableau de bord des mobilités durables                       28
    2 🚎 Tarification sociale/solidaire des transports publics | Attribut…          0
    3 Catalogue des données sur l'immobilier logistique à l'échelle nati…        135
    4 Véhicules électriques                                                       27
    5 Lutte contre la vacance des logements                                        8

Pass a theme’s id to `dg_find_datasets(topic =)` to narrow a catalog
search to datasets grouped under it (the same single-valued server-side
filter that `organization`/`geozone` use; it takes a topic id, not a
name/slug):

``` r

mobility <- dg_find_datasets(topic = topics$id[1], n = 10)
mobility[, c("title", "organization")]
```

    # A tibble: 10 × 2
       title                                                            organization
       <chr>                                                            <chr>
     1 "Nombre de places de stationnement vélo "                        ecolab-1
     2 "Flux domicile-travail selon le mode de transport principal uti… ecolab-1
     3 "Distance domicile-travail moyenne, selon le mode de déplacemen… ecolab-1
     4 "Nombre de stations de transports en commun selon le type de ré… ecolab-1
     5 "Nombre de flux domicile-travail"                                ecolab-1
     6 "Nombre de places de stationnement vélo pour 1000 hab."          ecolab-1
     7 "Linéaire d'aménagements cyclables"                              ecolab-1
     8 "Part des flux domicile-travail"                                 ecolab-1
     9 "Nombre de points de recharge pour véhicules électriques ouvert… ecolab-1
    10 "Part des ménages disposant au moins d’une voiture (taux de mot… ecolab-1    

By default
[`dg_find_topics()`](https://astamm.github.io/rdatagouv/reference/dg_find_topics.md)
reports `n_elements` — the theme’s declared total element count
(datasets, reuses, dataservices, …). To see how that total breaks down
by kind, pass `elements = TRUE` (costing one extra request per topic);
the `n_datasets`/`n_dataservices`/`n_reuses` columns are `NA` otherwise.

## Judging whether a dataset is usable

A quick way to judge a dataset before pulling it is
[`dg_glimpse()`](https://astamm.github.io/rdatagouv/reference/dg_glimpse.md).
It takes a dataset id — or, like the other functions, a pulled table
(its id is read automatically) — and returns a named list of the
v2-inline metadata the fetch path does not surface directly: the
dataset’s `quality` score and flags, its usage `metrics`, and its
`context` (license, frequency, coverage, …):

``` r

glimpse <- dg_glimpse("6a6be5976a05df136d48fb7a")
glimpse$quality$score             # 0..1 quality score
```

    [1] 0.5555556

``` r

glimpse$metrics$views             # how often the dataset is looked at
```

    [1] 625

``` r

glimpse$context$license           # e.g. "open" / "notspecified"
```

    [1] "notspecified"

The judged usefulness of a dataset also hinges on whether the columns
mean what you think they mean. That information comes from the
producer’s *schema* on schema.data.gouv.fr.
[`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md)
takes a table (its id is read automatically) or a composed table id and
returns the documented fields:

``` r

# schema_only filters client-side, so request a batch and take the first hit.
documented <- dg_find_datasets(schema_only = TRUE, n = 100)
```

    Forcing `resources = TRUE` because `schema_only = TRUE` selects on
    `has_schema`, which needs the per-dataset resource fetch.

``` r

table_id <- documented$id[!is.na(documented$id)][[1]]

# Pull it, then inspect the schema of the returned table.
tbl <- dg_pull_dataset(table_id)
schema <- dg_schema(tbl)

# Human-readable titles and descriptions of every column:
head(schema)
```

    # A tibble: 6 × 5
      name                title description                            type  example
      <chr>               <chr> <chr>                                  <chr> <chr>
    1 nom_amenageur       <NA>  La dénomination sociale du nom de l'a… stri… Sociét…
    2 siren_amenageur     <NA>  Le numero SIREN de l'aménageur issue … stri… 130025…
    3 contact_amenageur   <NA>  Adresse courriel de l'aménageur. Favo… stri… contac…
    4 nom_operateur       <NA>  La dénomination sociale de l'opérateu… stri… Sociét…
    5 contact_operateur   <NA>  Adresse courriel de l'opérateur. Favo… stri… contac…
    6 telephone_operateur <NA>  Numéro de téléphone permettant de con… stri… 011111…

The result is a tibble with one row per column and the columns `name`,
`title`, `description`, `type` and `example`, together with the schema’s
own `title` and `name` attached as attributes. Where the schema provides
no title or description (some producers document only some fields), the
corresponding cell is `NA`.

If the resource carries no schema pointer,
[`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md)
returns `NULL` with a message explaining that no variable documentation
is available.

## Downloading data

[`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
downloads the first parseable tabular resource of a dataset and returns
a **single tibble**:

``` r

tbl <- dg_pull_dataset("6397c0ff56d3963118a18345")
head(tbl)
```

    # A tibble: 6 × 16
      station_id name  physical_configuration   lat   lon altitude address post_code
           <int> <chr> <chr>                  <dbl> <dbl>    <dbl> <chr>   <chr>
    1          4 04 U… REGULAR                   NA    NA       NA 26 Ave… 63170
    2          7 07 -… REGULAR                   NA    NA       NA Place … 63000
    3          8 08A … REGULAR                   NA    NA       NA 29 Rue… 63000
    4          9 09 -… REGULAR                   NA    NA       NA Rue Ch… 63400
    5         14 14 -… REGULAR                   NA    NA       NA 12 Pla… 63000
    6         19 19 -… REGULAR                   NA    NA       NA 25-13 … 63000
    # ℹ 8 more variables: capacity <int>, is_charging_station <lgl>,
    #   geofenced_capacity <lgl>, rental_methods <chr>, is_virtual_station <lgl>,
    #   short_name <chr>, rental_uris <chr>, point_geo <chr>

``` r

dg_table_id(tbl)
```

    [1] "https://www.data.gouv.fr/datasets/6397c0ff56d3963118a18345#01f5b3da-8d58-42c6-a07d-202538ad6672"

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
  [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
  skips non-parseable resources and falls back to the next tabular one
  instead of erroring.
- When a dataset offers the *same table* in several formats (same file
  name, different extension, e.g. `data.csv` vs `data.xlsx`), the
  lightest advertised file is downloaded so the pull is as small as
  possible; resources with distinct names keep their declared order.
- Every returned table carries its stable, unique address as an `id`
  attribute, readable with
  [`dg_table_id()`](https://astamm.github.io/rdatagouv/reference/dg_table_id.md).
- Column types are seeded from data.gouv’s own `csv-detective` profile
  by default (`use_tabular_types = TRUE`), then remaining inference is
  left to vroom. The profile is best-effort — it only exists for
  single-file resources indexed by the tabular service, so a missing
  profile (or a ZIP member) falls back to type inference; pass
  `use_tabular_types = FALSE` to disable seeding entirely. You can
  always force specific columns with `col_types = c(col_name = "Date")`
  (shorthand: `"character"`, `"double"`/`"numeric"`, `"integer"`,
  `"logical"`, `"Date"`, `"datetime"`, `"skip"`, `"guess"`; explicit
  `col_types` always win). This is handy when vroom guesses a type the
  data does not fully match — e.g. a mostly-padded ISO date column with
  a few non-padded stragglers like `2021-7-01`, which vroom would
  otherwise flag as a parsing issue; forcing `"Date"` turns those
  stragglers into `NA`.
- Any parsing issues vroom encountered are attached to the table as an
  `rdatagouv_problems` attribute instead of a noisy per-cell warning.
  Read them with `dg_problems(tbl)` (a data frame of `row`, `col`,
  `expected`, `actual`, or `NULL` when the table parsed cleanly).

## When pulling goes wrong: parsing issues

A table is *pulled* by guessing how each column should be read — its
type (integer, double, date, …) is inferred from the values it contains.
Real-world open data rarely cooperates perfectly: a column can hold
mixed content, and the guess can be wrong. This section explains how
`rdatagouv` surfaces those problems and how you can fix them.

### Detecting a parsing problem

While it reads a delimited file, vroom reports every cell it cannot
reconcile with the column type it committed to. Rather than blasting
these one-by-one as warnings, `rdatagouv` silences the noisy per-cell
messages and keeps the underlying record on the table, readable with
[`dg_problems()`](https://astamm.github.io/rdatagouv/reference/dg_problems.md):

``` r

# In-memory demo of the problems attribute. A real pull works the same way:
#   tbl <- dg_pull_dataset("<id>")
#   dg_problems(tbl)
try({
  # A column declared "double" but holding some non-numeric cells.
  csv <- tempfile(fileext = ".csv")
  writeLines(c("x,y", "1,2", "2,oops", "3,4"), csv)
  pr <- vroom::problems(vroom::vroom(csv, col_types = vroom::cols(
    x = "d", y = "d"
  )))
  pr[, c("row", "col", "expected", "actual")]
})
```

    Warning: One or more parsing issues, call `problems()` on your data frame for details,
    e.g.:
      dat <- vroom(...)
      problems(dat)

    # A tibble: 1 × 4
        row   col expected actual
      <int> <int> <chr>    <chr>
    1     3     2 a double oops  

A *clean* pull — one where every cell matched its inferred type —
returns `NULL` from
[`dg_problems()`](https://astamm.github.io/rdatagouv/reference/dg_problems.md);
a table with issues returns a data frame with one row per problem and
the columns `row`, `col`, `expected` and `actual`:

| Column     | Meaning                                              |
|------------|------------------------------------------------------|
| `row`      | 1-based row (of the file) where the problem occurred |
| `col`      | column name (or number) that could not be parsed     |
| `expected` | the type vroom had committed to (e.g. `a double`)    |
| `actual`   | the raw value that failed, e.g. `oops`               |

The attribute is only attached when there is something to report, so a
healthy table stays lightweight and ordinary data frames (not produced
by a pull) return `NULL`.

### A common trigger: mostly-padded ISO dates

A frequent real-world case is a date column such as `2021-07-01` that is
*padded* (two-digit month/day) for almost every row, with a few
non-padded stragglers like `2021-7-01` or `2024-11-5`. vroom sees
mostly-padded ISO dates, commits to a `Date` collector, and flags each
straggler as a parsing issue. The stragglers parse to `NA` and the
warning count is often large — the trigger that motivated this feature.
This is a *data* quality issue, not a bug in the pull.

### Solving it: forcing column types

You can take control of the guess with `col_types`, which overrides
vroom’s inference for the named columns (shorthand: `"character"`,
`"double"`/ `"numeric"`, `"integer"`, `"logical"`, `"Date"`,
`"datetime"`, `"skip"`, `"guess"`). Two ways to fix the mixed-date case:

1.  **Force the stragglers to text** with `"character"` — nothing is
    lost and no value becomes `NA`; you can parse the dates yourself
    afterwards. The IRVE charging-points dataset is a good real example:
    its `date_mise_en_service` and `date_maj` columns are mostly padded
    with a few stragglers like `2021-7-01`:

    ``` r

    tbl <- dg_pull_dataset("5448d3e0c751df01f85d0572",
      col_types = c(date_mise_en_service = "character", date_maj = "character"))
    dg_problems(tbl)          # NULL — nothing is flagged any more
    ```

2.  **Force `"Date"`** and accept that the stragglers become `NA` —
    right when a few unparsed dates are acceptable for your analysis:

    ``` r

    tbl <- dg_refetch(tbl,
      col_types = c(date_mise_en_service = "Date", date_maj = "Date"))
    ```

Both
[`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
and
[`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
accept `col_types` (including inside a ZIP with `all_files = TRUE`), so
you can correct the same table every time you re-fetch it:

``` r

# Pull the IRVE charging-points table once, inspect its parsing issues with
# dg_problems(), then re-fetch the same table with the mixed-date columns
# forced to text so nothing is flagged.
tbl <- dg_pull_dataset("5448d3e0c751df01f85d0572")
nrow(dg_problems(tbl))                    # how many mixed-date stragglers
```

    [1] 278

``` r

tbl <- dg_refetch(tbl,
  col_types = c(date_mise_en_service = "character", date_maj = "character"))
dg_problems(tbl)                          # NULL — clean re-fetch
```

    NULL

The general workflow is: pull, inspect with
[`dg_problems()`](https://astamm.github.io/rdatagouv/reference/dg_problems.md),
spot the offending column in `col`, choose a `col_types` entry that
matches how you intend to use the data, and re-pull or re-fetch. If the
problem is a non-numeric value inside a numeric column, forcing
`"character"` keeps the raw text; forcing `"double"` turns it into `NA`.
Either choice lets you move on with a table whose columns behave
predictably.

## Re-fetching the same table reproducibly

This is what makes your analysis reproducible over time. The table’s id
is a URI built from the platform’s own stable identifiers —
`https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>` (plus
`/<file>` for a file inside a ZIP). Unlike a human-readable title, this
address always resolves to the same table:

``` r

tbl <- dg_pull_dataset("6397c0ff56d3963118a18345")
table_id <- dg_table_id(tbl)
table_id
```

    [1] "https://www.data.gouv.fr/datasets/6397c0ff56d3963118a18345#01f5b3da-8d58-42c6-a07d-202538ad6672"

``` r

# Re-fetch the exact same table later:
again <- dg_refetch(tbl)
```

[`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
accepts the table id (URI) directly, so you can store it in a script or
a database and reproduce the pull without re-searching the catalog.

### Why a stable id beats a file name

Datasets on data.gouv are *living*: producers re-upload files, correct
typos, and re-run pipelines. The file a human-readable name or title
points at can therefore change between the day you pull it and the day
you re-run your analysis. The table id, by contrast, is a stable address
built from the platform’s own identifiers, and
[`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
uses it to get back **the same table you fetched originally** — not
whatever the resource happens to contain today.

To make this concrete with no network, imagine a producer’s `bikes.csv`
that you pulled last month, and the slightly updated file they publish
today:

``` r

# In-memory illustration of resource drift — no network, no rdatagouv calls.
# The file you pulled on day one.
pulled_last_month <- tibble::tibble(city = c("Caen", "Lyon"), bikes = c(42L, 17L))

# The same-named file, re-uploaded by the producer the next month.
published_today <- tibble::tibble(city = c("Caen", "Lyon"), bikes = c(43L, 18L))

# A lookup by file name gives you whatever is current now (drifted):
name_based <- published_today

# A lookup by the stable id saved at pull time gives you the table you
# actually analysed. In a real session that is exactly what happens:
#   saved_id <- dg_table_id(pulled)   # a stable URI, e.g.
#   # `https://www.data.gouv.fr/datasets/<id>#<resource>`
#   back <- dg_refetch(saved_id)      # -> pulled_last_month, not published_today
id_based <- pulled_last_month
```

The table id is what makes your analysis reproducible over time: save it
alongside your results, and the pull you ran is the pull a future
[`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
gets back — even if the file name, its contents, or the surrounding
catalog have drifted in the meantime. A file name captures only *where
something is now*; the stable id captures *what you actually observed*.

## Summarising datasets

[`dg_summary()`](https://astamm.github.io/rdatagouv/reference/dg_summary.md)
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

[`dg_summarise()`](https://astamm.github.io/rdatagouv/reference/dg_summarise.md)
applies
[`dg_summary()`](https://astamm.github.io/rdatagouv/reference/dg_summary.md)
to a collection of tables. It is flexible about its input, accepting:

- a named list of tibbles (each element is a single table),
- a named list of such lists, as returned by
  `dg_pull_dataset(all_files = TRUE)` (a ZIP may contribute several
  tables),
- a tibble from
  [`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md)
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
dg_find_datasets(q = "recharge électrique", schema_only = TRUE, n = 5) |>
  pull(id) |>
  head(1) |>
  dg_pull_dataset() |>
  dg_schema()
```

    Forcing `resources = TRUE` because `schema_only = TRUE` selects on
    `has_schema`, which needs the per-dataset resource fetch.

    # A tibble: 40 × 5
       name                  title description                         type  example
       <chr>                 <chr> <chr>                               <chr> <chr>
     1 nom_amenageur         <NA>  "La dénomination sociale du nom de… stri… Sociét…
     2 siren_amenageur       <NA>  "Le numero SIREN de l'aménageur is… stri… 130025…
     3 contact_amenageur     <NA>  "Adresse courriel de l'aménageur. … stri… contac…
     4 nom_operateur         <NA>  "La dénomination sociale de l'opér… stri… Sociét…
     5 contact_operateur     <NA>  "Adresse courriel de l'opérateur. … stri… contac…
     6 telephone_operateur   <NA>  "Numéro de téléphone permettant de… stri… 011111…
     7 nom_enseigne          <NA>  "Le nom commercial du réseau."      stri… Réseau…
     8 id_station_itinerance <NA>  "L'identifiant de la station déliv… stri… FRA68P…
     9 id_station_local      <NA>  "Identifiant de la station utilisé… stri… 01F2KM…
    10 nom_station           <NA>  "Le nom de la station."             stri… Picpus…
    # ℹ 30 more rows

[`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
always returns a single tibble (a ZIP yields its first parseable file),
so the pipe keeps flowing whether or not the dataset is an archive —
[`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md)
and
[`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
read the table’s stable id from its attribute automatically. The same id
lets you reproduce the exact table later in a fresh session, no matter
how the catalog changes in the meantime:

``` r

tbl <- dg_find_datasets(q = "recharge électrique", schema_only = TRUE, n = 5) |>
  pull(id) |>
  head(1) |>
  dg_pull_dataset()
```

    Forcing `resources = TRUE` because `schema_only = TRUE` selects on
    `has_schema`, which needs the per-dataset resource fetch.

``` r

# Save the stable address, then re-fetch the exact same table later.
tbl_id <- dg_table_id(tbl)
again <- dg_refetch(tbl_id)
identical(again, tbl)
```

    [1] TRUE

The table id is the key to reproducibility: save `tbl_id`, and
`dg_refetch(tbl_id)` returns the same table again, regardless of
filename reorganisation or later edits to the dataset on the platform.
