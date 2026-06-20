# Testing & logs: read the game, don't guess

Purpose: the test loop for a Civ 7 (v1.4.0) data mod — where each log lives on Windows, what each one tells you, and a symptom -> meaning table — grounded in the real logs this repo's "Gift Gold" mod produced.

> Cross-references: `dev-environment.md` (junction setup, where Mods lives), `diplomacy-actions.md` (the `DiplomaticActionResponses` reaction model that the `Recipient = -1` symptom diagnoses).

## The test loop

Civ 7 builds the gameplay database **when a game starts** (and on mod reload), not when the app launches. So:

1. **Edit your data/text files** in the repo. If your Mods-folder entry is a junction to the repo (see `dev-environment.md`), edits are live — no copy step. The game notices via timestamp: `Modding.log` logs `File timestamps do not match.  Will reload the mod.` **[Confirmed in files]** (`Modding.log:19`).
2. **Start a NEW game** (not "Continue", not load — a fresh game forces the gameplay DB rebuild). `Modding.log` records `Rebuilding gameplay database.` (`Modding.log:321`) and `Database.log` ends the gameplay phase with a fresh `[gameplay]: Passed Validation.` **[Confirmed in files]** (`Database.log:23-24`).
3. **Reproduce the action** in-game (perform your diplomacy action, build the thing, etc.).
4. **Read the logs** (below). They are **overwritten every launch**, so copy anything you want to keep before relaunching.

> Gotcha — "I changed the XML and nothing happened": you almost certainly didn't start a new game, or the junction isn't pointing at the repo. Confirm the reload in `Modding.log` (step 1) before debugging anything else.

## Where the logs are (Windows)

