#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Rebuilding data products..."
Rscript R/render_all.R

echo
echo "Rendering Quarto site..."
quarto render

echo
echo "Done. Preview with:"
echo "quarto preview"
