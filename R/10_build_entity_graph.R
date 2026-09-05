suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(jsonlite)
})

message("Building entity graph data...")

dir.create("data/public", recursive = TRUE, showWarnings = FALSE)
dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)

registry_path <- "data/processed/entity_registry.csv"
mentions_path <- "data/processed/entity_mentions.csv"
metadata_path <- "data/chapter_metadata.csv"

if (!file.exists(registry_path)) {
  stop("Missing ", registry_path, ". Run R/09_extract_named_entities.R first.")
}
if (!file.exists(metadata_path)) {
  stop("Missing ", metadata_path, ".")
}

first_existing_col <- function(df, candidates) {
  nms <- names(df)
  lower <- tolower(nms)
  idx <- match(TRUE, lower %in% tolower(candidates))
  if (is.na(idx)) return(NA_character_)
  nms[[idx]]
}

ensure_col <- function(df, col, default) {
  if (!col %in% names(df)) df[[col]] <- default
  df
}

registry <- readr::read_csv(registry_path, show_col_types = FALSE)

required_registry_cols <- c("entity_id", "canonical_entity", "entity_type", "total_count", "chapters")
missing_registry_cols <- setdiff(required_registry_cols, names(registry))
if (length(missing_registry_cols) > 0) {
  stop("entity_registry.csv is missing: ", paste(missing_registry_cols, collapse = ", "))
}

registry <- registry |>
  ensure_col("review_status", "") |>
  ensure_col("extraction_methods", "") |>
  ensure_col("notes", "") |>
  mutate(
    entity_id = as.character(entity_id),
    canonical_entity = as.character(canonical_entity),
    entity_type = as.character(entity_type),
    review_status = dplyr::coalesce(as.character(review_status), ""),
    extraction_methods = dplyr::coalesce(as.character(extraction_methods), ""),
    notes = dplyr::coalesce(as.character(notes), ""),
    chapters = dplyr::coalesce(as.character(chapters), ""),
    total_count = suppressWarnings(as.numeric(total_count)),
    total_count = dplyr::if_else(is.na(total_count), 0, total_count)
  ) |>
  filter(
    !is.na(entity_id), entity_id != "",
    !is.na(canonical_entity), canonical_entity != "",
    !is.na(entity_type), entity_type != "", entity_type != "Unclassified",
    review_status != "rejected",
    total_count > 0
  )

chapter_meta <- readr::read_csv(metadata_path, show_col_types = FALSE) |>
  mutate(chapter = suppressWarnings(as.integer(chapter))) |>
  filter(!is.na(chapter), chapter != 12)

chapter_meta <- chapter_meta |>
  ensure_col("chapter_title", NA_character_) |>
  ensure_col("approx_start_year", NA_integer_) |>
  ensure_col("approx_end_year", NA_integer_) |>
  ensure_col("life_stage", NA_character_) |>
  ensure_col("primary_locations", NA_character_) |>
  mutate(
    chapter_title = dplyr::coalesce(as.character(chapter_title), paste("Chapter", chapter)),
    approx_start_year = dplyr::coalesce(as.character(approx_start_year), "?"),
    approx_end_year = dplyr::coalesce(as.character(approx_end_year), "?"),
    life_stage = dplyr::coalesce(as.character(life_stage), ""),
    primary_locations = dplyr::coalesce(as.character(primary_locations), "")
  )

# Keep accepted entities and useful candidate entities. This avoids graphing hundreds
# of one-off OCR guesses while preserving enough data for review.
graph_registry <- registry |>
  filter(
    review_status %in% c("accepted", "") |
      (review_status == "candidate" & total_count >= 2)
  ) |>
  arrange(entity_type, desc(total_count), canonical_entity)

# Fallback builder: use the chapter list encoded in entity_registry.csv.
make_mentions_from_registry <- function(reg) {
  reg2 <- reg |>
    mutate(
      chapters_clean = dplyr::coalesce(chapters, ""),
      chapter_n = if_else(chapters_clean == "", 1L, stringr::str_count(chapters_clean, ";") + 1L)
    )

  reg2 |>
    select(entity_id, canonical_entity, entity_type, total_count, chapters_clean, chapter_n) |>
    tidyr::separate_rows(chapters_clean, sep = "\\s*;\\s*") |>
    mutate(
      chapter = suppressWarnings(as.integer(chapters_clean)),
      count = pmax(1, round(total_count / pmax(1, chapter_n)))
    ) |>
    filter(!is.na(chapter), chapter != 12) |>
    select(chapter, entity_id, canonical_entity, entity_type, count)
}

mentions <- NULL

