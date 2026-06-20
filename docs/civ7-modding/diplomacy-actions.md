# Diplomacy actions: the system, the reaction mechanism, accept-gating

How player-to-player cooperative actions are wired in Civ 7 v1.4.0, why the target sometimes never gets an accept/decline window, and how to make effects fire only on accept — the part of the system where this mod lost the most time.

Worked examples: base `DIPLOMACY_ACTION_SEND_GOLD` ("Send Aid"), `DIPLOMACY_ACTION_IMPROVE_TRADE_RELATIONS`, `DIPLOMACY_ACTION_MILITARY_AID`, and this repo's `civ-simp-gold-gifting/data/gift-gold-action.xml` + `gift-gold-effects.xml`. See `diplomacy-effects-and-modifiers.md` for the `GameEffects`/`Modifier` layer and `modinfo-and-loading.md` for how files load. (Those two sibling files are forward references in this `civ7-modding/` set.)

Paths below are relative to the game install (`…/Sid Meier's Civilization VII/`); schema line numbers are from `Base/Assets/schema/gameplay/01_GameplaySchema.sql`; base data line numbers are from `Base/modules/base-standard/data/diplomacy-actions.xml` (the "base file") unless another file is named.

---

## 1. There is no "endeavor" table — these are diplomacy actions

Player-to-player cooperative actions (the things the UI calls "endeavors") are **diplomacy actions**. There is no generic `Endeavors` table. An action is a `Type` of `Kind=KIND_DIPLOMACY_ACTION`; each of its stages is a `Type` of `Kind=KIND_DIPLOMACY_ACTION_STAGE`. **[Confirmed in files]** base file `:4` (`KIND_DIPLOMACY_ACTION`), `:8` (`KIND_DIPLOMACY_ACTION_STAGE`), `:25` (`DIPLOMACY_ACTION_LAND_CLAIM` declared as `KIND_DIPLOMACY_ACTION`).

Every `Type` referenced anywhere must be declared in `<Types>` first, or the foreign-key cascade in the schema rejects the row. `DiplomacyActions.DiplomacyActionType` → `Types(Type) ON DELETE CASCADE` (`schema:1438`). The `Types` table itself is defined at `schema:3880`. **[Confirmed in files]**

## 2. The table set for one action

To define one working action you touch these tables (all keyed on `DiplomacyActionType` unless noted). "Schema" = the `CREATE TABLE` line in `01_GameplaySchema.sql`.

| Table | Schema | Role |
|---|---|---|
| `Types` | 3880 (FK from `DiplomacyActions` at 1438) | Declare the action Type + each stage Type. |
| `DiplomacyActions` | 1392 | The definition row: `Name`, `BaseDuration` (1396), `BaseTokenCost` (1397), `AllyOnly` (1394), `RequestString` (1420), `RejectionRefundsInfluence` (1418), `UIIconPath` (1434), etc. |
| `DiplomaticActionValidTokens` | 1606 | Which influence-token slot the action consumes (e.g. `DIPLOMACY_TOKEN_GLOBAL`). |
| `DiplomaticActionStages` | 1586 | One row per stage; `ProgressRequirement` (1599) per stage. |
| `EnterStageModifiers` | 1777 | Binds a `ModifierId` to fire when a stage is entered. |
| `DiplomaticProjects_UI_Data` | 1624 | `PlayerOperationType` (1639), `DiplomacyActionGroup` (1632), `Target1Type`/`Target2Type` (1641/1642), envoy counts, `UIStartProject` (**default 1**, 1647), `UIShowActiveProject` (default 1, 1646). |
| `DiplomacyBonusEnvoyData` | 1484 | Per-relationship envoy bonus knobs (usually all 0 for endeavors). |
| `DiplomaticActionInfluenceCosts` | 1549 | Influence cost to *perform* at each relationship level. |
| `DiplomaticActionResponses` | 1565 | **The reaction gate.** Per-action ACCEPT/REJECT/SUPPORT rows. See §3. |
| `DiplomaticActionResponseModifiers` | 1576 | Effects attached *after* a response is chosen. A different table — see §3. |
| `DiplomacyFavorsGrievancesEventsData` | 1497 | Registers named relationship events (e.g. `FAVOR_FROM_ENDEAVOR`). |

