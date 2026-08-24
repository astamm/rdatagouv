# fetch_resource_subsection() errors without an href

    Code
      fetch_resource_subsection(list(rel = "subsection"))
    Condition
      Error:
      ! The resources pointer carries no 'href' to fetch from.

# find_dataset() errors when no title matches exactly

    Code
      find_dataset("Does not exist")
    Condition
      Error:
      ! No dataset titled 'Does not exist' was found on data.gouv.fr. Check the name with dg_find_datasets().

# read_first_parseable_resource() errors when no resource is supported

    Code
      read_first_parseable_resource(dataset)
    Condition
      Error:
      ! Dataset 'Example dataset' has no resource in a supported format (zip, csv, csv.gz, xls, xlsx, parquet, tsv, txt, json).

# read_first_parseable_resource() errors when every candidate fails

    Code
      read_first_parseable_resource(dataset)
    Condition
      Error:
      ! None of the 2 tabular resource(s) of dataset 'Example dataset' could be parsed into a table. First failure: boom

# read_json_file() errors clearly on a non-tabular nested object

    Code
      read_json_file(path)
    Condition
      Error:
      ! JSON object is not tabular data: Tibble columns must have compatible sizes.
      * Size 5: Column `links`.
      * Size 10: Column `dataset`.
      i Only values of size one are recycled.. This resource declares `json` but does not contain a table (it is likely an API metadata document). Try another resource of the dataset, e.g. via dg_find_datasets() or dg_refetch().

# read_resource() errors on unsupported formats

    Code
      read_resource(mock_resource("pdf"))
    Condition
      Error:
      ! Unsupported format: pdf

