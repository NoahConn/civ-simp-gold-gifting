# Troubleshooting: symptom → cause → fix

The fast lookup. Find your symptom, jump to the likely cause, apply the fix. Deeper
explanations live in the linked section docs. Confidence tags: **[seen]** = we hit this
and fixed it this session; **[files]** = grounded in the game files; **[inferred]** = best
current understanding, verify in-game.

> First rule when anything is off: **read the logs.** See [`testing-and-logs.md`](testing-and-logs.md).
> `%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VII\Logs\` — start with `Database.log`
> and `Modding.log`, then the gameplay-specific ones.

## Loading / build

| Symptom | Likely cause | Fix |
|---|---|---|
| `ERROR: Database: ...` in `Database.log` (UNIQUE / FK / "no such column" / syntax) **[seen]** | A `<Row>` uses a nonexistent column, omits a `NOT NULL`-no-default column, references an undeclared `Type`, or a PK collision | The error names the table. Verify every attribute against that table's `CREATE TABLE` in `01_GameplaySchema.sql`; declare `Types` rows before referencing them. See [`data-and-gameeffects.md`](data-and-gameeffects.md) |
| `Database XML root elements must start with either <Database> or <GameEffects>` | A loaded file has a wrong/missing root element | A data file must be rooted `<Database>` (table rows) or `<GameEffects xmlns="GameEffects">` (modifiers). (Note: this message also appears harmlessly in vanilla load — only worry if it names your file) |
| Mod absent from the in-game Add-Ons list | `.modinfo` not at the mod folder root, or malformed | The folder under `Mods\` must contain `<id>.modinfo` at its root. Confirm `Modding.log` shows it discovered |
| Changes don't appear in game **[seen]** | Didn't **start a new game** (the DB builds at new-game time, not on reload); OR your dev junction got overwritten by a copy | Start a NEW game. If you dev via a Mods-folder junction, confirm it's still a junction (a copy installer can replace it). See [`dev-environment.md`](dev-environment.md) |

## The action doesn't behave

| Symptom | Likely cause | Fix |
|---|---|---|
| Action loads but never appears in the diplomacy UI | `DiplomaticProjects_UI_Data` row missing/mis-grouped, or `RequiresUnlock="true"` with no unlock granted | Add/repair the UI_Data row; set `RequiresUnlock="false"` for an always-available action |
| **"No Valid Targets"** when you pick the action **[seen]** | You reused an **ally-gated engine operation** (`SEND_GOLD_DIPLOMATIC_ACTION`) for a non-ally action — its alliance gate is compiled in (`m_bRequiresAlliance`) and `AllyOnly="false"` can't override it | Switch `PlayerOperationType` to `COOPERATIVE_YIELDS_DIPLOMATIC_ACTION` (the non-ally op). Trade-off: you lose that op's runtime gold-amount picker. See [`diplomacy-actions.md`](diplomacy-actions.md) |
| Action **fires (plays a sound) but instantly auto-completes** — no accept/decline window, `DiplomacySummary.csv` shows **`target=-1`** **[seen]** | No row in the **`DiplomaticActionResponses`** table → the engine resolves `DIPLOMACY_RESPONSE_NOT_NEEDED` and self-resolves on the initiator | Add `DiplomaticActionResponses` rows (`DIPLOMACY_RESPONSE_ACCEPT`, and `_REJECT` for a decline button). This table — not `DiplomaticActionResponseModifiers` — is what creates the response. See [`diplomacy-actions.md`](diplomacy-actions.md) |
| It now reacts, but **no effects happen** on accept **[seen]** | Effects are accept-gated children of an attach modifier but the accept never reached them; or the effect/args are wrong | Confirm the reaction actually fires (logs show a real target + `ACCEPT`). Then check the effect wiring below |
| An `ACCEPT`-side `DiplomaticActionResponseModifiers` row seems to do nothing **[files]** | Base data only ever binds **`REJECT`** rows in that table; `ACCEPT`-side firing is unproven | Gate on accept via an attach-modifier child instead, or `REQUIREMENT_PLAYER_INITIATED_DIPLOMACY_ACTION_RESPONSE_TYPE_MATCHES` (Machiavelli pattern) |

## Effects (gold / relationship)

| Symptom | Likely cause | Fix |
|---|---|---|
| Recipient's gold **drains every turn** instead of once | Used `EFFECT_PLAYER_ADJUST_YIELD` (a **per-turn rate**) where you wanted a one-time grant | Use `EFFECT_PLAYER_GRANT_YIELD` (one-time lump). See [`effects-and-modifiers.md`](effects-and-modifiers.md) |
| **Giver doesn't lose gold** on a "transfer" **[seen/inferred]** | A negative `EFFECT_PLAYER_GRANT_YIELD` (`-100`) has no base precedent and may be clamped to 0 | Use a purpose-built debit effect (`EFFECT_DAE_*CHANGE_INITIATOR_GOLD` with `RemoveGold`), or accept a one-sided gift |
| Recipient gold goes to the **wrong player** | A grant on `COLLECTION_OWNER` credits the initiator unless it's a **TargetPlayerAccept child** of an attach modifier (which reassigns owner to the target) | Route recipient yield through `EFFECT_DAE_TARGET_ATTACH_MODIFIER` → `TargetPlayerAccept` → grant child |
| **Relationship doesn't change** **[seen/inferred]** | `EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES` with `FavorsAmount`/`TargetFavorsAmount` — those arg names exist in the binary but appear in **no base data**, so the effect may ignore them | Prefer the `DiplomacyActions` **`TargetFavors`/`SupportFavors`/`TargetFavorsFreq` columns** (how base actions grant positive relationship); verify in-game |
| `EFFECT_DAE_SEND_GOLD` transfers nothing | That effect has **no amount argument** — the amount came from the `SEND_GOLD` operation's picker; detached from that op it does nothing | Use a yield-grant effect with an explicit `Amount` instead |

## Localization

| Symptom | Likely cause | Fix |
|---|---|---|
| UI text is **blank or shows the raw `LOC_` tag** | Used the Civ 6 `LocalizedText (Tag, Language, Text)` SQL table, **or** referenced an undefined tag (a quiet, non-fatal failure) | Use `<Database><EnglishText><Row Tag><Text>` loaded via `<UpdateText>`; make sure every referenced `LOC_` tag is defined. See [`localization.md`](localization.md) |

## Multiplayer

| Symptom | Likely cause | Fix |
|---|---|---|
| Match won't start together | Players have **different mods or versions** enabled | Both players need the identical mod + version. Re-distribute and re-install on updates |
| Desync after a custom gameplay effect **[inferred]** | A **JS/Lua gameplay script** mutating state diverged between clients | Prefer data/engine-applied effects (desync-safe); if scripting, keep it deterministic. See [`multiplayer.md`](multiplayer.md) |

## Meta

| Symptom | Likely cause | Fix |
|---|---|---|
| An online guide's approach doesn't work | It's probably **Civ 6** (its `DiplomaticActions` schema etc. did **not** carry over) | Verify against the install, not the web. See [`finding-the-truth.md`](finding-the-truth.md) |
| "We didn't set column X, so it must be 0/off" turned out false **[seen]** | Omitted columns take the **schema `DEFAULT`** (e.g. `UIStartProject` DEFAULT 1, `SupportFavors` DEFAULT 100) | Always check the `CREATE TABLE` default before theorizing about a column's value |
