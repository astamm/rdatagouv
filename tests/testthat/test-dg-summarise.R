test_that("dg_summarise() summarises a named list of tibbles", {
  out <- dg_summarise(datasets = list(iris = iris, mtcars = mtcars))

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 2)
  expect_named(
    out,
    c(
      "dataset",
      "size_kb",
      "n_vars",
      "n_numeric",
      "n_non_numeric",
      "n_rows",
      "prop_missing"
    )
  )
  expect_equal(out$dataset, c("iris", "mtcars"))
  expect_equal(out$n_rows, c(150, 32))
})

test_that("dg_summarise() downloads datasets from names when given a character vector", {
  local_mocked_bindings(
    dg_pull_dataset = function(name, remove_na = FALSE) {
      data.frame(x = 1, y = "v")
    }
  )

  out <- dg_summarise(datasets = c("A", "B"))

  expect_equal(out$dataset, c("A", "B"))
  expect_equal(out$n_vars, c(2, 2))
})

test_that("dg_summarise() accepts a dg_list_datasets() tibble", {
  local_mocked_bindings(
    dg_pull_dataset = function(id, remove_na = FALSE) {
      if (id == "id1") data.frame(x = 1) else data.frame(x = 1, y = 2)
    }
  )

  catalog <- tibble::tibble(
    title = c("Alpha", "Beta"),
    id = c("id1", "id2"),
    description = NA_character_,
    slug = NA_character_
  )

  out <- dg_summarise(datasets = catalog)

  # Labelled by title, downloaded by id.
  expect_equal(out$dataset, c("Alpha", "Beta"))
  expect_equal(out$n_vars, c(1, 2))
})

test_that("dg_summarise() uses the first n datasets by default", {
  local_mocked_bindings(
    dg_list_datasets = function(q = NULL, n = 1000) {
      utils::head(
        tibble::tibble(
          title = paste0("ds", 1:10),
          id = paste0("id", 1:10),
          description = NA_character_,
          slug = NA_character_
        ),
        n
      )
    },
    dg_pull_dataset = function(id, remove_na = FALSE) {
      data.frame(x = 1, y = "v")
    }
  )

  out <- dg_summarise(n = 3)

  expect_equal(out$dataset, c("ds1", "ds2", "ds3"))
})

test_that("dg_summarise() labels by title but downloads by id", {
  downloaded <- c()
  local_mocked_bindings(
    dg_list_datasets = function(q = NULL, n = 1000) {
      tibble::tibble(
        title = c("Alpha", "Beta"),
        id = c("aaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbb"),
        description = NA_character_,
        slug = NA_character_
      )
    },
    dg_pull_dataset = function(id, remove_na = FALSE) {
      downloaded <<- c(downloaded, id)
      data.frame(x = 1, y = "v")
    }
  )

  out <- dg_summarise(n = 2)

  expect_equal(out$dataset, c("Alpha", "Beta"))
  expect_equal(
    downloaded,
    c("aaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbb")
  )
})

test_that("dg_summarise() disambiguates duplicated titles with their id", {
  downloaded <- c()
  local_mocked_bindings(
    dg_list_datasets = function(q = NULL, n = 1000) {
      tibble::tibble(
        title = c("Shared", "Shared", "Unique"),
        id = c(
          "aaaaaaaaaaaaaaaaaaaaaaaa",
          "bbbbbbbbbbbbbbbbbbbbbbbb",
          "cccccccccccccccccccccccc"
        ),
        description = NA_character_,
        slug = NA_character_
      )
    },
    dg_pull_dataset = function(id, remove_na = FALSE) {
      downloaded <<- c(downloaded, id)
      data.frame(x = 1, y = "v")
    }
  )

  out <- dg_summarise(n = 3)

  # Both distinct ids must still be downloaded even though they share a title.
  expect_equal(
    downloaded,
    c(
      "aaaaaaaaaaaaaaaaaaaaaaaa",
      "bbbbbbbbbbbbbbbbbbbbbbbb",
      "cccccccccccccccccccccccc"
    )
  )
  # Duplicated titles get their id appended so the labels stay unique, while a
  # single-occurrence title is left unchanged.
  expect_equal(
    out$dataset,
    c(
      "Shared [aaaaaaaaaaaaaaaaaaaaaaaa]",
      "Shared [bbbbbbbbbbbbbbbbbbbbbbbb]",
      "Unique"
    )
  )
})

test_that("dg_summarise() returns an empty tibble for an empty list", {
  out <- dg_summarise(datasets = list())

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0)
})

test_that("dg_summarise() summarises a multi-table dataset by table", {
  # A dataset whose resource is a ZIP may yield several tables; each gets its
  # own summary row, labelled "dataset / table".
  local_mocked_bindings(
    dg_pull_dataset = function(id, remove_na = FALSE) {
      list(
        "data.csv" = data.frame(a = 1:2),
        "notes.tsv" = data.frame(c = 1)
      )
    }
  )

  out <- dg_summarise(
    datasets = c("aaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbb")
  )

  expect_equal(
    out$dataset,
    c(
      "aaaaaaaaaaaaaaaaaaaaaaaa / data.csv",
      "aaaaaaaaaaaaaaaaaaaaaaaa / notes.tsv",
      "bbbbbbbbbbbbbbbbbbbbbbbb / data.csv",
      "bbbbbbbbbbbbbbbbbbbbbbbb / notes.tsv"
    )
  )
  expect_equal(out$n_rows, c(2, 1, 2, 1))
})

test_that("dg_summarise() keeps a single table's plain label", {
  local_mocked_bindings(
    dg_pull_dataset = function(id, remove_na = FALSE) {
      list("data.csv" = data.frame(a = 1:2))
    }
  )

  out <- dg_summarise(datasets = "aaaaaaaaaaaaaaaaaaaaaaaa")

  # A dataset contributing a single table keeps its label without a " / file".
  expect_equal(out$dataset, "aaaaaaaaaaaaaaaaaaaaaaaa")
  expect_equal(out$n_rows, 2)
})

test_that("dg_summarise() errors on invalid input", {
  expect_snapshot(error = TRUE, dg_summarise(datasets = 42))
})
