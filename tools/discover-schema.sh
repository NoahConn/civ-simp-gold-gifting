#!/usr/bin/env bash
#
# discover-schema.sh — find the real Civ VII table/column/effect names this mod
# needs, by grepping the installed base game's data files.
#
# WHY: data/gift-gold-endeavor.sql ships with << >> tokens because the endeavor,
# gold-transfer, and relationship-effect schema is specific to the installed game
# version (1.4.0) and is NOT reliably documented online. This script automates the
# manual lookup described in the README by reading the base game modules directly.
# No game launch required — it only reads the shipped XML/SQL definition files.
#
# USAGE:
#   bash tools/discover-schema.sh                 # auto-detect the install
#   CIV_DIR="/path/to/Sid Meier's Civilization VII" bash tools/discover-schema.sh
#
# Then paste the relevant output into data/gift-gold-endeavor.sql, replacing the
# << >> tokens, and delete this file's header once the SQL loads cleanly.

set -uo pipefail

# --- 1) Locate the install --------------------------------------------------
# Override with CIV_DIR=... if your install lives somewhere unusual.
CANDIDATES=(
  "${CIV_DIR:-}"
  "$HOME/Library/Application Support/Steam/steamapps/common/Sid Meier's Civilization VII"
  "$HOME/.steam/steam/steamapps/common/Sid Meier's Civilization VII"
  "$HOME/.local/share/Steam/steamapps/common/Sid Meier's Civilization VII"
  "/Applications/Sid Meier's Civilization VII.app/Contents"
  "C:/Program Files (x86)/Steam/steamapps/common/Sid Meier's Civilization VII"
  "C:/Program Files/Epic Games/SidMeiersCivilizationVII"
)

CIV=""
for c in "${CANDIDATES[@]}"; do
  [ -n "$c" ] && [ -d "$c" ] && { CIV="$c"; break; }
done

if [ -z "$CIV" ]; then
  echo "Could not auto-detect the Civ VII install."
  echo "Re-run with the path, e.g.:"
  echo "  CIV_DIR=\"/path/to/Sid Meier's Civilization VII\" bash tools/discover-schema.sh"
  exit 1
fi

# The base game definitions live under Base/Modules (sometimes nested differently
# per platform), so search the whole install for the data folders to be safe.
echo "Install: $CIV"
echo

# Restrict grep to the data definition file types to cut noise.
GREP_INCLUDES=(--include='*.sql' --include='*.xml' --include='*.modinfo')

section() { printf '\n========== %s ==========\n' "$1"; }

# --- 2) Where are endeavors / diplomatic actions defined? -------------------
section "Files that mention 'Endeavor' or 'DiplomaticAction'"
grep -rliE "endeavor|diplomaticaction|diplomacyaction" "${GREP_INCLUDES[@]}" "$CIV" 2>/dev/null \
  | head -40

section "Endeavor/diplomatic-action table names (INSERT/CREATE targets)"
# Surfaces lines like:  INSERT INTO Endeavors (...)  /  <Endeavors>  /  CREATE TABLE ...
grep -rhiE "(insert[[:space:]]+into|create[[:space:]]+table)[[:space:]]+[A-Za-z_]*([Ee]ndeavor|[Dd]iploma)[A-Za-z_]*" \
  "${GREP_INCLUDES[@]}" "$CIV" 2>/dev/null | sort -u | head -40

section "Types 'Kind' values used for endeavors (fills <<KIND_ENDEAVOR>>)"
grep -rhiE "KIND_[A-Z_]*(ENDEAVOR|DIPLOMA)" "${GREP_INCLUDES[@]}" "$CIV" 2>/dev/null \
  | sort -u | head -40

# --- 3) Gold / treasury transfer effect (fills <<EFFECT_TRANSFER_GOLD>>) -----
section "Effect/argument names touching Gold or Treasury"
grep -rhiE "EFFECT_[A-Z_]*(GOLD|TREASURY)|(GOLD|TREASURY)[A-Z_]*(EFFECT|YIELD|TRANSFER)" \
  "${GREP_INCLUDES[@]}" "$CIV" 2>/dev/null | sort -u | head -40

# --- 4) Relationship / diplomacy value effect (fills <<EFFECT_ADJUST_RELATIONSHIP>>)
section "Effect names touching Relationship / Diplomacy score"
grep -rhiE "EFFECT_[A-Z_]*(RELATIONSHIP|DIPLOMAC|FAVOR|ATTITUDE)" \
  "${GREP_INCLUDES[@]}" "$CIV" 2>/dev/null | sort -u | head -40

# --- 5) The modifier plumbing (how effects bind to the endeavor) ------------
section "Schema for the modifier system (GameEffects / ModifierArguments / DynamicModifiers)"
grep -rhiE "create[[:space:]]+table[[:space:]]+(GameEffects|ModifierArguments|DynamicModifiers|Modifiers|EndeavorModifiers)" \
  "${GREP_INCLUDES[@]}" "$CIV" 2>/dev/null | sort -u | head -40

echo
echo "Done. For any table above, see its full column list with the schema file:"
echo "  grep -rl 'CREATE TABLE <TableName>' \"$CIV\""
echo "or open a built database in a SQLite browser if you have run the game once."
