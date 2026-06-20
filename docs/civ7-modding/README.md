# Civilization VII modding — field notes

A working knowledge base for building **Civ VII (v1.4.0) mods**, written so the next
developer (human or AI) gets productive fast and skips the troubleshooting we did the hard
way. Every technical claim here was checked against the actual game files, and carries a
confidence tag where it matters: **[confirmed in-game]**, **[confirmed in files]**,
**[inferred]**, **[unverified]**.

This grew out of building [`civ-simp-gold-gifting`](../../) (a mod that adds a "Gift Gold"
diplomacy action). That repo is the **worked example** referenced throughout, and
[`../schema-notes.md`](../schema-notes.md) holds the action-specific schema notes for it.

> **The one rule that saves the most time:** the game install is the source of truth, not
> the web (most online results are Civ 6, which differs). When unsure, grep the install and
> read the binary. See [`finding-the-truth.md`](finding-the-truth.md).

## Start here (reading path)

1. **[`finding-the-truth.md`](finding-the-truth.md)** — the methodology. Read this first; it
   changes how you approach everything else.
2. **[`mod-anatomy.md`](mod-anatomy.md)** — the `.modinfo` manifest, action groups/scopes,
   and how `UpdateDatabase`/`UpdateText` load your files.
3. **[`data-and-gameeffects.md`](data-and-gameeffects.md)** — the two XML dialects
   (`<Database>` table rows vs `<GameEffects>` modifiers) and the modifier system.
4. **[`localization.md`](localization.md)** — text via `<EnglishText>` (not the Civ 6 table).
5. **[`dev-environment.md`](dev-environment.md)** — install/Mods paths and the junction
   live-edit dev loop.
6. **[`testing-and-logs.md`](testing-and-logs.md)** — the test loop and how to read every log.

Then, for the domain we went deep on:

7. **[`diplomacy-actions.md`](diplomacy-actions.md)** — diplomacy actions, the **reaction
   mechanism** (the most expensive lesson), and accept-gating.
8. **[`effects-and-modifiers.md`](effects-and-modifiers.md)** — yields, favors, attach
   modifiers, and reading the engine binary for an effect's real arguments.
9. **[`multiplayer.md`](multiplayer.md)** — desync safety (data vs script).

## When something breaks

- **[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)** — symptom → cause → fix table. Start here.
- **[`GOTCHAS.md`](GOTCHAS.md)** — the traps we hit, in discovery order, each preserving the
  *reasoning* (not just the fix).

## The cross-cutting laws

These bite everyone; they're repeated in the relevant docs but worth stating once:

1. **Test by starting a NEW game.** The gameplay database builds at new-game time; a save
   reload does not pick up data changes.
2. **Omitted columns take the schema `DEFAULT`,** not 0/off. Check the `CREATE TABLE` in
   `Base/Assets/schema/gameplay/01_GameplaySchema.sql` before reasoning about a column.
3. **Mirror a working base action end-to-end** rather than inventing wiring.
4. **Engine-bound effects (`EFFECT_DAE_*`) hide their arguments in the binary,** not in data.
5. **A clean load ≠ correct behavior.** The DB can pass validation while an effect silently
   no-ops; confirm behavior in-game and in the logs.

## How to keep this alive (for the next contributor — including future me)

This is a *living* system. When you learn something new while modding:

1. **Append a dated entry to [`GOTCHAS.md`](GOTCHAS.md)** describing the trap, what actually
   happened, and the takeaway — with a confidence tag.
2. **Promote durable conclusions** into the relevant topic doc (with a `path:line` citation
   to the game files) and add a row to **[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)** if it's
   a recognizable symptom.
3. **Tag confidence honestly.** "I saw it work" (`[confirmed in-game]`) is very different from
   "the binary lists this argument" (`[inferred]` until tested). Mislabeled confidence is how
   wrong lore spreads.
4. **Cite evidence** as `path:line` against the install (and quote the real row/string), so
   the next reader can re-verify instead of trusting prose.
5. **Correct, don't just append.** If something here turns out wrong, fix it in place and note
   the correction — `diplomacy-actions.md` already corrects an earlier wrong belief this way.

Keep entries concrete and skimmable. The goal is always: *less troubleshooting for the next
person.*
