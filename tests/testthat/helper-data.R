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

# A small CSV the mocks can return when "reading" a resource.
mock_csv_data <- function() {
  data.frame(
    a = c(1, 2, NA),
    b = c("x", "y", "z"),
    stringsAsFactors = FALSE
  )
}
