# Civ Simp Gold Gifting

A Civilization VII mod that adds a diplomatic endeavor letting a player gift Gold directly to
another player, improving the relationship between them.

- **Mod id:** `civ-simp-gold-gifting`
- **Target game version:** 1.4.0 (Test of Time)

## Status

Phase 1 scaffold. The manifest, localization, and project structure are complete. The endeavor
body in `data/gift-gold-endeavor.sql` is a template: the table and column names there are schema
specific to 1.4.0 and are marked with `<< >>` tokens that must be replaced with the real names
from the installed base game modules. The file is written to fail loudly rather than load a wrong
guess.

## Structure

```
civ-simp-gold-gifting/
  civ-simp-gold-gifting.modinfo   manifest, registers actions in game + shell scope
  data/
    gift-gold-endeavor.sql        endeavor definition (template, fill in schema)
  text/
    en_us/
      gift-gold-text.sql          localized name + description
```

## Filling in the endeavor schema

1. Open `<CivInstall>/Base/Modules` and find the module defining the existing cooperative
   endeavors. Look in its `data` folder.
2. Identify: how an endeavor type is declared, the effect that transfers Gold between players, and
   the effect or modifier that adjusts a relationship value.
3. Replace every `<< >>` token in `data/gift-gold-endeavor.sql` with the confirmed names.
4. Start a new game to verify (database changes apply at database build time, so a reload is not
   enough).

## Phase 2 (designed, not built)

Dynamic behaviour, to be added later via gameplay scripting:

- Scale the relationship gain by how much the gift helps the receiver (prefer gift amount over a
  few turns of the receiver's Gold income, rather than raw treasury), with diminishing returns and
  a cap.
- Factor the giver's sacrifice relative to their own wealth.
- If the receiver is at war with a third leader, gifting them Gold deteriorates the giver's
  relationship with that third leader, scaled by the same significance.

This needs the runtime scripting surface, which is poorly documented and carries a multiplayer
desync risk, so it stays separate from the data driven Phase 1.

## Versioning

The `version` in the manifest tracks SemVer git tags. Tag `v0.1.0` once the mod loads and shows as
Activated; `v0.2.0` once the flat endeavor works in a new game.