if (file.exists(mentions_path)) {
  mentions_raw <- readr::read_csv(mentions_path, show_col_types = FALSE)

  chapter_col <- first_existing_col(mentions_raw, c("chapter", "chapter_number", "chapter_id"))
  entity_id_col <- first_existing_col(mentions_raw, c("entity_id", "id"))
  canonical_col <- first_existing_col(mentions_raw, c("canonical_entity", "entity", "entity_text", "name"))
  count_col <- first_existing_col(mentions_raw, c("count", "mention_count", "mentions", "total_count"))

  if (!is.na(chapter_col) && !is.na(entity_id_col)) {
    # Critical fix: keep only chapter/entity_id/count from the mentions file before
    # joining the registry. Otherwise dplyr suffixes canonical_entity/entity_type as
    # .x/.y and later group_by(canonical_entity, entity_type) fails.
    mentions <- tibble::tibble(
      chapter = suppressWarnings(as.integer(mentions_raw[[chapter_col]])),
      entity_id = as.character(mentions_raw[[entity_id_col]]),
      count = if (!is.na(count_col)) suppressWarnings(as.numeric(mentions_raw[[count_col]])) else 1
    )
  } else if (!is.na(chapter_col) && !is.na(canonical_col)) {
    # More defensive path: if a future mentions file lacks entity_id, match by
    # normalized canonical entity label.
    norm <- function(x) {
      x |>
        as.character() |>
        stringr::str_to_lower() |>
        stringr::str_replace_all("[\\r\\n]+", " ") |>
        stringr::str_replace_all("[^a-z0-9]+", " ") |>
        stringr::str_squish()
    }

    lookup <- graph_registry |>
      mutate(canonical_norm = norm(canonical_entity)) |>
      select(entity_id, canonical_norm)

    mentions <- tibble::tibble(
      chapter = suppressWarnings(as.integer(mentions_raw[[chapter_col]])),
      canonical_norm = norm(mentions_raw[[canonical_col]]),
      count = if (!is.na(count_col)) suppressWarnings(as.numeric(mentions_raw[[count_col]])) else 1
    ) |>
      left_join(lookup, by = "canonical_norm") |>
      select(chapter, entity_id, count)
  }
}

if (is.null(mentions)) {
  mentions <- make_mentions_from_registry(graph_registry)
} else {
  mentions <- mentions |>
    mutate(
      count = if_else(is.na(count) | count <= 0, 1, count),
      entity_id = as.character(entity_id)
    ) |>
    filter(!is.na(chapter), chapter != 12, !is.na(entity_id), entity_id != "") |>
    inner_join(graph_registry |> select(entity_id, canonical_entity, entity_type), by = "entity_id") |>
    group_by(chapter, entity_id, canonical_entity, entity_type) |>
    summarise(count = sum(count, na.rm = TRUE), .groups = "drop")
}

mentions <- mentions |>
  filter(chapter %in% chapter_meta$chapter) |>
  group_by(chapter, entity_id, canonical_entity, entity_type) |>
  summarise(count = sum(count, na.rm = TRUE), .groups = "drop") |>
  filter(count > 0)

chapter_nodes <- chapter_meta |>
  transmute(
    id = paste0("chapter_", chapter),
    label = paste0("Ch. ", chapter, ": ", chapter_title),
    short_label = paste0("Ch. ", chapter),
    type = "Chapter",
    group = "Chapter",
    chapter = chapter,
    title = paste0(
      "<strong>Chapter ", chapter, ": ", chapter_title, "</strong><br>",
      "Approx. years: ", approx_start_year, "–", approx_end_year, "<br>",
      "Life stage: ", life_stage, "<br>",
      "Primary locations: ", primary_locations
    ),
    value = 25
  )

entity_nodes <- graph_registry |>
  semi_join(mentions, by = "entity_id") |>
  transmute(
    id = entity_id,
    label = canonical_entity,
    short_label = canonical_entity,
    type = entity_type,
    group = entity_type,
    chapter = NA_integer_,
    title = paste0(
      "<strong>", canonical_entity, "</strong><br>",
      "Type: ", entity_type, "<br>",
      "Review status: ", if_else(review_status == "", "unreviewed seed", review_status), "<br>",
      "Total mentions: ", total_count, "<br>",
      "Chapters: ", chapters
    ),
    value = pmax(8, pmin(35, sqrt(total_count) * 4))
  )

nodes <- bind_rows(chapter_nodes, entity_nodes) |>
  distinct(id, .keep_all = TRUE)

mention_edges <- mentions |>
  transmute(
    from = paste0("chapter_", chapter),
    to = entity_id,
    relationship = "MENTIONS",
    weight = count,
    title = paste0("Chapter ", chapter, " mentions ", canonical_entity, " ", count, " time(s).")
  ) |>
  filter(from %in% nodes$id, to %in% nodes$id)

entity_chapters <- mentions |>
  filter(entity_type %in% c("Person", "Place", "Organization", "Organization/Place", "Event"), count >= 2) |>
  select(chapter, entity_id) |>
  distinct()

chapter_pairs <- entity_chapters |>
  inner_join(entity_chapters |> rename(chapter_b = chapter), by = "entity_id") |>
  filter(chapter < chapter_b) |>
  count(chapter, chapter_b, name = "shared_entities") |>
  filter(shared_entities >= 3) |>
  transmute(
    from = paste0("chapter_", chapter),
    to = paste0("chapter_", chapter_b),
    relationship = "SHARES_ENTITIES_WITH",
    weight = shared_entities,
    title = paste0("These chapters share ", shared_entities, " recurring entities.")
  ) |>
  filter(from %in% nodes$id, to %in% nodes$id)

edges <- bind_rows(mention_edges, chapter_pairs) |>
  distinct(from, to, relationship, .keep_all = TRUE)

readr::write_csv(nodes, "data/public/graph_nodes.csv")
readr::write_csv(edges, "data/public/graph_edges.csv")
jsonlite::write_json(nodes, "data/public/graph_nodes.json", pretty = TRUE, auto_unbox = TRUE, na = "null")
jsonlite::write_json(edges, "data/public/graph_edges.json", pretty = TRUE, auto_unbox = TRUE, na = "null")

message("Wrote graph outputs:")
message("- data/public/graph_nodes.csv")
message("- data/public/graph_edges.csv")
message("- data/public/graph_nodes.json")
message("- data/public/graph_edges.json")
message("Graph contains ", nrow(nodes), " nodes and ", nrow(edges), " edges.")
