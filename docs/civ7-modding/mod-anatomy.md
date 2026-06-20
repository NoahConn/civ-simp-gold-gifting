# Mod anatomy: `.modinfo`, action groups, how files load

> How a Civ VII (v1.4.0) mod is wired together: the `.modinfo` manifest, action groups and their scopes, and the exact mechanics of how `UpdateDatabase` / `UpdateText` pull your data into the game. Verified against the base game (`Base/modules/base-standard`, `Base/modules/core`) and the `civ-simp-gold-gifting` worked example.

Cross-references: see `diplomacy-actions.md` for the action tables themselves, `effects-and-modifiers.md` for the `<GameEffects>` dialect, and `localization.md` for `<EnglishText>` text rows.

---

## 1. The folder + manifest skeleton

A mod is a **single folder** placed under the user Mods directory, containing one `<id>.modinfo` XML file **at its root**. **[Confirmed in files]**

- User Mods dir on Windows: `%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VII\Mods` (i.e. `C:\Users\<you>\AppData\Local\Firaxis Games\Sid Meier's Civilization VII\Mods`).
- The base game ships its own modules the same way, under the install tree: `…\Sid Meier's Civilization VII\Base\modules\base-standard\base-standard.modinfo` and `…\Base\modules\core\core.modinfo`. Reading those is the single best way to learn the schema — they *are* the source of truth.

The worked example's layout (`civ-simp-gold-gifting/`):

```
civ-simp-gold-gifting/
  civ-simp-gold-gifting.modinfo   <- manifest, at the folder ROOT
  data/
    gift-gold-action.xml          <- <Database>-rooted: action tables
    gift-gold-effects.xml         <- <GameEffects>-rooted: modifiers
  text/
    en_us/
      gift-gold-text.xml          <- <Database><EnglishText> text rows
```

The `id` attribute on the `<Mod>` element should match the folder/file name (`civ-simp-gold-gifting`); it is the handle the loader keys on and that other mods use as a dependency.

---

## 2. The `.modinfo` file, element by element

Full manifest from `civ-simp-gold-gifting.modinfo` (39 lines; comments elided here):

```xml
<?xml version="1.0" encoding="utf-8"?>
<Mod id="civ-simp-gold-gifting" version="1" xmlns="ModInfo">
  <Properties>
    <Name>Civ Simp Gold Gifting</Name>
    <Description>Adds a diplomatic endeavor to gift Gold directly to another player…</Description>
    <Authors>Noah</Authors>
    <Package>Mod</Package>
  </Properties>

  <Dependencies>
    <Mod id="base-standard" title="LOC_MODULE_BASE_STANDARD_NAME"/>
  </Dependencies>

  <ActionCriteria>
    <Criteria id="always">
      <AlwaysMet></AlwaysMet>
    </Criteria>
  </ActionCriteria>

  <ActionGroups>
    <ActionGroup id="gift-gold-game" scope="game" criteria="always">
      <Actions>
        <UpdateDatabase>
          <Item>data/gift-gold-action.xml</Item>
          <Item>data/gift-gold-effects.xml</Item>
        </UpdateDatabase>
        <UpdateText>
          <Item>text/en_us/gift-gold-text.xml</Item>
        </UpdateText>
      </Actions>
    </ActionGroup>
  </ActionGroups>
</Mod>
```

### Root element

`<Mod id=".." version=".." xmlns="ModInfo">`. The `xmlns="ModInfo"` is required and identical in the base game (`base-standard.modinfo:2-3` and `core.modinfo` both use `xmlns="ModInfo"`). **[Confirmed in files]**

`version` is an integer string (`1` here), matching the base modules which are also `version="1"` (`base-standard.modinfo:2`). It is the manifest's own revision number, **not** SemVer; this project tracks its public SemVer in **git tags** (`v0.1.0`, `v0.2.0`) separately — see `civ-simp-gold-gifting/README.md:94-97`. **[Confirmed in files]**

### `<Properties>`

