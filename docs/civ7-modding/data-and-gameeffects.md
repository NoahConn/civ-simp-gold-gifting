# The two XML dialects: `<Database>` rows vs `<GameEffects>` modifiers

Purpose: explain the two data-authoring formats in Civ 7 (v1.4.0) modding — direct SQL-table rows vs. the compiled modifier system — so you write XML the loader accepts, and know which tables you may touch by hand and which the engine generates for you.

Every claim below is verified against the v1.4.0 install; evidence is cited as `path:line`. Primary reference files:

- `Base/Assets/schema/gameplay/01_GameplaySchema.sql` — the authoritative `CREATE TABLE` definitions (5192 lines).
- `Base/modules/base-standard/data/diplomacy-actions.xml` — a `<Database>` file (1078 lines).
- `Base/modules/base-standard/data/diplomacy-gameeffects.xml` — a `<GameEffects>` file (475 lines).
- Worked example: `civ-simp-gold-gifting/data/gift-gold-action.xml` (Database) and `.../gift-gold-effects.xml` (GameEffects).

See also `diplomacy-actions.md` (the action this example wires together) and the mod's own `docs/schema-notes.md`.

---

## TL;DR

| | `<Database>` file | `<GameEffects>` file |
|---|---|---|
| Root element | `<Database>` | `<GameEffects xmlns="GameEffects">` |
| Children | Table elements (`<Types>`, `<DiplomacyActions>`, …) wrapping `<Row .../>` | `<Modifier>` elements with `<Argument>` / `<String>` children |
| Maps to | Real SQLite tables, 1:1 | The engine **compiles** these into `Modifiers` / `ModifierArguments` / `DynamicModifiers` / `ModifierStrings` |
| You hand-write the SQL tables? | Yes — every `<Row>` is a table insert | **No** — never hand-write `Modifiers`/`ModifierArguments`/`DynamicModifiers` |
| Loaded via | `<UpdateDatabase>` in the `.modinfo` | `<UpdateDatabase>` in the `.modinfo` (same action; loader detects the root) |
| A bad attribute is… | A load error (must be a real column) | A load error (unknown `<Modifier>` attr or argument) |

Both file types load through the **same** `<UpdateDatabase>` manifest action — the loader detects the root element. The base game proves this: in `base-standard.modinfo` a single `<UpdateDatabase>` block (lines 322–425) lists both `data/diplomacy-actions.xml` (`base-standard.modinfo:351`, a `<Database>` file) and `data/diplomacy-gameeffects.xml` (`base-standard.modinfo:354`, a `<GameEffects>` file) as plain `<Item>` entries. The worked example follows the identical pattern (`civ-simp-gold-gifting.modinfo:29-32`). **[Confirmed in files]**

---

## 1. The `<Database>` dialect: rows that map straight to SQL tables

A `<Database>` file's children are **table elements** whose name is the SQLite table name; each `<Row .../>` is one insert, and each attribute is one column.

```xml
<Database>
  <Types>
    <Row Type="DIPLOMACY_ACTION_GIFT_GOLD" Kind="KIND_DIPLOMACY_ACTION" />
  </Types>
  <DiplomacyActions>
    <Row DiplomacyActionType="DIPLOMACY_ACTION_GIFT_GOLD"
         Name="LOC_DIPLOMACY_PROJECT_GIFT_GOLD_NAME"
         Description="LOC_DIPLOMACY_PROJECT_GIFT_GOLD_DESCRIPTION"
         BaseTokenCost="1" .../>
  </DiplomacyActions>
</Database>
```
(`gift-gold-action.xml:38-63`; mirrors the base `SEND_GOLD` row at `diplomacy-actions.xml:329`.) **[Confirmed in files]**

**Every `<Row>` attribute must be a real column of that table.** The columns come from the `CREATE TABLE` in `01_GameplaySchema.sql`. Example — the `DiplomacyActions` table is defined at `01_GameplaySchema.sql:1392-1440` and begins:

```sql
CREATE TABLE 'DiplomacyActions' (
    'DiplomacyActionType' TEXT NOT NULL,
    'AllyOnly' BOOLEAN NOT NULL DEFAULT 0,
    ...
    'Description' LOC_TEXT NOT NULL,
    ...
    'Name' LOC_TEXT NOT NULL,
    ...
    'BaseTokenCost' INTEGER NOT NULL DEFAULT 0,
    ...
    PRIMARY KEY("DiplomacyActionType"),
    FOREIGN KEY ("DiplomacyActionType") REFERENCES "Types"("Type") ...
);
```

