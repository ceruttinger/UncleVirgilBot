suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(tidyr)
  library(purrr)
  library(jsonlite)
})

message("Building named entity layer...")

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("data/public", recursive = TRUE, showWarnings = FALSE)

if (!file.exists("data/processed/chapter_text.csv")) {
  if (file.exists("R/01_prepare_corpus.R")) {
    source("R/01_prepare_corpus.R")
  } else {
    stop("Missing data/processed/chapter_text.csv and R/01_prepare_corpus.R")
  }
}

chapters <- readr::read_csv("data/processed/chapter_text.csv", show_col_types = FALSE)

required_chapter_cols <- c("chapter", "chapter_title", "text")
missing_chapter_cols <- setdiff(required_chapter_cols, names(chapters))
if (length(missing_chapter_cols) > 0) {
  stop("chapter_text.csv is missing: ", paste(missing_chapter_cols, collapse = ", "))
}

# Exclude synthetic Full Text chapter so entities do not get double-counted.
chapters_for_entities <- chapters |>
  filter(!is.na(chapter), chapter != 12) |>
  mutate(
    text = coalesce(as.character(text), ""),
    chapter_title = coalesce(as.character(chapter_title), paste("Chapter", chapter))
  )

norm_text <- function(x) {
  x |>
    str_to_lower() |>
    str_replace_all("[\\r\\n]+", " ") |>
    str_replace_all("[^a-z0-9]+", " ") |>
    str_squish()
}

count_phrase <- function(text, phrase) {
  nt <- norm_text(text)
  np <- norm_text(phrase)
  if (is.na(np) || np == "") return(0L)
  pattern <- paste0("(^| )", np, "( |$)")
  stringr::str_count(nt, pattern)
}

# -----------------------------------------------------------------------------
# Curated seed list
# -----------------------------------------------------------------------------
seed_path <- "data/entity_seeds.csv"

