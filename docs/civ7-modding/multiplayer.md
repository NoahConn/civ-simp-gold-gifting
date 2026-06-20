# Multiplayer: desync safety

One-line purpose: what makes a Civ 7 mod multiplayer-safe vs. desync-prone, grounded in how the v1.4.0 engine replicates state — so you build on the data-driven path and avoid client-divergent scripting.

> Scope: multiplayer (MP) desync risk only. For how the Gift Gold action itself is authored, see `diplomacy-actions.md` and `game-effects-modifiers.md`. For the `.modinfo` ActionGroup/scope structure, see `modinfo-and-loading.md`. (Those sibling docs are companion files in this knowledge base.)

## TL;DR

| Mod content | MP-safe? | Why |
|---|---|---|
| Data loaded via `<UpdateDatabase>` (DiplomacyActions, Modifiers/GameEffects, EnterStageModifiers, responses) | **Yes** | Engine applies & replicates it deterministically — same pipeline the base game uses. **[Confirmed in files]** |
| UI-only scripts (`<UIScripts>` / `<ImportFiles>`, presentation/tooltips/panels) | **Generally yes** | They render local state; they don't mutate the synced game state. **[Inferred]** |
| JS scripts that mutate **gameplay** state (RNG, per-frame, client-only data) | **Risk** | Can diverge between clients; the engine flags this as out-of-sync. **[Inferred from engine strings]** |
| Mismatched mod set / mod version between players | **Match won't start** | Engine enforces identical, version-matched mods. **[Confirmed in files]** |

The Gift Gold mod is **100% data-driven** (`<UpdateDatabase>` over two XML files plus `<UpdateText>`, zero gameplay scripts), so it sits squarely in the safe row. **[Confirmed in files]** — `civ-simp-gold-gifting.modinfo:29-35`; a repo-wide search finds no `.js`/`.lua` and no `<UIScripts>`/`script` references in the manifest.

## Why data-driven gameplay is desync-safe

The mod ships no gameplay scripts. Its entire behavior is rows the engine loads and then applies itself. From the mod manifest (`civ-simp-gold-gifting.modinfo:27-37`):

```xml
<ActionGroup id="gift-gold-game" scope="game" criteria="always">
  <Actions>
    <UpdateDatabase>
      <Item>data/gift-gold-action.xml</Item>   <!-- <Database>: DiplomacyActions, stages, responses -->
      <Item>data/gift-gold-effects.xml</Item>  <!-- <GameEffects>: the modifiers -->
    </UpdateDatabase>
    <UpdateText><Item>text/en_us/gift-gold-text.xml</Item></UpdateText>
  </Actions>
</ActionGroup>
```

This is **the same pipeline the base game uses**. The base module loads its own diplomacy under one `scope="game"` ActionGroup via `<UpdateDatabase>`:

- `base-standard.modinfo:25` — `<ActionGroup id="base-game-main" scope="game" criteria="always">`
- `base-standard.modinfo:351` — `<Item>data/diplomacy-actions.xml</Item>`
- `base-standard.modinfo:354` — `<Item>data/diplomacy-gameeffects.xml</Item>`

So `DIPLOMACY_ACTION_GIFT_GOLD` is loaded and executed the same way as the base game's `DIPLOMACY_ACTION_SEND_GOLD` ("Send Aid") that the mod clones — defined at `Base/modules/base-standard/data/diplomacy-actions.xml:329`, with its accept response at `:936`. The action class fires identically in single-player and multiplayer **[Confirmed in-game per brief]**, which is what you'd expect: both go through the engine's deterministic action/modifier execution, not through any mod code.

### The engine treats modifiers as replicated, checksummed state

The data path is safe because the engine — not your mod — owns applying it, and it replicates that application across clients with hash-checked snapshots. Evidence from the shipped engine binary `Base/Binaries/Win64/Civ7_Win64_DX12_FinalRelease.exe` (strings verified present verbatim):