Supporting/registry tables you reference but rarely add to: `DiplomacyActionGroups` (schema 1441; base rows at `:368`), `DiplomacyActionGroupSubtypes` (1447), `DiplomaticResponses` (schema 1653 — the response-*type* name registry, base rows at `:924-928`, distinct from `DiplomaticActionResponses`), `DiplomacyPlayerRelationships` (1521).

---

## 3. *** The reaction mechanism (the most expensive lesson) ***

**Confirmed: whether the TARGET gets an accept/decline window is decided by the engine, gated on the action having a row in `DiplomaticActionResponses`.** With no row, the engine resolves `DIPLOMACY_RESPONSE_NOT_NEEDED` and the action silently auto-completes with no target reaction.

### Evidence from the binary
The engine runs literal queries against `DiplomaticActionResponses`. Extracted (verbatim) from `Base/Binaries/Win64/Civ7_Win64_DX12_FinalRelease.exe`: **[Confirmed in files]**

```
SELECT count(*) from DiplomaticActionResponses
SELECT rowid, DiplomacyActionType, DiplomaticResponseType, CostDescription,
       Description, InfCost, Name FROM DiplomaticActionResponses ORDER BY rowid
```
loaded by `…/Definitions/Definition_DiplomaticActionResponse.cpp` (the `.cpp` path is also a literal in the binary). The response enum strings are all present: `DIPLOMACY_RESPONSE_ACCEPT`, `DIPLOMACY_RESPONSE_REJECT`, `DIPLOMACY_RESPONSE_SUPPORT`, **`DIPLOMACY_RESPONSE_NOT_NEEDED`**, `INVALID_RESPONSE`. The engine builds the response buttons from the rows it finds; finding none yields `NOT_NEEDED` → instant auto-success. (Repo symptom log: `target=-1`, instant Success, on every test before the rows were added — see `gift-gold-action.xml:118`.) **[Confirmed in files]** for the SQL, the `.cpp` loader name, and the enum; **[Inferred]** for the exact `NOT_NEEDED` control-flow (the strings + the symptom corroborate it; the compiled branch was not disassembled).

### What it is NOT gated by
- **Not `DiplomacyActionGroup`.** `SEND_GOLD` reacts even though it is in `DIPLOMACY_ACTION_GROUP_ENDEAVOR` (`:779`); it reacts because of its response row (`:936`), not its group.
- **Not `PlayerOperationType`.** See §5 — the operation governs targeting/validation, not the reaction window.
- **Not `UIStartProject`.** That column defaults to `1`/true (`schema:1647`); it is not the trigger.
- **Not `RequestString`, and not `AlwaysNotifyTarget`.** `AlwaysNotifyTarget` (`schema:1395`, default 0) is **used by zero base data rows** (`grep` of `Base/**/*.xml` returns nothing), so it is not the reaction trigger. `RequestString` only supplies the offer text shown *if* a window opens.

### The worked rows
- `SEND_GOLD` reacts solely via its ACCEPT row (`:936`):
  ```xml
  <Row DiplomacyActionType="DIPLOMACY_ACTION_SEND_GOLD"
       DiplomaticResponseType="DIPLOMACY_RESPONSE_ACCEPT" InfCost="0"
       Name="LOC_DIPLOMACY_RESPONSE_ACCEPT" Description="LOC_DIPLOMACY_PROJECT_SEND_GOLD_ACCEPT"/>
  ```
- `FORM_ALLIANCE` has explicit ACCEPT **and** REJECT (`:941-942`).