base_seeds <- tibble::tribble(
  ~canonical_entity, ~entity_type, ~aliases, ~review_status, ~notes,
  "Marion", "Person", "", "candidate", "Curated seed from memoir/entity review.",
  "Richard", "Person", "", "candidate", "Curated seed from memoir/entity review.",
  "Martin", "Person", "", "candidate", "Curated seed from memoir/entity review.",
  "Loverna", "Person", "", "candidate", "Curated seed from memoir/entity review.",
  "Ila Rose", "Person", "", "candidate", "Curated seed from memoir/entity review.",
  "Sarah Harris", "Person", "Aunt Sarah", "candidate", "Curated seed from memoir/entity review.",
  "Solomon R. Harris", "Person", "Uncle Sol; Sol Harris", "candidate", "Curated seed from memoir/entity review.",
  "Solomon Webster Harris", "Person", "", "candidate", "Curated seed from memoir/entity review.",
  "Martin Harris", "Person", "", "candidate", "Curated seed from memoir/entity review.",
  "Carmen Stevens", "Person", "Carmen", "candidate", "Curated seed from memoir/entity review.",
  "Reuel Neilson", "Person", "Revel Neilson; Reuel Nielsen; Jr", "candidate", "OCR/name variant needs review.",
  "Jack Kelley", "Person", "Jack Kelly", "candidate", "OCR/name variant needs review.",
  "Joyce McNeill", "Person", "Joyce", "candidate", "Curated seed from memoir/entity review.",
  "Rhoda Jones", "Person", "", "candidate", "Curated from unclassified list.",
  "Julian Lowe", "Person", "", "candidate", "Curated from unclassified list.",
  "Wendell Thorne", "Person", "", "candidate", "Curated from unclassified list.",
  "Dottie Burton", "Person", "", "candidate", "Curated from unclassified list.",
  "Joe Dunn", "Person", "", "candidate", "Curated from unclassified list.",
  "Heber J. Grant", "Person", "", "candidate", "Curated seed from memoir/entity review.",
  "Franklin D. Roosevelt", "Person", "Roosevelt; FDR", "candidate", "Historical figure.",
  "Herbert Hoover", "Person", "Hoover", "candidate", "Historical figure.",
  "Harry Truman", "Person", "Truman", "candidate", "Historical figure.",
  "Dwight D. Eisenhower", "Person", "Eisenhower", "candidate", "Historical figure.",
  "Lyndon Johnson", "Person", "Lyndon B. Johnson; LBJ", "candidate", "Historical figure.",
  "Richard M. Nixon", "Person", "Nixon", "candidate", "Historical figure.",
  "Martin Luther King", "Person", "Martin Luther King Jr; Dr King", "candidate", "Historical figure.",
  "Howard Hughes", "Person", "", "candidate", "Curated from unclassified list.",
  "Howard Hunt", "Person", "E. Howard Hunt", "candidate", "Curated from unclassified list.",

  "Idaho Falls", "Place", "Idaho Falls Idaho", "candidate", "Curated seed from memoir/entity review.",
  "Mesa", "Place", "Mesa Arizona", "candidate", "Curated seed from memoir/entity review.",
  "Arizona", "Place", "", "candidate", "Curated seed from memoir/entity review.",
  "Idaho", "Place", "", "candidate", "Curated seed from memoir/entity review.",
  "Utah", "Place", "", "candidate", "Curated seed from memoir/entity review.",
  "Salt Lake City", "Place", "Salt Lake; Salt Lake\nCity", "candidate", "Curated seed from memoir/entity review.",
  "Pomona", "Place", "Pomona California", "candidate", "Curated seed from memoir/entity review.",
  "California", "Place", "", "candidate", "Curated seed from memoir/entity review.",
  "Montevideo", "Place", "Montevideo Uruguay", "candidate", "Curated seed from memoir/entity review.",
  "Uruguay", "Place", "", "candidate", "Curated seed from memoir/entity review.",
  "Rio De Janeiro", "Place", "Rio de Janeiro; Rio", "candidate", "Curated seed from memoir/entity review.",
  "McLean Virginia", "Place", "McLean; McLean Va.; McLean VA", "candidate", "Curated seed from memoir/entity review.",
  "Virginia", "Place", "", "candidate", "Curated seed from memoir/entity review.",
  "Washington", "Place", "Washington DC; Washington D.C.; D.C.", "candidate", "Could mean state or DC; review context.",
  "United States", "Place", "United\nStates; U.S.; US", "candidate", "Curated from unclassified list.",
  "New York", "Place", "", "candidate", "Curated from unclassified list.",
  "New York City", "Place", "", "candidate", "Curated from unclassified list.",
  "Soviet Union", "Place", "USSR; U.S.S.R.", "candidate", "Historical geopolitical entity.",
  "Japan", "Place", "", "candidate", "Curated seed from memoir/entity review.",
  "Philippines", "Place", "Philippine Islands", "candidate", "Curated seed from memoir/entity review.",
  "Pearl Harbor", "Place", "", "candidate", "Curated seed from memoir/entity review.",
  "South China Sea", "Place", "", "candidate", "Curated seed from memoir/entity review.",
  "Vietnam", "Place", "Indochina; Indo China", "candidate", "Curated seed from memoir/entity review.",
  "Sao Paulo", "Place", "São Paulo", "candidate", "Curated from unclassified list.",
  "Kansas City", "Place", "", "candidate", "Curated from unclassified list.",
  "Los Angeles", "Place", "", "candidate", "Curated from unclassified list.",
  "Falls Church", "Place", "", "candidate", "Curated from unclassified list.",
  "Shanks Village", "Place", "", "candidate", "Curated from unclassified list.",
  "Hill Cumorah", "Place", "", "candidate", "Curated from unclassified list.",
  "Atlantic Ocean", "Place", "", "candidate", "Curated from unclassified list.",

  "U.S. Navy", "Organization", "US Navy; United States Navy; Navy", "candidate", "Curated seed from memoir/entity review.",
  "USS Wasp", "Organization", "Wasp; U.S.S. Wasp", "candidate", "Ship; treated as organization/object for graph purposes.",
  "Central Intelligence Agency", "Organization", "CIA", "candidate", "Curated seed from memoir/entity review.",
  "Clandestine Services", "Organization", "", "candidate", "Curated from unclassified list.",
  "State Department", "Organization", "Department of State", "candidate", "Curated from unclassified list.",
  "Foreign Service", "Organization", "", "candidate", "Curated from unclassified list.",
  "Air Force", "Organization", "U.S. Air Force; US Air Force", "candidate", "Curated from unclassified list.",
  "Columbia University", "Organization", "Colombia University", "candidate", "Includes common OCR/spelling variant seen in chapter title.",
  "Brigham Young University", "Organization", "BYU", "candidate", "Curated seed from memoir/entity review.",
  "Church of Jesus Christ of Latter-day Saints", "Organization", "Church of Jesus Christ of Latter Day Saints; LDS Church; church", "candidate", "Broad religious organization; 'church' may overcount.",
  "Communications Workers of America", "Organization", "CWA", "candidate", "Curated seed from memoir/entity review.",
  "Mountain States Telephone and Telegraph", "Organization", "Mountain States Telephone; MSTT; MST T", "candidate", "Curated seed from memoir/entity review.",
  "Western Electric", "Organization", "Western Electric Co", "candidate", "Curated seed from memoir/entity review.",
  "Presiding Bishop's Office", "Organization", "Presiding Bishops Office; PBO", "candidate", "Curated seed from memoir/entity review.",
  "Arizona Temple", "Organization/Place", "Mesa Temple", "candidate", "Temple is both place and institution.",
  "Idaho Falls Temple", "Organization/Place", "", "candidate", "Temple is both place and institution.",
  "Utah State Agricultural College", "Organization", "Utah State Agricultural\nCollege; USAC; Utah State", "candidate", "Curated from unclassified list.",
  "Idaho Falls High School", "Organization", "", "candidate", "Curated seed from memoir/entity review.",
  "Alexandria Ward", "Organization", "Alexandia Ward", "candidate", "Curated from unclassified list; includes OCR misspelling.",
  "Arlington Ward", "Organization", "", "candidate", "Curated from unclassified list.",
  "Sunday School", "Organization", "", "candidate", "Church program; may be generic.",
  "First Presidency", "Organization", "", "candidate", "Church leadership body.",
  "Personnel Management Staff", "Organization", "", "candidate", "Curated from unclassified list.",
  "Soviet Embassy", "Organization/Place", "", "candidate", "Curated from unclassified list.",
  "American Embassy", "Organization/Place", "", "candidate", "Curated from unclassified list.",
  "American University", "Organization", "", "candidate", "Curated from unclassified list.",
  "World War II", "Event", "World War Two; World War; WWII", "candidate", "Curated from unclassified list."
)

