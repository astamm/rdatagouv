# schema_only = TRUE announces the forced resource fetch

    Code
      dg_find_datasets(schema_only = TRUE, resources = FALSE)
    Message
      Forcing `resources = TRUE` because `schema_only = TRUE` selects on `has_schema`, which needs the per-dataset resource fetch.
    Output
      # A tibble: 0 x 21
      # i 21 variables: title <chr>, id <chr>, description <chr>, slug <chr>,
      #   organization <chr>, license <chr>, quality_score <dbl>,
      #   quality_flags <chr>, views <int>, resources_downloads <int>,
      #   access_type <chr>, frequency <chr>, spatial_granularity <chr>,
      #   temporal_start <chr>, temporal_end <chr>, archived <lgl>, featured <lgl>,
      #   n_resources <int>, formats <list>, has_table <lgl>, has_schema <lgl>

