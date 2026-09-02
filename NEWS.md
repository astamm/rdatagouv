# rdatagouv 0.1.0

This is the first release of **rdatagouv**, an R client for the public API of
data.gouv.fr, the French government's open data platform. Download and install
the package to explore, download and reuse public datasets from your terminal.

The package is organised around the workflow it supports:

- **Find** a dataset that matches your interests with `dg_find_datasets()`
  (full-text and schema-only search, and filters such as `organization`,
  `topic`, `geozone`, `license` or `format`) and identify its producer with
  `dg_find_organization()`, or browse data.gouv's curated themes with
  `dg_find_topics()`.
- **Judge** whether a dataset is usable: `dg_glimpse()` surfaces quality
  scores, download counts and coverage metadata, and `dg_schema()` returns the
  documented columns of the data's declared schema so you can check the
  variables before downloading.
- **Fetch** the data: `dg_pull_dataset()` downloads a dataset's tabular
  resources (CSV, XLS/XLSX, Parquet, ZIP, ...) into tidy tibbles, optionally
  keeping only fully numeric columns or forcing the type of specific columns.
- **Reuse** it reproducibly: each pulled table carries a stable identifier,
  read with `dg_table_id()` and used by `dg_refetch()` to re-download the exact
  same table later.
- **Summarise** a table with `dg_summary()` (size, number of columns, rows,
  missing-value rate), or many tables at once with `dg_summarise()`.
- **Diagnose** parsing with `dg_problems()`, which returns the rows and columns
  that could not be read as expected.

The README is a good starting point, and the package vignette walks through
each function with worked examples.
