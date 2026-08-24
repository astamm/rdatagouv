# Helpers to build synthetic API objects for tests.

# Build a minimal, realistic dataset object as returned by the API.
mock_dataset <- function(
  title = "Example dataset",
  id = "dset-1",
  resources = NULL
) {
  if (is.null(resources)) {
    resources <- list(mock_resource("csv"))
  }
  list(
    id = id,
    title = title,
    slug = "example-dataset",
    resources = resources
  )
}

# A minimal, realistic dataset object as returned by the **v2**
# datasets/search endpoint: resources are a subsection pointer (not inlined),
# and rich per-dataset metadata is embedded.
mock_dataset_v2 <- function(
  title = "Example dataset",
  id = "dset-1",
  resources_href = NULL,
  organization = NULL,
  license = NULL,
  quality = NULL,
  metrics = NULL,
  access_type = NULL,
  frequency = NULL,
  spatial = NULL,
  temporal_coverage = NULL,
  archived = NULL,
  featured = NULL
) {
  if (is.null(resources_href)) {
    resources_href <- paste0(
      "https://www.data.gouv.fr/api/2/datasets/",
      id,
      "/resources/?page=1&page_size=50"
    )
  }
  if (is.null(organization)) {
    organization <- list(
      id = "org-1",
      slug = "example-org",
      name = "Example org"
    )
  }
  if (is.null(quality)) {
    quality <- list(
      score = 0.8,
      license = TRUE,
      temporal_coverage = TRUE,
      spatial = FALSE,
      update_frequency = TRUE,
      dataset_description_quality = TRUE
    )
  }
  if (is.null(metrics)) {
    metrics <- list(views = 100, resources_downloads = 50)
  }
  list(
    id = id,
    title = title,
    slug = paste0("slug-", id),
    description = "A v2-shaped mock dataset.",
    resources = list(
      rel = "subsection",
      href = resources_href,
      type = "GET",
      total = 1
    ),
    organization = organization,
    license = license %||% "lov2",
    quality = quality,
    metrics = metrics,
    access_type = access_type %||% "open",
    frequency = frequency %||% "monthly",
    spatial = spatial %||% list(granularity = "fr:commune", zones = list()),
    temporal_coverage = temporal_coverage %||%
      list(start = "2020-01-01", end = "2023-12-31"),
    archived = archived %||% FALSE,
    featured = featured %||% FALSE
  )
}

# A v2 search response envelope. `next_page` is a pointer-based URL string, as
# the v2 API returns; pass NULL for the last page.
mock_search_envelope <- function(datasets, next_page = NULL, total = NULL) {
  if (is.null(total)) {
    total <- length(datasets)
  }
  list(
    data = datasets,
    page = 1,
    page_size = length(datasets),
    total = total,
    next_page = next_page,
    previous_page = NULL,
    facets = list()
  )
}

# A v2 resources-subsection response page. When fully paginated, the subsection
# reproduces v1's inline resource list exactly (ids, order and key sets).
mock_subsection_page <- function(resources, next_page = NULL) {
  list(
    data = resources,
    total = length(resources),
    page_size = 50,
    next_page = next_page,
    previous_page = NULL
  )
}

# Build a minimal, realistic resource object.
mock_resource <- function(
  format = "csv",
  title = "data",
  url = "https://example.org/data.csv",
  id = "res-1",
  filesize = 1024
) {
  list(
    id = id,
    title = title,
    format = format,
    url = url,
    filesize = filesize,
    filetype = "file"
  )
}

# A minimal, realistic organization object as returned by the v2
# organizations/search endpoint. `id` is the stable 24-hex producer id a
# caller would pass to the `organization` argument of dg_find_datasets().
mock_organization <- function(
  id = "534fffb0a3a7292c64a78115",
  name = "SNCF",
  slug = "sncf",
  acronym = NULL,
  description = NULL,
  datasets = 183,
  badges = list(list(kind = "public-service")),
  business_number_id = NULL
) {
  list(
    id = id,
    name = name,
    slug = slug,
    acronym = acronym,
    description = description %||% "A mock organization.",
    metrics = list(datasets = datasets),
    badges = badges,
    business_number_id = business_number_id
  )
}

# A v2 organizations/search response envelope (same shape as
# mock_search_envelope()).
mock_organization_envelope <- function(orgs, next_page = NULL, total = NULL) {
  mock_search_envelope(orgs, next_page = next_page, total = total)
}

# A small CSV the mocks can return when "reading" a resource.
mock_csv_data <- function() {
  data.frame(
    a = c(1, 2, NA),
    b = c("x", "y", "z"),
    stringsAsFactors = FALSE
  )
}