- A deterministic state-snapshot/replication layer ("AutoArchive") with **delta sync and hash comparison**: `AutoArchive out of sync (data hash mismatch) Player=%i` and `AutoArchive out of sync (delta data mismatch)`.
- **Modifiers are part of the synced state and have explicit desync handling**: `DynamicModifierDesynced failed to create modifier!` and `DynamicModifierDesynced failed to find desynced modifier (%i)`. `DynamicModifiers` is a real gameplay table (`Base/Assets/schema/gameplay/01_GameplaySchema.sql:1741`) — exactly what `<GameEffects>` modifiers compile into, alongside `Modifiers` (`:2708`) and `ModifierArguments` (`:2722`). The engine has a code path to *recreate a desynced modifier from the host's authoritative state* — i.e. modifiers are replicated, not computed independently per client. **[Confirmed in files]**

Because the engine deterministically applies and reconciles `EnterStageModifiers` → `ModifierId` (table at `01_GameplaySchema.sql:1777`) and the response-bound effects in `DiplomaticActionResponseModifiers` (`:1576`) that your data declares, adding more of that same kind of data (more actions, more modifiers, more effects) does not introduce new desync risk. **[Inferred]** — the inference is "more rows on a proven-deterministic path stay deterministic"; the path itself is confirmed.

## Why gameplay scripts are a risk

The engine explicitly detects and surfaces divergence between clients (binary strings, verified present): `Client recorded Out of Sync errors`, `Host recorded Out of Sync errors`, plus the substrings `Desync`, `NetSync`, and `setMemberToDesync`. Anything that makes one client's authoritative game state differ from another's trips this.

Script code is where that creeps in, because it runs *on each client* rather than being applied-and-replicated by the engine. Classic desync sources in a turn-based lockstep engine like this:

- **RNG not drawn from the synced game seed** (e.g. `Math.random()` in JS) — each client rolls differently.
- **Client-only or per-frame state** — reading UI/local timing, frame counts, or anything not part of the replicated game state, then writing gameplay from it.
- **Order-dependent logic** — iterating an unordered collection and mutating state based on iteration order (the engine even guards its own collections: `UEnumeration out of sync with underlying collection.`).

If you must script gameplay, keep it **deterministic and engine-event-driven**: react to engine gameplay events, derive only from replicated game state, and use the engine's game RNG — never wall-clock, frame, or local-input state. Prefer expressing the change as data (a modifier/effect) so the engine replicates it for you. **[Inferred]**

> Note: **UI-only** scripts (presentation) are a different category. The base game's `scope="game"` ActionGroup loads a large `<UIScripts>` block — `base-standard.modinfo:33` (`<UIScripts>` open) through `:321` (close) — plus an `<ImportFiles>` block of UI `.js`/`.html` (`:27-32`). Its `scope="shell"` ActionGroup (`base-game-shell`, `base-standard.modinfo:932`) has its own much smaller `<UIScripts>` (`:937-939`, just `live-notice.js`). These render local views, tooltips, and the front-end shell; they don't mutate the synced simulation, so they're generally MP-safe. The danger is specifically **gameplay-state mutation**, not having scripts at all. **[Inferred]**

## Both players need the same mod AND the same version

This is enforced by the engine, not a social convention. From the binary (strings verified present verbatim):

- Verbatim user-facing error: **`The following mods are missing (mod versions MUST match):`**
- Version-comparison hooks: `getEnabledModVersion`, `getRequiredModVersion`, and a `ModVersion` field.
- Game-version gating around mod compatibility: the SQL `... FROM ModCompatibilityWhitelist WHERE ModRowId = ? AND GameVersion = ? LIMIT 1`, and the mod registry `INSERT INTO Mods(ScannedFileRowId, ModId, Version) VALUES(?,?,?)`.

So the match will not start together unless every player has the **same mod enabled at the same version**. The `version` you ship is the one in your manifest — `civ-simp-gold-gifting.modinfo:2` declares `<Mod id="civ-simp-gold-gifting" version="1" xmlns="ModInfo">`. **[Confirmed in files]**

Practical consequence: **bump `version` on every gameplay-affecting release, and have all players re-install the same build.** A host on `version="2"` and a guest still on `version="1"` is a non-start, not a silent partial-load.