A misspelled attribute (e.g. `Decription=`) is not silently ignored — it fails the load because the column does not exist. **[Confirmed in files]**

### Which columns you must supply

Read the `CREATE TABLE`. The rule is mechanical:

- **`NOT NULL` with no `DEFAULT`** → you **must** provide it. For `DiplomacyActions` that is exactly `DiplomacyActionType`, `Description`, and `Name` (`01_GameplaySchema.sql:1393, 1402, 1410`).
- **`NOT NULL DEFAULT x`** → optional; omitting it uses `x`. E.g. `AllyOnly` defaults to `0`, `BaseTokenCost` to `0`, `Opposable` to `1` (`01_GameplaySchema.sql:1394, 1397, 1413`).
- **Nullable (no `NOT NULL`)** → optional; omitting it stores NULL. E.g. `ChangeSupportMsg`, `DiplomacyActionTag`, `RequestString` (`01_GameplaySchema.sql:1400, 1403, 1420`).

> `LOC_TEXT` is just a TEXT column whose value is a localization tag (e.g. `LOC_DIPLOMACY_PROJECT_GIFT_GOLD_NAME`) resolved from a text file. It is not a special type you declare.

### The `Types` table and the FK-before-reference rule

Almost every piece of content first declares itself in the **`Types`** table, then other tables reference it by foreign key. `Types` is tiny (`01_GameplaySchema.sql:3880-3886`):

```sql
CREATE TABLE 'Types' (
    'Type' TEXT NOT NULL,
    'Hash' INTEGER NOT NULL UNIQUE DEFAULT 0,
    'Kind' TEXT NOT NULL,
    PRIMARY KEY("Type"),
    FOREIGN KEY ("Kind") REFERENCES "Kinds"("Kind") ...
);
```

Each `<Row>` supplies `Type` (the unique id) and `Kind` (its category). `Hash` is auto-filled — leave it out. The `Kind` value must already exist in the **`Kinds`** table (`01_GameplaySchema.sql:2420-2424` — just `Kind` + auto `Hash`). The base file declares its kinds at the top of `diplomacy-actions.xml:3-22` (e.g. `KIND_DIPLOMACY_ACTION` at `:4`, `KIND_DIPLOMACY_ACTION_STAGE` at `:8`).

So the authoring order is: **`<Kinds>` → `<Types>` → everything that references those types.** In the worked example, `DIPLOMACY_ACTION_GIFT_GOLD` and `DIPLOMACY_GIFT_GOLD_COMPLETE` are declared in `<Types>` (`gift-gold-action.xml:41-44`) before any table uses them; `KIND_DIPLOMACY_ACTION` / `KIND_DIPLOMACY_ACTION_STAGE` come pre-defined from base-standard, so the mod reuses them rather than re-declaring. Reference a `Type` you never declared and the FK fails. **[Confirmed in files]**

---

## 2. The `<GameEffects>` dialect: modifiers, not rows

A `<GameEffects>` file describes **modifiers** — the engine's unit of "do something to a subject." You do **not** write the underlying SQL tables; the engine compiles them.

```xml
<GameEffects xmlns="GameEffects">
  <Modifier id="PLAYER_MOD_GIFT_GOLD_TARGET_ACCEPT"
            collection="COLLECTION_OWNER"
            effect="EFFECT_PLAYER_GRANT_YIELD"
            permanent="true">
    <Argument name="Amount">100</Argument>
    <Argument name="YieldType">YIELD_GOLD</Argument>
  </Modifier>
</GameEffects>
```
(`gift-gold-effects.xml:39-42`.) **[Confirmed in files]**

The four `<Modifier>` attributes:

| Attribute | Meaning | Example (real values) |
|---|---|---|
| `id` | Unique modifier id. This is what other tables reference (e.g. `EnterStageModifiers.ModifierId`). | `PLAYER_MOD_GIFT_GOLD_COMPLETE` |
| `collection` | The **subject** the effect runs on — who/what gets affected. | `COLLECTION_OWNER`, `COLLECTION_PLAYER_CITIES`, `COLLECTION_PLAYER_UNITS` |
| `effect` | The engine effect Type to run. | `EFFECT_PLAYER_GRANT_YIELD`, `EFFECT_DAE_SEND_GOLD`, `EFFECT_DAE_COOPERATIVE_ATTACH_MODIFIER` |
| `permanent` | `"true"` to persist the effect (common for one-shot grants). Maps to `Modifiers.Permanent` (`01_GameplaySchema.sql:2714`, default `0`). | `permanent="true"` |

