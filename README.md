# Civ Simp Gold Gifting

A Civilization VII mod that adds a diplomatic action, **Gift Gold**, letting a player gift Gold
directly to *any* met leader (not only allies) and improving the relationship between them.

- **Mod id:** `civ-simp-gold-gifting`
- **Target game version:** 1.4.0 (Test of Time)

> 📚 **Modding a Civ 7 mod yourself?** This repo doubles as a knowledge base. See
> [`docs/civ7-modding/`](docs/civ7-modding/README.md) — a verified field guide (mod anatomy,
> the diplomacy-action system, effects, testing/logs, a symptom→fix
> [troubleshooting table](docs/civ7-modding/TROUBLESHOOTING.md), and a
> [gotchas log](docs/civ7-modding/GOTCHAS.md)) written so the next developer skips the
> troubleshooting we did the hard way.

## Status

**Phase 1, in test.** The mod adds a new diplomacy action `DIPLOMACY_ACTION_GIFT_GOLD`: an
**offer** to gift a fixed amount of Gold to **any met major leader** (not just allies). The receiver
can **accept or decline**; on accept, Gold moves from giver to receiver and the relationship
improves, on decline nothing happens.

The schema was reverse-engineered from the installed base game (see `docs/schema-notes.md`). A few
engine-bound behaviors can only be confirmed in-game and are flagged inline in
`data/gift-gold-effects.xml` (notably: whether a negative Gold grant debits the giver, and whether
an ACCEPT-side response modifier fires the relationship favor).

## How it works (and the engine constraint that shaped it)

Civ VII has **no generic "endeavor" table**. Player-to-player cooperative actions are
**diplomacy actions** (`Kind = KIND_DIPLOMACY_ACTION`). The base game ships
`DIPLOMACY_ACTION_SEND_GOLD` ("Send Aid"), which gifts Gold but only to an **ally**.

The catch, found by testing: the ally restriction is **compiled into the engine operation**
`SEND_GOLD_DIPLOMATIC_ACTION` (`m_bRequiresAlliance`/`FAILURE_NOT_ALLIES`), not the `AllyOnly` data
column — and that same operation is the **only** source of the runtime "choose an amount" Gold
picker. So you cannot both target non-allies and keep the picker in pure data. The mod is therefore
built by mirroring `DIPLOMACY_ACTION_IMPROVE_TRADE_RELATIONS` — the one base action that is
non-ally, instant, declinable, and delivers Gold to the target on accept:

- uses `COOPERATIVE_YIELDS_DIPLOMATIC_ACTION` (the operation behind non-ally endeavors), so **any
  met major leader** is a valid target (`Target2Type` is `NONE`); the `RequestString` makes the
  engine raise an **accept/decline** window for the receiver;
- gifts a **fixed amount** of Gold (currently 100) only on accept, via an accept-gated attach
  wrapper (`EFFECT_DAE_COOPERATIVE_ATTACH_MODIFIER`) whose children grant the recipient +100 and
  debit the giver −100 with one-time `EFFECT_PLAYER_GRANT_YIELD`;
- improves the relationship via `EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES`
  (`FAVOR_FROM_ENDEAVOR`), bound to the **ACCEPT** response so it can't fire on a decline.

Trade-off vs. the original design: **no in-game amount slider** (engine-limited — it was welded to
the ally-only operation). If amount choice matters, the data-only option is a few fixed-tier actions
(Gift 100 / 250 / 500); an arbitrary slider for non-allies would need custom UI scripting.

## Structure

```
civ-simp-gold-gifting/
  civ-simp-gold-gifting.modinfo   manifest; loads the data + text in game scope
  data/
    gift-gold-action.xml          the diplomacy action (<Database> rows, mirrors SEND_GOLD)
    gift-gold-effects.xml         the modifiers (<GameEffects>: gold transfer + favor grant)
  text/
    en_us/
      gift-gold-text.xml          localized name/description (<EnglishText> rows)
  docs/
    schema-notes.md               what was confirmed against the 1.4.0 install
  tools/
    discover-schema.sh            greps the install for the schema (used during bring-up)
```

## Testing

Database changes apply at **database build time**, so a reload is not enough — start a **new game**.

1. Install: copy this folder into your Civ VII Mods directory
   (`%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VII\Mods` on Windows), or symlink it.
2. Enable the mod in the in-game Mods menu.
3. Start a **new game** with at least one other major leader.
4. Meet that leader, open diplomacy, and look for **Gift Gold** in the endeavors/actions list.
   Confirm: (a) it is offered even when you are *not* allied, (b) Gold moves from you to them,
   (c) your relationship value ticks up.
5. If the Gold transfers but the relationship does **not** change, the favor argument name is the
   likely cause — see the inline note in `data/gift-gold-effects.xml` and `docs/schema-notes.md`.

When the favor is confirmed to apply in a new game, tag `v0.2.0`.

## Phase 2 (designed, not built)

Dynamic behaviour, to be added later via gameplay scripting:

- Scale the relationship gain by how much the gift helps the receiver (prefer gift amount over a
  few turns of the receiver's Gold income, rather than raw treasury), with diminishing returns and
  a cap.
- Factor the giver's sacrifice relative to their own wealth.
- If the receiver is at war with a third leader, gifting them Gold deteriorates the giver's
  relationship with that third leader, scaled by the same significance.

This needs the runtime scripting surface, which is poorly documented and carries a multiplayer
desync risk, so it stays separate from the data-driven Phase 1.

## Versioning

The `version` in the manifest tracks SemVer git tags. Tag `v0.1.0` once the mod loads and shows as
Activated; `v0.2.0` once the flat Gift Gold action works (gold + relationship) in a new game.