if (file.exists(seed_path)) {
  existing_seeds <- readr::read_csv(seed_path, show_col_types = FALSE)

  # Normalize schema across earlier patch versions.
  names(existing_seeds) <- names(existing_seeds) |>
    str_replace_all("[^A-Za-z0-9]+", "_") |>
    str_to_lower()

  if ("entity" %in% names(existing_seeds) && !"canonical_entity" %in% names(existing_seeds)) {
    existing_seeds <- existing_seeds |> rename(canonical_entity = entity)
  }
  if ("canonical" %in% names(existing_seeds) && !"canonical_entity" %in% names(existing_seeds)) {
    existing_seeds <- existing_seeds |> rename(canonical_entity = canonical)
  }
  if (!"canonical_entity" %in% names(existing_seeds)) {
    existing_seeds$canonical_entity <- character(nrow(existing_seeds))
  }
  if (!"entity_type" %in% names(existing_seeds)) existing_seeds$entity_type <- "Unclassified"
  if (!"aliases" %in% names(existing_seeds)) existing_seeds$aliases <- ""
  if (!"review_status" %in% names(existing_seeds)) existing_seeds$review_status <- "candidate"
  if (!"notes" %in% names(existing_seeds)) existing_seeds$notes <- ""

  existing_seeds <- existing_seeds |>
    select(canonical_entity, entity_type, aliases, review_status, notes) |>
    mutate(across(everything(), ~coalesce(as.character(.x), "")))

  seed_rows <- bind_rows(existing_seeds, base_seeds) |>
    mutate(canonical_norm = norm_text(canonical_entity)) |>
    filter(canonical_norm != "") |>
    arrange(canonical_norm, desc(review_status == "reviewed"), desc(entity_type != "Unclassified")) |>
    distinct(canonical_norm, .keep_all = TRUE) |>
    select(-canonical_norm)
} else {
  seed_rows <- base_seeds
}

