#!/usr/bin/env bash
# Copies Mulberry Symbols into assets/symbols/, renamed to Bolo card ids.
# Mulberry Symbols: https://mulberrysymbols.org (CC-BY-SA, see ATTRIBUTION.md)
#
# NOTE on the MAP below: the real mulberry-symbols repo stores all SVGs flat
# under EN/ (no per-letter subfolders), and verb symbols are named with a
# trailing "_,_to" (e.g. "eat_,_to.svg"). A plain word-substring search (e.g.
# term "eat" against "*eat*.svg") is NOT safe here — it matches unrelated
# files like "ant_eater.svg" or "great.svg" before the real "eat_,_to.svg"
# because of alphabetical sort order. So most terms below are the exact
# filename stem (verified by hand against the real EN/ listing + a visual
# check of each symbol), not a loose synonym. The exact-match branch is what
# actually resolves them; the substring fallback is kept only as a safety
# net for re-runs against a slightly different repo snapshot.
#
# A few ids have no matching concept in Mulberry Symbols at all (verified by
# grepping scripts/data/symbol-info-en.csv, the set's own name/category
# index) and were mapped to the closest reasonable synonym instead:
#   - tv        -> flatscreen_tv (no "tv"/"television" noun symbol exists)
#   - book      -> read_book_,_to (no plain "book" noun symbol exists)
#   - snack     -> biscuits (no "snack" symbol; biscuits is tagged "food snack")
#   - hurts     -> plaster (no "pain"/"hurt" symbol; a plaster/band-aid is the
#                  standard AAC stand-in for "that hurts")
#   - tired     -> yawn_,_to (no "tired"/"sleepy" symbol)
#   - sick      -> thermometer (no "sick"/"ill"/"unwell" symbol)
#   - all-done  -> finish (no "finished"/"all done"/"empty" symbol reads better)
#   - stop      -> enough (Mulberry has NO stop/no/halt/prohibit symbol at all;
#                  "enough" is the closest core-AAC-vocabulary substitute)
#   - happy/sad/angry/scared -> Mulberry only has gendered "_lady"/"_man"
#     variants for feelings, no neutral/child face. The "_man" variant was
#     picked for all four for visual consistency across the feelings row.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git clone --depth 1 https://github.com/mulberrysymbols/mulberry-symbols.git "$WORK/mulberry"
# Pick the directory with the MOST directly-contained SVGs, not just the
# first one found. A naive "first dir with any svg" scan is directory-
# traversal-order dependent (not deterministic) and on this repo can land on
# docs/assets/examples (8 sample svgs) instead of the real symbol set in
# EN/ (3400+ svgs) depending on filesystem readdir order.
SVG_DIR=""
BEST_COUNT=0
while read -r d; do
  n=$(find "$d" -maxdepth 1 -iname '*.svg' | wc -l | tr -d ' ')
  if [ "$n" -gt "$BEST_COUNT" ]; then
    BEST_COUNT="$n"
    SVG_DIR="$d"
  fi
done < <(find "$WORK/mulberry" -type d)
echo "SVGs found under: $SVG_DIR ($BEST_COUNT files)"

mkdir -p assets/symbols

# card-id:search-term (first match wins; adjust term if a mapping misses)
MAP="eat:eat_,_to drink:drink water:water snack:biscuits more:more all-done:finish
toilet:toilet wash-hands:wash_hands_,_to hurts:plaster tired:yawn_,_to sick:thermometer
play:play_,_to outside:outside ball:ball book:read_book_,_to music:music tv:flatscreen_tv bubbles:bubbles
happy:happy_man sad:sad_man angry:angry_man scared:afraid_man love:heart_shape
help:help_,_to come-here:come_,_to hug:hug_,_to stop:enough"

MISSING=""
for pair in $MAP; do
  id="${pair%%:*}"; term="${pair##*:}"
  match=$(find "$SVG_DIR" -maxdepth 1 -iname "${term}.svg" | head -1)
  [ -z "$match" ] && match=$(find "$SVG_DIR" -maxdepth 1 -iname "*${term}*.svg" | sort | head -1)
  if [ -n "$match" ]; then
    cp "$match" "assets/symbols/${id}.svg"
    echo "OK   ${id}  <-  $(basename "$match")"
  else
    MISSING="$MISSING ${id}(${term})"
  fi
done
[ -n "$MISSING" ] && echo "MISSING:$MISSING — pick manually from $SVG_DIR" && exit 1
echo "All 27 symbols copied."

# flutter_svg has no CSS support: inline any Mulberry <style> classes so symbols don't render solid black.
python3 tool/inline_svg_styles.py assets/symbols/*.svg