### ⚠️ Correction to a widespread misconception (and to this repo's own comments)
A natural-but-wrong conclusion — written into `civ-simp-gold-gifting/data/gift-gold-action.xml:19-24` — is that declinability is "emergent" from `RequestString`/`AllyOnly` and that "the base game's declinable endeavors (e.g. `IMPROVE_TRADE_RELATIONS`) carry **zero** `DiplomaticActionResponses` rows." **That is false.** It looks true if you only read the base file, where `IMPROVE_TRADE_RELATIONS`/`MILITARY_AID`/`MINOR_TRADE` appear in `DiplomaticActionResponseModifiers` (as REJECT) but not in `DiplomaticActionResponses` — `MINOR_TRADE` at `:972-973`, `MILITARY_AID` at `:984-985`, `IMPROVE_TRADE_RELATIONS` at `:987-988`. Their actual ACCEPT/REJECT response rows live in the **per-age** files, with age-scaled reject costs: **[Confirmed in files]**

| Action | Age file (`Base/modules/age-*/data/diplomacy-actions.xml`) | Rows |
|---|---|---|
| `IMPROVE_TRADE_RELATIONS` | age-antiquity | `:132-133` (ACCEPT + REJECT InfCost 60) |
| `IMPROVE_TRADE_RELATIONS` | age-exploration | `:192-193` (REJECT 120) |
| `IMPROVE_TRADE_RELATIONS` | age-modern | `:174-175` (REJECT 180) |
| `MILITARY_AID` | age-antiquity | `:110-112` (SUPPORT / ACCEPT / REJECT) |
| `MINOR_TRADE` | age-antiquity | `:98-100` (SUPPORT / ACCEPT / REJECT) |

So the rule is universal: **every declinable endeavor has `DiplomaticActionResponses` rows.** They are just split across age modules (data is additive at load). The mod *ships* correctly anyway, because `gift-gold-action.xml:125-128` does declare ACCEPT + REJECT — but trust the rows, not the stale comment above them.

### `DiplomaticActionResponseModifiers` is a different table
It attaches a modifier **after** a response is chosen; it does **not** create the response. **[Confirmed in files]** the engine loads it separately (verbatim binary query):
```
SELECT rowid, DiplomacyActionType, DiplomaticResponseType, ModifierId, ModifierTarget,
       ModifierType FROM DiplomaticActionResponseModifiers ORDER BY rowid
```
via `Definition_DiplomaticActionResponseModifier.cpp`. In active base data it is bound **exclusively to REJECT** — to apply grievances / block-future-action penalties on a decline (`:959-1006`; e.g. `PLAYER_DIPLOMACY_GRIEVANCES_FOR_ACTION_REJECTION`, `PLAYER_DIPLOMACY_BLOCK_ENDEAVORS_10`). The only ACCEPT binding in this table is inside a fully commented-out `FREE_CAPTURED_COMMANDER` block (`:1002`).

> **Gotcha:** Putting a row only in `DiplomaticActionResponseModifiers` does *not* give the target a choice. With no matching `DiplomaticActionResponses` row the engine never builds a button for that response, so the modifier has no response to attach to. This repo hit exactly this: an earlier rewrite deleted the `DiplomaticActionResponses` rows and "replaced" them with `DiplomaticActionResponseModifiers` rows → silent auto-complete (`gift-gold-action.xml:114-124`).

> **Gotcha (the inverse):** Binding a `DiplomaticActionResponseModifiers` row to **ACCEPT** is not how base data works — active rows only ever bind REJECT. The mod binds its relationship-favor modifier to ACCEPT (`gift-gold-action.xml:136-142`); plausibly fine but **[Unverified]** in base data, and flagged in-repo as the first thing to change if the relationship doesn't move in-game.

---

## 4. Accept-gating effects: fire ONLY when the target accepts

Plain `EnterStageModifiers` fire when the COMPLETE stage runs **regardless of accept/decline**. To make an effect fire *only on accept*, route it through one of the cooperative DAE effects, whose argument names the engine reads as "modifier to give … if the target selects accept." **[Confirmed in files]** (effect names + arg docstrings are present as literals in the binary):

