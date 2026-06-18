# Schema notes — filling the `<< >>` tokens

Status as of 2026-06-18. The endeavor body in `data/gift-gold-endeavor.sql` is a
template; this file records what is **confirmed** versus what still needs the
installed base game (1.4.0) to nail down. Run `tools/discover-schema.sh` on the
machine with Civ VII installed to resolve the unknowns automatically.

## Confirmed (safe to rely on)

- **`Types (Type, Kind)`** — Civ VII declares a `Type` row with a `Kind` before
  referencing it elsewhere. The `INSERT INTO Types` in the endeavor file is the
  right shape; only the `Kind` *value* (`<<KIND_ENDEAVOR>>`) is unconfirmed.
- **`LocalizedText (Tag, Language, Text)`** — `text/en_us/gift-gold-text.sql`
  uses the correct table and columns. No change expected.
- **Effects use the modifier system, not loose effect rows.** Civ VII wires
  gameplay effects through `GameEffects`, `ModifierArguments (ModifierId, Name,
  Value)`, and `DynamicModifiers` — confirmed across CivFanatics Civ 7 modding
  threads. So tokens #3–#5 in the endeavor file (the `<<EFFECT_TABLE>>` inserts
  and the bind step) will most likely restructure into:
  a modifier row → its `ModifierArguments` (e.g. `Amount`, `YieldType`) →
  a `DynamicModifiers` entry tying a `ModifierType` to a `CollectionType` and
  `EffectType` → the endeavor referencing that modifier. The discovery script
  dumps the exact table/column names so this can be written against reality.

## Unknown — needs `tools/discover-schema.sh` against the install

| Token | What it is | How the script finds it |
|---|---|---|
| `<<KIND_ENDEAVOR>>` | `Kind` value for endeavor/diplo Types | "Types 'Kind' values" section |
| `<<ENDEAVOR_DEFINITION_TABLE>>` + cols | table defining an endeavor | "table names" section |
| `<<EFFECT_TRANSFER_GOLD>>` | effect that moves Gold treasury→treasury | "Gold or Treasury" section |
| `<<EFFECT_ADJUST_RELATIONSHIP>>` | effect that changes a relationship score | "Relationship / Diplomacy" section |
| bind step (#5) | how an effect/modifier attaches to the endeavor | "modifier system" section + an existing base endeavor as a worked example |

## Why not just guess

The file is intentionally written to fail loudly. Civ VII's endeavor/diplomacy
schema is poorly documented publicly (most online results are Civ VI, whose
`DiplomaticActions` table does **not** carry over). Guessing a wrong table name
loads silently-wrong or errors confusingly; reading one real base-game endeavor
end-to-end is faster and correct.

## Recommended path once names are known

1. Run the discovery script; copy the real names in.
2. Find ONE existing cooperative endeavor in the base modules and mirror its
   full wiring (Type → definition → modifier(s) → bind) for `ENDEAVOR_GIFT_GOLD`.
3. Start a **new game** (DB builds at new-game time) and confirm the mod shows as
   Activated and the endeavor appears. Tag `v0.2.0` when the flat version works.

## Sources consulted

- CivFanatics — Civ 7 Modding Questions: https://forums.civfanatics.com/threads/civ-7-modding-questions.695200/
- CivFanatics — Dynamic modifiers, effects, collections and arguments: https://forums.civfanatics.com/threads/chapter-2-dynamic-modifiers-effects-collections-and-arguments.608917/
- izica/civ7-modding-tools: https://github.com/izica/civ7-modding-tools
- mateicanavra/civ7-modding-tools: https://github.com/mateicanavra/civ7-modding-tools