| Element | Purpose | Notes |
|---|---|---|
| `Name` | Display name in the Mods menu | Plain text or a `LOC_…` tag |
| `Description` | Mods-menu blurb | — |
| `Authors` | Credit | — |
| `Package` | Bucket/category | This mod uses `Mod`. The base game uses `BaseGame` (`base-standard.modinfo:9`) and also sets `ShowInBrowser`/`PackageSortIndex` (`:8`,`:10`), which user mods normally omit. **[Confirmed in files]** |

### `<Dependencies>` vs `<References>`

- `<Dependencies>` lists mods that **must** be present/loaded. This mod depends on `base-standard` (`civ-simp-gold-gifting.modinfo:11`), which is correct: the diplomacy framework and the row data its action plugs into (`DiplomacyActions`, `EnterStageModifiers`, the `DIPLOMACY_*` types, …) come from base-standard. The table *definitions* themselves live in the gameplay schema (`Base/Assets/schema/gameplay/01_GameplaySchema.sql`, e.g. `DiplomacyActions` at `:1392`, `DiplomaticActionResponses` at `:1565`, `EnterStageModifiers` at `:1777`), which the engine loads before any module. **[Confirmed in files]**
- The base game also demonstrates a separate `<References>` element: `base-standard.modinfo:13-15` references `core`. **[Inferred]** `References` expresses a softer load-order relationship than a hard `Dependencies` requirement; for a typical content mod, declaring `base-standard` under `<Dependencies>` is what you want. (Note `base-standard`'s own `<Dependencies>` is empty — `:12`.)

### `<ActionCriteria>`

Declares reusable named conditions. This mod declares one:

```xml
<Criteria id="always"><AlwaysMet></AlwaysMet></Criteria>
```

`<AlwaysMet>` means "no condition" (the empty-tag form `<AlwaysMet></AlwaysMet>` and the self-closing `<AlwaysMet />` the base game uses at `base-standard.modinfo:18` are equivalent XML). The base game declares the **same** `always` criterion plus a `standard-games` criterion gated on `<RuleSetInUse>RULESET_STANDARD</RuleSetInUse>` (`base-standard.modinfo:16-23`). **[Confirmed in files]** Criteria are referenced by id from an `ActionGroup`'s `criteria` attribute, letting you conditionally enable content (e.g. only in a particular ruleset).

---

## 3. Action groups: `scope` and `criteria`

An `<ActionGroup>` bundles a set of load actions and tags them with **where** and **when** they apply:

- `scope="game"` — applies **inside an active game** (gameplay database). This is where diplomacy actions, units, modifiers, etc. belong.
- `scope="shell"` — applies in the **front-end / setup** (main menu, game-setup screens).

**[Confirmed in files]** `base-standard.modinfo` has exactly two action groups: `base-game-main` (`scope="game"`, `:25`) and `base-game-shell` (`scope="shell"`, `:932`). The split is concrete:

| | `scope="game"` (base-game-main) | `scope="shell"` (base-game-shell) |
|---|---|---|
| Loads | gameplay tables: `data/diplomacy-actions.xml` (`:351`), `data/diplomacy-gameeffects.xml` (`:354`), … (`:322-425`) | setup/config tables: `config/config.xml`, `config/hall-of-fame.xml`, `config/metaprogression.xml`, `config/unlockableRewards.xml` (`:943-948`) |
| Typical use | the actual mod content | menu options, game-setup parameters |

`civ-simp-gold-gifting` only needs `scope="game"` because a diplomacy action is pure in-game content — it has a single `gift-gold-game` group (`civ-simp-gold-gifting.modinfo:27`). A mod that adds a setup-screen toggle or a custom map option would add a second `scope="shell"` group. (`core.modinfo` shows both, plus a dedicated schema group — `:19`,`:29`,`:201`.)

The `criteria="always"` attribute points at one of the `<ActionCriteria>` ids; here it gates the group on `AlwaysMet` (i.e. unconditional).

### Action types inside `<Actions>`

| Action element | What it does | Item paths are… | Base proof |
|---|---|---|---|
| `<UpdateDatabase>` | Loads XML/SQL into the **gameplay database** | relative to mod root, e.g. `data/gift-gold-action.xml` | `base-standard.modinfo:322-425` |
| `<UpdateText>` | Loads localized text rows | e.g. `text/en_us/gift-gold-text.xml` | `:466-599` |
| `<UpdateIcons>` | Registers icon definitions | `data/icons/*.xml` | `:430-465` |
| `<UpdateColors>` | Player/UI colors | `data/colors/*.xml` | `:426-429` |
| `<UpdateArt>` | Pulls in asset packages | `Civ7`, `boot-shell` | `:600-604` |
| `<ImportFiles>` / `<UIScripts>` | Registers HTML/JS UI files | `ui/...` | `:27-32` / `:33-321` |

Each contains `<Item>…</Item>` entries listing files. Items can carry attributes — e.g. the base game uses `locale="de_DE"` on `<UpdateText>` items for translations (`base-standard.modinfo:566`) and `platform="Switch"` / `ecosystem="game-center"` on platform-specific overrides (`:579-598`). **[Confirmed in files]** A content mod rarely needs those.

---

## 4. CRUCIAL: `<UpdateDatabase>` loads *both* `<Database>` and `<GameEffects>` files

This is the single most important loading fact, and the one most likely to trip you up if you assume there's a separate action for effects.

**`<UpdateDatabase>` dispatches on each file's root element** — `<Database>`-rooted files go through the table loader, `<GameEffects>`-rooted files go through the modifier compiler. Both are listed under the **same** `<UpdateDatabase>` block. **[Confirmed in files]**

Base-game proof — inside `base-standard.modinfo`'s single `scope="game"` `<UpdateDatabase>` block:

```
:351   <Item>data/diplomacy-actions.xml</Item>       <- root is <Database>
:354   <Item>data/diplomacy-gameeffects.xml</Item>   <- root is <GameEffects xmlns="GameEffects">
```

Verified roots:
- `diplomacy-actions.xml:2` → `<Database>`
- `diplomacy-gameeffects.xml:2` → `<GameEffects xmlns="GameEffects">`

The worked example mirrors this exactly — its `gift-gold-game` group lists both files in one `<UpdateDatabase>` (`civ-simp-gold-gifting.modinfo:29-32`):

```xml
<UpdateDatabase>
  <Item>data/gift-gold-action.xml</Item>     <!-- <Database> at gift-gold-action.xml:38 -->
  <Item>data/gift-gold-effects.xml</Item>    <!-- <GameEffects xmlns="GameEffects"> at gift-gold-effects.xml:21 -->
</UpdateDatabase>
```

> There is **no** `<UpdateGameEffects>` or similar action. If you put your modifiers in a separate `<GameEffects>` file (recommended — it matches the base game), you still list it under `<UpdateDatabase>`.

Localized text is the exception: `<EnglishText>` rows go through `<UpdateText>`, **not** `<UpdateDatabase>`, even though the file itself is `<Database>`-rooted (`gift-gold-text.xml:8-9` is `<Database><EnglishText>`). See `localization.md`.

---

## 5. Load order within an `<UpdateDatabase>` list: forward references resolve

You can list a `<Database>` file that **references** a modifier *before* you list the `<GameEffects>` file that **defines** that modifier. It still resolves, because modifiers are compiled in a **later pass** than the table rows. **[Confirmed in files]**

Base-game proof:
- `diplomacy-actions.xml:614` declares an `EnterStageModifiers` row: `ModifierId="PLAYER_DIPLOMACY_MILITARY_AID_COMPLETE"`.
- That modifier is only **defined** in `diplomacy-gameeffects.xml:234`.
- In the manifest, the actions file (`base-standard.modinfo:351`) is listed **before** the gameeffects file (`:354`).

So a row referencing a modifier defined in a later-listed file is fine. The worked example relies on the identical pattern: `gift-gold-action.xml:81` has `EnterStageModifiers … ModifierId="PLAYER_MOD_GIFT_GOLD_COMPLETE"`, and that modifier is defined later in `gift-gold-effects.xml:27`.

**Caveat — this leniency is about the table-row → modifier direction across the two-pass compile.** Plain `<Types>` declarations are still expected up-front: every `Type` referenced by a row must already exist in a `<Types>` block (the worked example declares its types in `gift-gold-action.xml:41-44`, at the top of the same file, before any table references them). Don't over-generalize "forward refs always work" to arbitrary FK relationships — when in doubt, mirror the base game's file order. **[Inferred]**

---

## 6. WHEN database changes take effect: new game, not reload

Database changes from `<UpdateDatabase>` apply at **database build time**, which happens when you **START A NEW GAME**. Loading a save is **not** enough — a save already has its database baked in. **[Confirmed in-game]** (`civ-simp-gold-gifting/README.md:66`: "Database changes apply at **database build time**, so a reload is not enough — start a **new game**."; corroborated in `docs/civ7-modding/TROUBLESHOOTING.md:19`, tagged `[seen]`.)

Practical iteration loop for any data mod:

1. Edit your `data/*.xml`.
2. Make sure the mod is **Enabled** in the in-game Mods menu (one-time).
3. **Start a new game** (with whatever conditions your feature needs — e.g. for Gift Gold, at least one other major leader to meet).
4. Observe (and read `…\Logs\Database.log` / `Modding.log` first if anything is off).

There is no hot-reload for database content. Budget for full new-game restarts on every data change.

---

## 7. `.xml` vs `.sql` in `UpdateDatabase`

`<UpdateDatabase>` accepts **both** `.xml` and `.sql` items. **[Confirmed in files]** — the base game proves it: `core.modinfo:25` loads `config/config-schema.sql` through an `<UpdateDatabase>` block (in a `scope="shell"` group, `:19-25`). The action is a generic database-load that runs raw SQL when handed a `.sql` file.

This project deliberately standardized on **`.xml`** to match the base game's authoring style (every base `data/*.xml` diplomacy/gameplay file is XML; no `.sql` items appear anywhere in `base-standard.modinfo`), which makes diffing against the install trivial and keeps the `<Database>` / `<GameEffects>` dialects consistent. **[Confirmed in files]** — `docs/schema-notes.md:4-7` records that the original `.sql` prototype (`gift-gold-endeavor.sql`) was replaced by `gift-gold-action.xml` + `gift-gold-effects.xml`.

Recommendation: prefer `.xml` for declarative table inserts; reach for `.sql` only when you need imperative `UPDATE`/`DELETE`/`CREATE` against existing rows that XML insert-rows can't express (exactly what `core`'s `config-schema.sql` does).