| Effect | Accept-only args (verbatim binary docstrings) | Base example |
|---|---|---|
| `EFFECT_DAE_COOPERATIVE_ATTACH_MODIFIER` | `InitialPlayerAccept` ("Modifier to give to the initial player if the target selects accept"), `TargetPlayerAccept`, `InitialPlayerSupport`, `TargetPlayerSupport` | `PLAYER_DIPLOMACY_MILITARY_AID_COMPLETE`, `diplomacy-gameeffects.xml:234-240` |
| `EFFECT_DAE_TARGET_ATTACH_MODIFIER` | `TargetPlayerAccept` (+ `AcceptEffectIsRemovable` / `SupportEffectIsRemovable`) | `PLAYER_DIPLOMACY_IMPROVE_TRADE_RELATIONS_COMPLETE_TARGET`, `diplomacy-gameeffects.xml:348-351` |

Pattern: the **wrapper** modifier is what you bind in `EnterStageModifiers` (with `collection="COLLECTION_OWNER"`); its named **child** modifiers (`PLAYER_DIPLOMACY_MILITARY_AID_TARGET_PLAYER_ACCEPT`, etc.) carry the real grant and are instantiated only on accept.

**A `TargetPlayer*` child reassigns owner to the TARGET**, so `COLLECTION_OWNER` inside that child credits the *recipient*. Base proof: `PLAYER_DIPLOMACY_IMPROVE_TRADE_RELATIONS_TARGET_GOLD` grants the target 30 Gold via `COLLECTION_OWNER` + `EFFECT_PLAYER_GRANT_YIELD` (`diplomacy-gameeffects.xml:352-355`). This repo mirrors it: wrapper `PLAYER_MOD_GIFT_GOLD_COMPLETE` (`gift-gold-effects.xml:27-31`) names `InitialPlayerAccept` → `PLAYER_MOD_GIFT_GOLD_INITIATOR_ACCEPT` (giver −100, `:49-52`) and `TargetPlayerAccept` → `PLAYER_MOD_GIFT_GOLD_TARGET_ACCEPT` (recipient +100, `:39-42`).

> **Gotcha — one-time vs. per-turn:** `EFFECT_PLAYER_GRANT_YIELD` is a **one-time lump** grant; `EFFECT_PLAYER_ADJUST_YIELD` is a **per-turn rate**. `IMPROVE_TRADE_RELATIONS` uses `GRANT_YIELD` for its one-shot gold (`:352-355`); `MILITARY_AID`'s target reward uses `ADJUST_YIELD` (`:249-252`). Pick deliberately. The repo gift uses `GRANT_YIELD` (correct for a one-time transfer).

> **Gotcha — negative grants are untested in base data:** the giver-debit child uses `EFFECT_PLAYER_GRANT_YIELD` with `Amount="-100"` (`gift-gold-effects.xml:49-52`). No base row uses a negative lump grant, so **[Unverified]** whether the engine clamps it. Confirm in-game that the giver's treasury actually drops.

### Relationship favor via `EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES`
Argument names present in the binary: `FavorsAmount` (alias `FavorAmount`), `TargetFavorsAmount`, `GrievancesAmount`, `TargetGrievancesAmount`, `EventType` ("The event to show in the relationship record"). **[Confirmed in files]** The event token must be a registered `KIND_DIPLOMACY_FAVOR_GRIEVANCE_EVENT`; `FAVOR_FROM_ENDEAVOR` is one (base file `:194` Type row, `:833` event-data row, group `DIPLOMACY_FAVOR`). The repo uses it at `gift-gold-effects.xml:64-68`. Base examples of this effect: `PLAYER_DIPLOMACY_GRIEVANCES_FOR_ACTION_REJECTION` (`diplomacy-gameeffects.xml:406`), `PLAYER_DIPLOMACY_CS_ORDER_ATTACK_ACTIVE` (`:324`).

---

## 5. `PlayerOperationType` is engine code with its own logic

`PlayerOperationType` names a compiled engine operation, not just data. Each has its own validation. **[Confirmed in files]** — the operation strings and dedicated source-file names are literals in the binary:

| Operation | Source file (literal in binary) | Behavior |
|---|---|---|
| `SEND_GOLD_DIPLOMATIC_ACTION` | `Player_Operations_DiplomacySendGold.cpp` | Hard alliance gate `m_bRequiresAlliance` → `LOC_DIPLOMACY_ACTION_FAILURE_NOT_ALLIES`. Only source of the **runtime gold-amount picker**. Its base row sets `AllyOnly="true"` (`:329`). |
| `COOPERATIVE_YIELDS_DIPLOMATIC_ACTION` | `Player_Operations_DiplomacyCooperativeYields.cpp` | Non-ally op; targets **met major leaders**. Used by `MINOR_TRADE`, `MILITARY_AID`, `IMPROVE_TRADE_RELATIONS`, and most endeavors. |

