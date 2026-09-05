# Named entity workflow

This project uses a review-first named entity workflow.

## Why not just use generic NER?

The memoir has OCR noise, historical names, family names, place names, abbreviations, LDS/church terminology, CIA/military references, and sometimes lower-case text. A generic NER model will miss important domain-specific entities and return false positives.

## Current workflow

1. `data/entity_seeds.csv` stores known people, places, organizations, and variants.
2. `R/09_extract_named_entities.R` matches those seeds against chapter text.
3. The same script extracts four-digit years as Date entities.
4. Outputs are written to `data/processed/` and `data/public/`.
5. `entities.qmd` displays registry and mention tables.

## Key outputs

- `data/processed/entity_registry.csv`
- `data/processed/entity_mentions.csv`
- `data/public/entity_registry.json`
- `data/public/entity_mentions.json`

## Manual review

Edit `data/entity_seeds.csv` to add:

- people
- places
- organizations
- events
- spelling variants
- OCR variants
- canonical names

Then rerun:

```bash
Rscript R/09_extract_named_entities.R
quarto preview
```

## Later production model

Once entities are reviewed, promote accepted records into a database table:

- `entities`
- `entity_aliases`
- `entity_mentions`
- `chapters`
- `passages`

That database can power graph views and chatbot citations.