readr::write_csv(seed_rows, seed_path)

# Build search terms from canonical names and aliases.
seed_terms <- seed_rows |>
  mutate(
    aliases = coalesce(aliases, ""),
    term_blob = if_else(aliases == "", canonical_entity, paste(canonical_entity, aliases, sep = ";"))
  ) |>
  separate_rows(term_blob, sep = "\\s*;\\s*") |>
  transmute(
    canonical_entity,
    entity_type,
    review_status,
    notes,
    search_term = str_squish(term_blob)
  ) |>
  filter(!is.na(search_term), search_term != "") |>
  mutate(search_term_norm = norm_text(search_term)) |>
  filter(search_term_norm != "") |>
  distinct(canonical_entity, search_term_norm, .keep_all = TRUE)

# Count seed mentions by chapter.
seed_mentions <- tidyr::crossing(
  chapters_for_entities |> select(chapter, chapter_title, text),
  seed_terms
) |>
  mutate(count = purrr::map2_int(text, search_term, count_phrase)) |>
  filter(count > 0) |>
  transmute(
    entity_id = paste0(str_to_lower(entity_type), "__", norm_text(canonical_entity)) |>
      str_replace_all("[^a-z0-9]+", "_") |>
      str_replace_all("^_+|_+$", ""),
    canonical_entity,
    entity_type,
    search_term,
    chapter,
    chapter_title,
    count,
    extraction_method = "seed_phrase",
    review_status,
    notes
  )

# Extract year candidates from chapters 1-11 only.
year_mentions <- chapters_for_entities |>
  transmute(
    chapter,
    chapter_title,
    years = str_extract_all(text, "\\b(18|19|20)[0-9]{2}\\b")
  ) |>
  tidyr::unnest_longer(years, values_to = "canonical_entity", keep_empty = FALSE) |>
  filter(!is.na(canonical_entity)) |>
  count(chapter, chapter_title, canonical_entity, name = "count") |>
  transmute(
    entity_id = paste0("date__", canonical_entity),
    canonical_entity,
    entity_type = "Date",
    search_term = canonical_entity,
    chapter,
    chapter_title,
    count,
    extraction_method = "year_regex",
    review_status = "candidate",
    notes = "Detected four-digit year. Review whether this is chapter-period date, historical context, or retrospective reference."
  )

entity_mentions <- bind_rows(seed_mentions, year_mentions) |>
  arrange(entity_type, canonical_entity, chapter)

# Registry: one row per canonical entity.
entity_registry <- entity_mentions |>
  group_by(entity_id, canonical_entity, entity_type) |>
  summarise(
    review_status = dplyr::first(na.omit(review_status)),
    total_count = sum(count, na.rm = TRUE),
    chapters = paste(sort(unique(chapter)), collapse = "; "),
    extraction_methods = paste(sort(unique(extraction_method)), collapse = "; "),
    notes = paste(unique(na.omit(notes)), collapse = " | "),
    .groups = "drop"
  ) |>
  arrange(desc(total_count), entity_type, canonical_entity)

entity_summary <- entity_registry |>
  count(entity_type, name = "entity_count") |>
  arrange(desc(entity_count), entity_type)

readr::write_csv(entity_mentions, "data/processed/entity_mentions.csv")
readr::write_csv(entity_registry, "data/processed/entity_registry.csv")
readr::write_csv(entity_summary, "data/processed/entity_summary.csv")

readr::write_csv(entity_mentions, "data/public/entity_mentions.csv")
readr::write_csv(entity_registry, "data/public/entity_registry.csv")
readr::write_csv(entity_summary, "data/public/entity_summary.csv")

jsonlite::write_json(entity_mentions, "data/public/entity_mentions.json", pretty = TRUE, auto_unbox = TRUE)
jsonlite::write_json(entity_registry, "data/public/entity_registry.json", pretty = TRUE, auto_unbox = TRUE)
jsonlite::write_json(entity_summary, "data/public/entity_summary.json", pretty = TRUE, auto_unbox = TRUE)

message("Wrote entity outputs without Full Text chapter double-counting.")
message("- data/processed/entity_mentions.csv")
message("- data/processed/entity_registry.csv")
message("- data/processed/entity_summary.csv")