**Consequences for a gold-gift mod:**
- The `SEND_GOLD` op's alliance requirement is **compiled in** (`m_bRequiresAlliance`) and **cannot** be overridden by the `AllyOnly` data column. Reusing it on a non-ally action gives "not allies" failures (`LOC_DIPLOMACY_ACTION_FAILURE_NOT_ALLIES`).
- `SEND_GOLD` is the only op that exposes the in-game amount picker (`Target2Type="DIPLOMACY_TARGET_SPECIAL"`, `:779`). Drop it and you lose the picker — the gift amount must be **fixed in the effect** (`gift-gold-effects.xml`).
- Reusing the wrong op gives **"No Valid Targets"**: each op decides who is targetable. `COOPERATIVE_YIELDS_DIPLOMATIC_ACTION` accepts any met major leader; the repo therefore uses it with `Target1Type="DIPLOMACY_TARGET_PLAYER"`, `Target2Type="DIPLOMACY_TARGET_NONE"` (`gift-gold-action.xml:89-102`). **[Inferred]** for the exact "No Valid Targets" string (the empty-target path is operation-internal), but the targeting-by-op behavior is confirmed by the two distinct source files and the base usage split.

> **Gotcha:** `AllyOnly` (`schema:1394`, default 0) gates non-engine eligibility, but it cannot relax an op that requires alliance in C++. Choose the op first, then set data.

---

## 6. The instant pattern, and a worked walkthrough

**Instant action = `BaseDuration="0"` + a single COMPLETE stage with `ProgressRequirement="0"`.** Base proof: `SEND_GOLD` (`DiplomacyActions` row `:329`, `BaseDuration="0"`) has one stage `DIPLOMACY_SEND_GOLD_COMPLETE` (`:453`, `ProgressRequirement="0"`) bound to `PLAYER_MOD_SEND_GOLD` via `EnterStageModifiers` (`:598`). `IMPROVE_TRADE_RELATIONS` is also `BaseDuration="0"` (`:353`).

### Add a new instant, declinable, non-ally gift action (mirroring SEND_GOLD + IMPROVE_TRADE_RELATIONS)

The repo's `data/gift-gold-action.xml` is the reference implementation; map its sections to the checklist:

1. **`<Types>`** — declare the action and its stage Type (`:41-44`):
   ```xml
   <Row Type="DIPLOMACY_ACTION_GIFT_GOLD" Kind="KIND_DIPLOMACY_ACTION" />
   <Row Type="DIPLOMACY_GIFT_GOLD_COMPLETE" Kind="KIND_DIPLOMACY_ACTION_STAGE" />
   ```
2. **`DiplomacyActions`** — `BaseDuration="0"`, `AllyOnly="false"`, a `RequestString` for the offer text, `RejectionRefundsInfluence="true"` so a decline cleanly refunds (`:48-63`).
3. **`DiplomaticActionValidTokens`** — `DIPLOMACY_TOKEN_GLOBAL` (like `SEND_GOLD`) (`:66-68`).
4. **`DiplomaticActionStages`** — one COMPLETE stage, `ProgressRequirement="0"` (`:71-73`).
5. **`EnterStageModifiers`** — bind the accept-gated wrapper to the stage (`:80-82`).
6. **`DiplomaticProjects_UI_Data`** — `PlayerOperationType="COOPERATIVE_YIELDS_DIPLOMATIC_ACTION"` (non-ally, targets met majors), `DiplomacyActionGroup="DIPLOMACY_ACTION_GROUP_ENDEAVOR"`, `Target2Type="DIPLOMACY_TARGET_NONE"` (no amount picker) (`:89-102`).
7. **`DiplomacyBonusEnvoyData`** + **`DiplomaticActionInfluenceCosts`** — zeros, like base endeavors (`:105-112`).
8. **`DiplomaticActionResponses` — the step you must not skip.** Declare ACCEPT (and REJECT to give a real choice) (`:125-128`):
   ```xml
   <Row DiplomacyActionType="DIPLOMACY_ACTION_GIFT_GOLD"
        DiplomaticResponseType="DIPLOMACY_RESPONSE_ACCEPT" InfCost="0"
        Name="LOC_DIPLOMACY_RESPONSE_ACCEPT" Description="LOC_DIPLOMACY_PROJECT_GIFT_GOLD_ACCEPT"/>
   <Row DiplomacyActionType="DIPLOMACY_ACTION_GIFT_GOLD"
        DiplomaticResponseType="DIPLOMACY_RESPONSE_REJECT" InfCost="0"
        Name="LOC_DIPLOMACY_RESPONSE_REJECT" Description="LOC_DIPLOMACY_PROJECT_GIFT_GOLD_REJECT"/>
   ```
