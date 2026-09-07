#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Git status:"
git status --short

echo
echo "Latest commits:"
git log --oneline -5

echo
echo "Local HEAD:"
git rev-parse HEAD

echo
echo "Remote main:"
git ls-remote origin main | cut -f1

echo
echo "Recent GitHub Pages runs:"
gh run list --repo ceruttinger/UncleVirgilBot --limit 5