Real `collection` values in `diplomacy-gameeffects.xml`: `COLLECTION_OWNER` (most), `COLLECTION_PLAYER_CITIES` (`:53`), `COLLECTION_PLAYER_UNITS` (`:458`). Real `effect` values include `EFFECT_PLAYER_ADJUST_YIELD` (per-turn rate, `:36`), `EFFECT_CITY_ADJUST_YIELD` (`:53`), `EFFECT_DAE_SEND_GOLD` (`:450`), `EFFECT_DAE_COOPERATIVE_ATTACH_MODIFIER` (`:46`), `EFFECT_DO_NOTHING` (`:453`). **[Confirmed in files]**

### Children: `<Argument>` and `<String>`

- **`<Argument name="…">value</Argument>`** — a parameter for the effect. Which names are valid depends entirely on the `effect`. E.g. `EFFECT_PLAYER_GRANT_YIELD` takes `Amount` + `YieldType` (`gift-gold-effects.xml:40-41`); `EFFECT_DAE_COOPERATIVE_ATTACH_MODIFIER` takes `InitialPlayerAccept` / `TargetPlayerAccept` (id references to other modifiers, `gift-gold-effects.xml:29-30`).
- **`<String context="…">LOC_…</String>`** — a localized display string for the modifier. Real contexts in base data are `Name` (`diplomacy-gameeffects.xml:33`) and `Description` (`diplomacy-gameeffects.xml:5`). These compile into the `ModifierStrings` table.

`<Argument>` also accepts optional `type` and `extra` attributes for value scaling, e.g. `<Argument name="Amount" type="ScaleByGameAge" extra="100">2</Argument>` (`diplomacy-gameeffects.xml:38`). These map to the `Type` and `Extra` columns of `ModifierArguments` (`01_GameplaySchema.sql:2725, 2727`).

### What the engine generates — and why you must not hand-write it

The compiler turns each `<Modifier>` into rows across these tables (all in `01_GameplaySchema.sql`):

| Table | What it holds | Schema |
|---|---|---|
| `Modifiers` | One row per `<Modifier>` (`ModifierId`, `ModifierType`, `Permanent`, requirement-set ids, …) | `01_GameplaySchema.sql:2708-2721` |
| `ModifierArguments` | One row per `<Argument>` (`ModifierId`, `Name`, `Value`, `Type`, `Extra`, `SecondExtra`) | `01_GameplaySchema.sql:2722-2731` |
| `DynamicModifiers` | The `(ModifierType, CollectionType, EffectType)` triple — i.e. your `collection`+`effect` | `01_GameplaySchema.sql:1741-1749` |
| `ModifierStrings` | One row per `<String>` (`Context`, `ModifierId`, `Text`) | `01_GameplaySchema.sql:2745-2751` |

These are populated for you. The engine then **reads** them at load — proven by the literal load SQL embedded as printable strings in the engine binary (`Base/Binaries/Win64/Civ7_Win64_DX12_FinalRelease.exe`, all confirmed present verbatim):

```
SELECT rowid, ModifierId, ModifierType, NewOnly, OwnerRequirementSetId,
       OwnerStackLimit, Permanent, RunOnce, SubjectRequirementSetId,
       SubjectStackLimit FROM Modifiers
SELECT Name, Value, Type, Extra, SecondExtra FROM ModifierArguments
... from DynamicModifiers inner join Types as ModifierTypes on
    DynamicModifiers.ModifierType = ModifierTypes.Type inner join Types as Collection...
SELECT Text from ModifierStrings
```

The column list in each `SELECT` is exactly what the engine consumes — and exactly the columns the `CREATE TABLE`s declare — a handy cross-check that your authored data lines up with what the engine reads. **[Confirmed in files]**

Hand-writing rows into `Modifiers`/`ModifierArguments`/`DynamicModifiers` from a `<Database>` file is the classic mistake: you would have to compute the triple in `DynamicModifiers` and the per-argument decomposition yourself, get the FKs right, and keep them in sync — all of which the `<GameEffects>` compiler does. Author modifiers as `<Modifier>` elements and reference them by `id` from your `<Database>` rows.

---

## 3. How the two files connect (the worked example)

The Database file and the GameEffects file are joined by **id references**, not by being in the same file:

