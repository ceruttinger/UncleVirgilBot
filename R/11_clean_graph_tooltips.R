suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(jsonlite)
})

clean_tooltip <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  x <- str_replace_all(x, regex("<br\\s*/?>", ignore_case = TRUE), "\n")
  x <- str_replace_all(x, regex("</p>|</div>|</li>", ignore_case = TRUE), "\n")
  x <- str_replace_all(x, "<[^>]+>", "")
  x <- str_replace_all(x, "&nbsp;", " ")
  x <- str_replace_all(x, "&amp;", "&")
  x <- str_replace_all(x, "&lt;", "<")
  x <- str_replace_all(x, "&gt;", ">")
  x <- str_replace_all(x, "&quot;", '"')
  x <- str_replace_all(x, "&#39;", "'")
  x <- str_replace_all(x, "\\r\\n|\\r", "\n")
  x <- str_replace_all(x, "[ \\t]+\\n", "\n")
  x <- str_replace_all(x, "\\n[ \\t]+", "\n")
  x <- str_replace_all(x, "\\n{3,}", "\n\n")
  str_trim(x)
}

rebuild_node_title <- function(df) {
  out <- df
  id <- if ("id" %in% names(out)) as.character(out$id) else rep("", nrow(out))
  label <- if ("label" %in% names(out)) as.character(out$label) else id
  node_type <- dplyr::coalesce(
    if ("entity_type" %in% names(out)) as.character(out$entity_type) else NA_character_,
    if ("group" %in% names(out)) as.character(out$group) else NA_character_,
    ifelse(str_detect(id, "^chapter"), "Chapter", "Entity")
  )
  review <- dplyr::coalesce(
    if ("review_status" %in% names(out)) as.character(out$review_status) else NA_character_,
    "unreviewed seed"
  )
  total <- dplyr::coalesce(
    if ("total_count" %in% names(out)) as.character(out$total_count) else NA_character_,
    if ("mentions" %in% names(out)) as.character(out$mentions) else NA_character_,
    if ("value" %in% names(out)) as.character(out$value) else NA_character_,
    ""
  )
  chapters <- dplyr::coalesce(
    if ("chapters" %in% names(out)) as.character(out$chapters) else NA_character_,
    ""
  )

  rebuilt <- paste0(
    label,
    "\nType: ", node_type,
    "\nReview status: ", review,
    ifelse(total != "", paste0("\nTotal mentions: ", total), ""),
    ifelse(chapters != "", paste0("\nChapters: ", chapters), "")
  )

  out$title <- clean_tooltip(rebuilt)
  out
}

rebuild_edge_title <- function(df) {
  out <- df
  if (!"title" %in% names(out)) {
    out$title <- ""
  }
  out$title <- clean_tooltip(out$title)
  if ("label" %in% names(out)) {
    out$label <- clean_tooltip(out$label)
  }
  out
}

nodes_csv <- "data/public/graph_nodes.csv"
edges_csv <- "data/public/graph_edges.csv"

if (!file.exists(nodes_csv) || !file.exists(edges_csv)) {
  stop("Graph CSV files do not exist yet. Run R/10_build_entity_graph.R before cleaning tooltips.")
}

nodes <- read_csv(nodes_csv, show_col_types = FALSE) |> rebuild_node_title()
edges <- read_csv(edges_csv, show_col_types = FALSE) |> rebuild_edge_title()

write_csv(nodes, nodes_csv)
write_csv(edges, edges_csv)

write_json(nodes, "data/public/graph_nodes.json", pretty = TRUE, auto_unbox = TRUE, na = "null")
write_json(edges, "data/public/graph_edges.json", pretty = TRUE, auto_unbox = TRUE, na = "null")

cat("Cleaned graph tooltips so HTML tags do not display literally.\n")