## Gotchas

- **"It works in single-player" proves nothing about MP.** SP runs one client, so divergence is impossible by construction. The Gift Gold action was checked in *both* SP and MP; a script-based version would need the MP check specifically.
- **Version is a hard gate, and it's *your* manifest `version`, not the file's mtime or git SHA.** Forgetting to bump it means two different builds both advertise `version="1"` and may load-then-desync instead of cleanly refusing to start.
- **Don't reach for a script to do what data can do.** The mod gates gold/favor on accept entirely through data: the accept-only attach wrapper `PLAYER_MOD_GIFT_GOLD_COMPLETE` is bound to the COMPLETE stage via `EnterStageModifiers` (`data/gift-gold-action.xml:80-82`), and the favor is bound to the `DIPLOMACY_RESPONSE_ACCEPT` row in `DiplomaticActionResponseModifiers` (`:136-142`). No script = no desync surface. If you find yourself writing JS to move yields or relationships, check whether an `EFFECT_*` modifier already does it.
- **Modifiers are replicated, not recomputed — but only when declared as data.** The engine's `DynamicModifierDesynced` recovery exists for engine-managed modifiers. A modifier *your script* fabricates at runtime on one client has no host-authoritative counterpart to reconcile against.
- **RNG and time are the usual culprits.** If a future scripted feature needs randomness, it must come from the synced game RNG, never `Math.random()` or anything time/frame-derived.

## Quick verification map (file → line)

| Claim | Evidence |
|---|---|
| Mod loads gameplay via `<UpdateDatabase>` under `scope="game"`, no scripts | `civ-simp-gold-gifting.modinfo:27-37` (`gift-gold-game` ActionGroup) |
| Base game uses the same pipeline/scope | `base-standard.modinfo:25`, `:351`, `:354` |
| Cloned base action exists / its accept response | `Base/modules/base-standard/data/diplomacy-actions.xml:329` (`DIPLOMACY_ACTION_SEND_GOLD`); accept row at `:936` |
| Base UI scripts are scope-separated (game vs shell) | `base-standard.modinfo:33-321` (`<UIScripts>` under `scope="game"`); `:932`, `:937-939` (shell) |
| Modifiers are synced state with desync recovery | binary strings `DynamicModifierDesynced failed to create modifier!`, `DynamicModifierDesynced failed to find desynced modifier (%i)`; tables `DynamicModifiers` (`01_GameplaySchema.sql:1741`), `Modifiers` (`:2708`), `ModifierArguments` (`:2722`) |
| Engine detects client/host out-of-sync | binary strings `Client recorded Out of Sync errors`, `Host recorded Out of Sync errors`, `Desync`, `NetSync`, `setMemberToDesync` |
| Deterministic hash-checked replication | binary strings `AutoArchive out of sync (data hash mismatch) Player=%i`, `AutoArchive out of sync (delta data mismatch)` |
| Same-mod-same-version enforced | binary strings `The following mods are missing (mod versions MUST match):`, `getEnabledModVersion`, `getRequiredModVersion`, `... FROM ModCompatibilityWhitelist WHERE ModRowId = ? AND GameVersion = ?`, `INSERT INTO Mods(ScannedFileRowId, ModId, Version) ...` |
| Mod version source | `civ-simp-gold-gifting.modinfo:2` `<Mod ... version="1">` |

Schema path is `Base/Assets/schema/gameplay/01_GameplaySchema.sql`; binary is `Base/Binaries/Win64/Civ7_Win64_DX12_FinalRelease.exe`. All quoted binary strings above were confirmed present in that file.

**Confidence summary:** the replication mechanism, desync detection, and version enforcement are **[Confirmed in files]** (engine binary + schema + manifests). The single-vs-multiplayer parity of the Gift Gold action is **[Confirmed in-game]** per the brief. The generalizations "any further data-driven content stays safe" and "UI-only scripts are fine / gameplay scripts are the risk" are **[Inferred]** from the confirmed engine behavior, not from a line that states them outright.