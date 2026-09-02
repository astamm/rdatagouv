# Changelog

## rdatagouv 0.1.0

This is the first release of **rdatagouv**, an R client for the public
API of data.gouv.fr, the French government’s open data platform.
Download and install the package to explore, download and reuse public
datasets from your terminal.

The package is organised around the workflow it supports:

- **Find** a dataset that matches your interests with
  [`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md)
  (full-text and schema-only search, and filters such as `organization`,
  `topic`, `geozone`, `license` or `format`) and identify its producer
  with
  [`dg_find_organization()`](https://astamm.github.io/rdatagouv/reference/dg_find_organization.md),
  or browse data.gouv’s curated themes with
  [`dg_find_topics()`](https://astamm.github.io/rdatagouv/reference/dg_find_topics.md).
- **Judge** whether a dataset is usable:
  [`dg_glimpse()`](https://astamm.github.io/rdatagouv/reference/dg_glimpse.md)
  surfaces quality scores, download counts and coverage metadata, and
  [`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md)
  returns the documented columns of the data’s declared schema so you
  can check the variables before downloading.
- **Fetch** the data:
  [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
  downloads a dataset’s tabular resources (CSV, XLS/XLSX, Parquet, ZIP,
  …) into tidy tibbles, optionally keeping only fully numeric columns or
  forcing the type of specific columns.
- **Reuse** it reproducibly: each pulled table carries a stable
  identifier, read with
  [`dg_table_id()`](https://astamm.github.io/rdatagouv/reference/dg_table_id.md)
  and used by
  [`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
  to re-download the exact same table later.
- **Summarise** a table with
  [`dg_summary()`](https://astamm.github.io/rdatagouv/reference/dg_summary.md)
  (size, number of columns, rows, missing-value rate), or many tables at
  once with
  [`dg_summarise()`](https://astamm.github.io/rdatagouv/reference/dg_summarise.md).
- **Diagnose** parsing with
  [`dg_problems()`](https://astamm.github.io/rdatagouv/reference/dg_problems.md),
  which returns the rows and columns that could not be read as expected.

The README is a good starting point, and the package vignette walks
through each function with worked examples.
