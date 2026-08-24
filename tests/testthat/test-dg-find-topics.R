test_that("dg_find_topics() returns a tibble with the expected columns", {
  local_mocked_bindings(
    fetch_topics_all = function(...) {
      list(
        mock_topic(
          id = "a1",
          name = "Mobilité",
          slug = "mobilite",
          tags = c("transports", "mobilite"),
          featured = TRUE,
          n_elements = 50
        ),
        mock_topic(
          id = "b2",
          name = "Environnement",
          slug = "environnement",
          tags = character(),
          n_elements = 12
        )
      )
    }
  )

  out <- dg_find_topics(q = "mobilité")

  expect_s3_class(out, "tbl_df")
  expect_named(
    out,
    c(
      "id",
      "name",
      "slug",
      "description",
      "tags",
      "featured",
      "n_elements",
      "n_datasets",
      "n_dataservices",
      "n_reuses"
    )
  )
  expect_equal(out$id, c("a1", "b2"))
  expect_equal(out$name, c("Mobilité", "Environnement"))
  expect_equal(out$tags, c("transports, mobilite", NA_character_))
  expect_equal(out$featured, c(TRUE, FALSE))
  expect_equal(out$n_elements, c(50L, 12L))
})

test_that("dg_find_topics() forwards the query and limit", {
  seen <- NULL
  local_mocked_bindings(
    fetch_topics_all = function(q = NULL, n = 20, ...) {
      seen <<- list(q = q, n = n)
      list(mock_topic(id = "a1", name = "Mobilité", slug = "mobilite"))
    }
  )

  dg_find_topics(q = "mobilite", n = 5)

  expect_equal(seen$q, "mobilite")
  expect_equal(seen$n, 5)
})

test_that("dg_find_topics() returns an empty tibble when nothing matches", {
  local_mocked_bindings(
    fetch_topics_all = function(...) list()
  )

  out <- dg_find_topics(q = "nonexistent")

  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0)
  expect_true("id" %in% names(out))
  expect_true("n_elements" %in% names(out))
  expect_true("n_datasets" %in% names(out))
})

test_that("dg_find_topics() fills the per-kind breakdown when elements = TRUE", {
  local_mocked_bindings(
    fetch_topics_all = function(...) {
      list(
        mock_topic(id = "a1", name = "Mobilité", slug = "mobilite"),
        mock_topic(id = "b2", name = "Autre", slug = "autre")
      )
    },
    # topic_element_counts(topic_id) returns n_datasets/n_dataservices/n_reuses.
    topic_element_counts = function(topic_id) {
      switch(
        topic_id,
        "a1" = list(n_datasets = 10L, n_dataservices = 2L, n_reuses = 3L),
        "b2" = list(n_datasets = 1L, n_dataservices = 0L, n_reuses = 0L)
      )
    }
  )

  out <- dg_find_topics(elements = TRUE)

  expect_equal(out$n_datasets, c(10L, 1L))
  expect_equal(out$n_dataservices, c(2L, 0L))
  expect_equal(out$n_reuses, c(3L, 0L))
})

test_that("dg_find_topics() leaves the breakdown NA unless elements = TRUE", {
  local_mocked_bindings(
    fetch_topics_all = function(...) {
      list(mock_topic(id = "a1", name = "Mobilité", slug = "mobilite"))
    }
  )

  out <- dg_find_topics()

  expect_true(all(is.na(out$n_datasets)))
  expect_true(all(is.na(out$n_dataservices)))
  expect_true(all(is.na(out$n_reuses)))
  # The cheap declared total is always populated, independent of `elements`.
  expect_equal(out$n_elements, 0L)
})

test_that("dg_find_topics() coerces absent fields to NA", {
  # Build the raw topic object directly (not via mock_topic(), whose defaults
  # would fill in absent fields) so the NA-coercion path is really exercised.
  local_mocked_bindings(
    fetch_topics_all = function(...) {
      list(
        list(
          id = "a1",
          name = "Minimal",
          slug = "minimal",
          description = NULL,
          tags = character(),
          featured = FALSE,
          elements = list(total = NULL)
        )
      )
    }
  )

  out <- dg_find_topics()

  expect_true(is.na(out$description[1]))
  expect_true(is.na(out$tags[1]))
  expect_equal(out$n_elements, NA_integer_)
})