---

## Gotchas

- **`<UpdateDatabase>` loads `<GameEffects>` files too** — there is no separate effects action. Looking for an `<UpdateGameEffects>` is a dead end; list the `<GameEffects>` file under `<UpdateDatabase>`.
- **Text is special**: `<EnglishText>` rows load via `<UpdateText>`, not `<UpdateDatabase>` — even though the file is `<Database>`-rooted.
- **No reload shortcut**: a save reload will *not* pick up data edits. Always start a **new game**.
- **`.modinfo` must be at the folder root**, and its `id` should match the folder name; the loader keys on it and other mods depend on it.
- **Get `xmlns` right**: the manifest needs `xmlns="ModInfo"`; a `<GameEffects>` file needs `xmlns="GameEffects"`; a `<Database>` file has **no** xmlns. A wrong/missing root triggers `Database XML root elements must start with either <Database> or <GameEffects>` in `Database.log` (`docs/civ7-modding/TROUBLESHOOTING.md:17`).
- **Declare `<Types>` up-front**, even though modifier *references* can be forward. Rows that reference an undeclared `Type` fail to load (UNIQUE/FK error in `Database.log`).
- **Scope mismatch = invisible content**: putting gameplay data in a `scope="shell"` group (or setup data in `scope="game"`) means it won't be there when you expect it. Match the base game: gameplay → `game`, setup/menus → `shell`.