1. `gift-gold-action.xml` declares a completion stage and binds a modifier id to it (`EnterStageModifiers`, `gift-gold-action.xml:80-82`):
   ```xml
   <EnterStageModifiers>
     <Row StageType="DIPLOMACY_GIFT_GOLD_COMPLETE" ModifierId="PLAYER_MOD_GIFT_GOLD_COMPLETE" />
   </EnterStageModifiers>
   ```
2. `gift-gold-effects.xml` defines that modifier as `<Modifier id="PLAYER_MOD_GIFT_GOLD_COMPLETE" …>` (`gift-gold-effects.xml:27`).

`EnterStageModifiers.ModifierId` is FK'd to `Modifiers.ModifierId` (`01_GameplaySchema.sql:1783`) — and `Modifiers.ModifierId` is the row the GameEffects compiler creates from your `<Modifier id>`. This is the identical pattern the base game uses to wire `DIPLOMACY_SEND_GOLD_COMPLETE` to `PLAYER_MOD_SEND_GOLD` (`diplomacy-actions.xml:598` → `diplomacy-gameeffects.xml:450`). Because the references resolve at load, **both files must be in the same mod load step** so the ids are satisfiable. **[Confirmed in files]**

---

## Gotchas

- **Don't hand-author `Modifiers` / `ModifierArguments` / `DynamicModifiers` / `ModifierStrings`.** They are compiler output from `<GameEffects>`. Writing them as `<Database>` rows means recomputing the `DynamicModifiers` triple and arg decomposition by hand — the most common self-inflicted load failure.
- **A typo in a `<Row>` attribute is a hard load error, not a warning.** The attribute must be a real column. Confirm against the `CREATE TABLE` in `01_GameplaySchema.sql`.
- **Declare `<Types>` (and any needed `<Kinds>`) before referencing them.** Other tables FK to `Types("Type")`; a reference to an undeclared Type fails the foreign-key check.
- **Don't supply auto columns.** `Types.Hash` and `Kinds.Hash` are `UNIQUE DEFAULT 0` and auto-assigned — leave them out (`01_GameplaySchema.sql:3882, 2422`).
- **`collection` ≠ effect target with attach effects.** An attach effect reassigns the *child* modifier's owner at attach time. In the worked example `PLAYER_MOD_GIFT_GOLD_TARGET_ACCEPT` uses `COLLECTION_OWNER` yet credits the *recipient*, because the parent's `EFFECT_DAE_COOPERATIVE_ATTACH_MODIFIER` makes the target the owner of the `TargetPlayerAccept` child (`gift-gold-effects.xml:27-42`). This clones base `PLAYER_DIPLOMACY_MILITARY_AID_COMPLETE` (`diplomacy-gameeffects.xml:234-253`), which uses the same `COOPERATIVE_ATTACH` shape. (Base `IMPROVE_TRADE_RELATIONS` reaches the same end via the sibling effect `EFFECT_DAE_TARGET_ATTACH_MODIFIER`, `diplomacy-gameeffects.xml:348-355`.) **[Inferred from base MILITARY_AID / IMPROVE_TRADE_RELATIONS patterns]**
- **`EFFECT_PLAYER_GRANT_YIELD` is a one-time lump grant; `EFFECT_PLAYER_ADJUST_YIELD` is a per-turn rate.** Pick deliberately — the worked example uses `GRANT` for a single gold transfer (`gift-gold-effects.xml:39`), while base Open Borders uses `ADJUST` for ongoing yield (`diplomacy-gameeffects.xml:36`). The base game also uses `GRANT` for a one-shot in `PLAYER_DIPLOMACY_IMPROVE_TRADE_RELATIONS_TARGET_GOLD` (30 Gold, `diplomacy-gameeffects.xml:352-355`).
- **Argument names are effect-specific and not in the SQL schema** — `ModifierArguments` only stores `Name`/`Value`. To find valid argument names for an effect, copy a base modifier that uses the same `effect`, or read them out of the engine binary. The mod did the latter for `EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES`: the strings `FavorsAmount`, `TargetFavorsAmount`, `GrievancesAmount`, `TargetGrievancesAmount`, and `FavorAmount can be used in place of Amount` are all present verbatim in `Civ7_Win64_DX12_FinalRelease.exe` (used at `gift-gold-effects.xml:64-67`; see `docs/schema-notes.md`). **[Confirmed in files for the cited effects; other effects' arg sets are [Unverified] until checked the same way.]**