```
%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VII\Logs
```
i.e. `C:\Users\<you>\AppData\Local\Firaxis Games\Sid Meier's Civilization VII\Logs` **[Confirmed in files]** (~93 `.log`/`.csv` files in this repo's run). Everything below is a file in that directory. They are plain text / CSV — read them with your normal tools.

> This is distinct from the **Mods** folder (`...\AppData\Local\Firaxis Games\Sid Meier's Civilization VII\Mods\`, where the loader discovers your mod — `Modding.log:18`) and from **Saves** (`...\Documents\My Games\...`). Don't confuse the three.

## The four logs you'll actually use

### `Database.log` — did the DB build cleanly?

First stop for any "my data didn't load" problem. The build runs in **phases**, each tagged with a prefix — `[frontend]`, `[localization]`, and `[gameplay]`. **The phase that matters for in-game gameplay data is `[gameplay]`.** A clean gameplay build ends with:

```
[gameplay]: Validating Foreign Key Constraints...
[gameplay]: Passed Validation.
```
**[Confirmed in files]** (`Database.log:23-24`, written when the mod was reloaded for a new game).

> Note the `[localization]: Rebuilding database.` line that precedes it (`Database.log:20`) is the localization phase, **not** the gameplay rebuild. The gameplay rebuild is logged in `Modding.log` as `Rebuilding gameplay database.` (`Modding.log:321`). Don't read the localization "Rebuilding database." line as proof your gameplay data rebuilt — look for the `[gameplay]: Passed Validation.` pair.

Any line of the form `ERROR: Database: ...` is a load failure, and **the message names the offending table/column**. Common shapes:

| Error fragment | Almost always means |
|---|---|
| `no such column: X` | Typo'd or non-existent column in your `<Row>` — check it against `01_GameplaySchema.sql`. |
| `no such table: X` | Wrong table name, or your file's root element wasn't recognized (see Gotcha below). |
| `UNIQUE constraint failed: T.col` | You inserted a row whose primary key already exists (e.g. re-declaring a base `Type`, or two `<Row>`s with the same PK). |
| `FOREIGN KEY constraint failed` | A referenced row doesn't exist **yet** — e.g. a `DiplomacyActions` row before its `Types` row, or a `ModifierId` that no `<Modifier>` defines. Order matters: declare `Types` first. |
| `near "...": syntax error` | Malformed SQL/XML reaching the DB layer. |

> The reference schema is at `Base/Assets/schema/gameplay/01_GameplaySchema.sql` in the game install — every gameplay table and its columns are `CREATE TABLE`'d there (e.g. `DiplomaticActionResponses` at `01_GameplaySchema.sql:1565`). **[Confirmed in files]**

> Note: `Validating Foreign Key Constraints...` on its own is **not** an error — it's the header line that precedes `Passed Validation.` Only treat lines containing `ERROR` as failures. In this repo's run, the only validation-related lines were the benign header + `Passed Validation.` pairs across all three phases — a clean build. **[Confirmed in files]** (`Database.log:1-2`, `:5-6`, `:11-12`, `:23-24`).

> **Gotcha — the silent root-element trap.** The loader picks the parser from the file's **root element**: `<Database>` for table rows, `<GameEffects xmlns="GameEffects">` for modifier-authoring files. A real, slightly alarming line appears in every launch — `[localization]: Database XML root elements must start with either <Database> or <GameEffects>.` (`Database.log:4`, `:22`) — emitted while scanning `StartupErrorMessages.xml`. It is harmless background noise here, **but the same message is exactly what you'd see if *your* file had the wrong root.** If your data didn't apply and the table looks empty, check your root element before anything else.

### `Modding.log` — was the mod discovered, and did its components apply?

Confirms discovery and load:
```
Discovered 1 mods.
New/Reloaded Mods:
civ-simp-gold-gifting (Civ Simp Gold Gifting)
```
**[Confirmed in files]** (`Modding.log:25-27`).

Then, when an **ActionGroup** actually applies, it's listed under `Target in-game actions (in order of application):` (`Modding.log:115`) with a ` * <action-group-id>` line:
```
civ-simp-gold-gifting (Civ Simp Gold Gifting)
 * gift-gold-game
```
**[Confirmed in files]** (`Modding.log:183-184`). `gift-gold-game` is the `<ActionGroup id="gift-gold-game">` from `civ-simp-gold-gifting.modinfo`. If your mod is in the discovery list but you **never** see its ` * <group-id>` line, the ActionGroup's `criteria` didn't match (the mod loaded but applied nothing) — check the criteria, not the data.

> Your mod also appears in the big "Target Mods (in no particular order)" roster (header at `Modding.log:37`; this mod at `:51`) — that only means it's a candidate, not that it applied. The ` * <group-id>` line under "Target in-game actions" is the proof it applied.

### `DiplomacySummary.csv` — did the diplomacy action behave?

One row per diplomacy lifecycle event. Header: `Game Turn, Initiator, Recipient, Action, Details, Mayhem, Visibility` (`DiplomacySummary.csv:1`). **[Confirmed in files]** A healthy multi-party action shows a real **Recipient** id; an action that auto-resolved with no reaction shows **Recipient `-1`**.

**This is the single most diagnostic log for a custom diplomacy action.** Here is the *broken* state this repo captured — Gift Gold initiated by player 0, recipient `-1`, four lines, instant, "Success":

```
2, 0, -1, Diplomacy Action Started, Gift Gold,    0.0
2, 0, -1, Diplomacy Action Enter Stage, Gift Gold Entering Stage DIPLOMACY_GIFT_GOLD_COMPLETE,    0.0
2, 0, -1, Diplomacy Action Support Changed, Gift Gold - P 0 increased support by 1,    0.0
2, 0, -1, Diplomacy Action Ended, Gift Gold result: Success,    0.0
```
**[Confirmed in files]** (`DiplomacySummary.csv:250-253`).

**Read it like this:** `Recipient = -1` + an instant `Started -> Enter Stage -> Ended: result Success` with **no second party ever taking a turn** means the engine concluded **no response was needed** and auto-completed with no recipient reaction. The engine evaluates a `SELECT ... FROM DiplomaticActionResponses` for the action; the `DIPLOMACY_RESPONSE_NOT_NEEDED` path self-completes the action. Both the query string (`... FROM DiplomaticActionResponses ...`) and the enum `DIPLOMACY_RESPONSE_NOT_NEEDED` are present verbatim in the engine binary `Base/Binaries/Win64/Civ7_Win64_DX12_FinalRelease.exe` (alongside `DIPLOMACY_RESPONSE_ACCEPT`, `_REJECT`, `_SUPPORT`). **[Confirmed in files]** (binary string scan). See `diplomacy-actions.md` for the fix — the response/reaction wiring is what's missing, not the data rows.

Contrast — base-game actions that **do** involve a second party carry a real recipient id, never `-1`:
```
3, 4, 2, Diplomacy Action Started, Military Aid,    4.0
6, 4, 2, Diplomacy Action Started, Cultural Exchange,    4.5
```
**[Confirmed in files]** (`DiplomacySummary.csv:521`, `:542`). A real target id (here `2`) is the signal the reaction path engaged.

> **[Confirmed in files / correction to the brief]** In *this* repo's logs, `DiplomacySummary.csv` does **not** print literal `ACCEPT`/`REJECT` words — the reaction is visible as a **real Recipient id vs `-1`**, plus whether the second player ever appears as Initiator of a response. Don't grep for "Accept" here; grep for your action name and inspect the Recipient column.

> Adjacent file — `DiplomacyManager.csv` (header `Game Turn, From, To, Initiator, Type, SubType, Message`, `DiplomacyManager.csv:1`) logs the lower-level request/response handshake, e.g. `Requesting Session (B)` / `Adding to pending` rows (`DiplomacyManager.csv:2-3`). A custom action that never created a real session (the `-1` case) leaves **no** rows here — in this repo, `Gift Gold` appears **0** times in `DiplomacyManager.csv`. **[Confirmed in files]** (grep count 0). Its absence corroborates the auto-complete diagnosis.

### Text & gameplay traces

| Log | What it carries | Note |
|---|---|---|
| `Localization.log` | Text-key load + format-string evaluation. `ERROR: Missing argument N` / `Failed to evaluate parameter N` mean a `LOC_*` string used `{N_...}` placeholders the caller didn't supply. **[Confirmed in files]** (`Localization.log:7-8` — a base-game `{1_turns}` string, illustrating the shape). | Your missing/garbled tooltip text shows up here, not in `Database.log`. In this run the mod's own `GIFT_GOLD` strings produced **no** errors. |
| `Scripting.log` | JS/V8 gameplay-script traces (UI scripts, gameplay scripts). | In this repo (5 lines total) it only logged engine lifecycle (`Shutting down V8-based script engine.`, `Scripting.log:5`) — a pure-data mod with no scripts produces little here. **[Confirmed in files]** |
| `DiplomacyDeals.log` | Deal-level diplomacy traces. | **Situational** — this file was **not present** in this repo's Logs dir during the captured run. Don't assume it always exists; its absence isn't an error. **[Confirmed in files]** |
| `Player_Treasury.csv` | Per-turn `Gold Balance` per player. Header: `Turn, Player, Gold Balance, Unit Maintenance, Building Maintenance, Total Maintenance, Gold Yield` (`Player_Treasury.csv:1`). **[Confirmed in files]** | The place to confirm a **gold** effect actually moved money: diff a player's `Gold Balance` across the turn the action resolved. |

## Did the effect actually FIRE?

"The action completed" and "the effect ran" are different claims. To check whether a specific effect fired, **grep every gameplay log/CSV for the event it should produce** — the yield grant, the favor/grievance event, the relationship change:

- **Gold transfer** -> look for the giver/receiver `Gold Balance` changing in `Player_Treasury.csv` on the resolution turn.
- **Favor / relationship** -> grep the gameplay logs for the favor/grievance event the effect should emit.

**If no such event appears anywhere even though the action "completed", the effect did not run.** In this repo's run, the favor/grievance event the Gift Gold accept should have produced is **absent from every gameplay log** (a directory-wide grep for `FAVOR`/`ENDEAVOR`-family events returned zero matches). **[Confirmed in files]** Combined with the `Recipient = -1` auto-complete, that's a consistent story: the action self-completed with no acceptance, so the **accept-gated** effects (the gold wrapper and the favor) never attached. The most common reason an effect silently doesn't fire is exactly this — it's gated on an accept that never happened (see `diplomacy-actions.md`).

> Gotcha — grep the telemetry logs out. `twokdna.log`, `Telemetry.log`, and the `AI_*.csv` files carry enum/string dumps that can match almost any term and produce false positives. When checking "did my effect fire", trust gameplay logs (`DiplomacySummary.csv`, `Player_Treasury.csv`, `DiplomacyManager.csv`, the relevant `.log`), not a raw match count across the whole directory.

## Symptom -> meaning quick reference

| Symptom (where you see it) | Meaning | First move |
|---|---|---|
| `Database.log`: no `[gameplay]: Passed Validation.` after a new game | Gameplay DB didn't build / your file aborted the build | Scan for `ERROR: Database:` — it names the table. |
| `Database.log`: `ERROR ... no such column/table` | Wrong column/table name, or unrecognized root element | Check against `01_GameplaySchema.sql`; verify root is `<Database>` or `<GameEffects>`. |
| `Database.log`: `UNIQUE constraint failed` | Duplicate primary key (re-declared `Type`, repeated `<Row>`) | Remove the duplicate; don't re-`<Row>` an existing base `Type`. |
| `Database.log`: `FOREIGN KEY constraint failed` | Referenced row/`ModifierId`/`Type` doesn't exist yet | Declare `Types` first; ensure every referenced id is defined. |
| `Modding.log`: mod discovered but no ` * <group-id>` line | ActionGroup `criteria` didn't match — nothing applied | Fix the `criteria`, not the data. |
| `Modding.log`: mod absent from "New/Reloaded Mods" | Mod not discovered (junction/path/`.modinfo` problem) | Check the Mods-folder junction and `.modinfo` location. |
| Edited XML, no change in game | You didn't start a **new** game (DB not rebuilt) | New game; confirm `File timestamps do not match` + fresh `[gameplay]: Passed Validation`. |
| `DiplomacySummary.csv`: your action, `Recipient = -1`, instant `Started -> Ended: Success` | Engine hit `DIPLOMACY_RESPONSE_NOT_NEEDED`; auto-completed, no reaction | Wire up the accept/decline reaction (see `diplomacy-actions.md`). |
| `DiplomacySummary.csv`: real Recipient id, second player reacts | Reaction path engaged correctly | Good — now verify the effect fired. |
| Action "completed" but no yield/favor event anywhere in gameplay logs | Effect never ran (often accept-gated, no accept occurred) | Check the action wasn't `-1` auto-completing; verify the effect's gating. |
| Gold action completed but treasuries unchanged in `Player_Treasury.csv` | Gold effect didn't apply (often the accept-gate again) | Confirm a real accept happened; re-check the accept-gated wrapper. |
| `Localization.log`: `Missing argument N` / `Failed to evaluate parameter N` | A `LOC_*` string expects `{N_...}` params the caller didn't pass | Fix the text placeholders or the call site. |

## Verified evidence map

| Claim | Evidence |
|---|---|
| Logs dir path | `%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VII\Logs` (directory listing) |
| Clean gameplay build line | `Database.log:23-24` (`[gameplay]: Passed Validation.`) |
| Gameplay DB rebuilds on new game | `Modding.log:321` (`Rebuilding gameplay database.`) |
| Localization-phase rebuild (not the gameplay one) | `Database.log:20` (`[localization]: Rebuilding database.`) |
| Schema file location + table | `Base/Assets/schema/gameplay/01_GameplaySchema.sql:1565` (`DiplomaticActionResponses`) |
| Root-element warning is real engine text | `Database.log:4`, `:22` |
| Mod reload via timestamp | `Modding.log:19` |
| Mod discovered | `Modding.log:25-27` |
| ActionGroup applied marker | `Modding.log:115` (header), `:183-184` (` * gift-gold-game`) |
| `Recipient = -1` auto-complete signature | `DiplomacySummary.csv:250-253` |
| Real-target base actions | `DiplomacySummary.csv:521`, `:542` |
| `DIPLOMACY_RESPONSE_NOT_NEEDED`, `_ACCEPT`, `_REJECT` + `FROM DiplomaticActionResponses` are engine strings | `Civ7_Win64_DX12_FinalRelease.exe` binary scan (all matched) |
| No `Gift Gold` rows in `DiplomacyManager.csv` | grep count 0 |
| `DiplomacyDeals.log` absent during run | directory listing (not present) |
| Treasury columns for gold verification | `Player_Treasury.csv:1` |
| Favor/endeavor event absent from all gameplay logs | dir-wide grep for `FAVOR`/`ENDEAVOR` -> 0 matches |
| Localization format-string error shape | `Localization.log:7-8` |
| Scripting engine lifecycle only | `Scripting.log:5` |