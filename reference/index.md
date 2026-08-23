# Package index

## Finding and downloading datasets

Find a dataset on data.gouv.fr, judge whether it is usable, and pull its
tabular resources into tidy tables.

- [`dg_list_datasets()`](https://astamm.github.io/datagouv/reference/dg_list_datasets.md)
  : List datasets available on data.gouv.fr
- [`dg_pull_dataset()`](https://astamm.github.io/datagouv/reference/dg_pull_dataset.md)
  : Download a dataset from data.gouv.fr
- [`dg_table_id()`](https://astamm.github.io/datagouv/reference/dg_table_id.md)
  : Read a table's stable address
- [`dg_refetch()`](https://astamm.github.io/datagouv/reference/dg_refetch.md)
  : Re-fetch a single parsed table by its stable address
- [`dg_schema()`](https://astamm.github.io/datagouv/reference/dg_schema.md)
  : Documented schema of a parsed table's columns

## Summaries

Compute summary metrics (size, number of columns, missing-value rates,
…) on a single dataset or across several datasets.

- [`dg_summary()`](https://astamm.github.io/datagouv/reference/dg_summary.md)
  : Compute summary metrics for a dataset
- [`dg_summarise()`](https://astamm.github.io/datagouv/reference/dg_summarise.md)
  : Summarise several datasets