9. **Effects file** (`gift-gold-effects.xml`) — the `EFFECT_DAE_COOPERATIVE_ATTACH_MODIFIER` wrapper + `InitialPlayerAccept`/`TargetPlayerAccept` children; favor via `EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES`.
10. **Text** — supply the `LOC_*` keys: NAME, DESCRIPTION, REQUEST, ACCEPT, REJECT (`text/en_us/gift-gold-text.xml`). Civ 7 stores these as `<EnglishText>` `<Row Tag=…>` rows, not the Civ-VI `LocalizedText` table.
11. **`.modinfo`** — load action + effects together in a `scope="game"` `ActionGroup` via `<UpdateDatabase>` so `EnterStageModifiers → ModifierId` references resolve (`civ-simp-gold-gifting.modinfo:27-37`).

### Gotchas checklist
- **No `DiplomaticActionResponses` row → silent auto-complete** (`target=-1`). The #1 trap.
- **`DiplomaticActionResponseModifiers` ≠ `DiplomaticActionResponses`.** The former attaches post-decision effects; only the latter creates the window. Active base data binds the former to REJECT only.
- **Base response rows for endeavors live in the per-age files**, not `base-standard` — don't conclude they're absent from one file.
- **Reusing `SEND_GOLD_DIPLOMATIC_ACTION`** drags in a compiled alliance gate (`AllyOnly` can't override it) and is the only amount-picker source.
- **Plain stage modifiers fire on accept *and* decline.** Gate via the `…Accept` args of a DAE attach effect.
- **`TargetPlayer*` child reassigns owner to the target** — that's how `COLLECTION_OWNER` credits the recipient.
- **`GRANT_YIELD` (one-time) vs `ADJUST_YIELD` (per-turn)** — easy to swap by accident.
- **Negative lump grant and ACCEPT-bound response modifiers are unverified in base data** — confirm both in-game.

---

### Confidence summary
- **[Confirmed in files]**: the engine's `SELECT … FROM DiplomaticActionResponses`/`…ResponseModifiers` queries, their `Definition_*.cpp` loader names, and the response enum incl. `NOT_NEEDED`/`INVALID_RESPONSE`; DAE effect names + accept-arg docstrings; the two operation source files (`Player_Operations_DiplomacySendGold.cpp`, `Player_Operations_DiplomacyCooperativeYields.cpp`), `m_bRequiresAlliance`, `LOC_DIPLOMACY_ACTION_FAILURE_NOT_ALLIES`; all schema columns/defaults and table lines cited; the per-age response rows for `IMPROVE_TRADE_RELATIONS`/`MILITARY_AID`/`MINOR_TRADE`; `FAVOR_FROM_ENDEAVOR` registration.
- **[Inferred]**: the precise `NOT_NEEDED` branch and the "No Valid Targets" literal (behavior corroborated by strings + base usage, not by disassembly).
- **[Unverified]**: negative `EFFECT_PLAYER_GRANT_YIELD` not being clamped; a `DiplomaticActionResponseModifiers` row bound to ACCEPT firing (active base data binds REJECT only). Both are flagged in-repo as the first things to re-check in-game.