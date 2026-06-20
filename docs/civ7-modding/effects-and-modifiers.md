# Effects & modifiers catalog (yields, favors, attach modifiers, binary args)

> Purpose: a verified reference for the gameplay effects this mod used and the ones nearby — what arguments each accepts and the traps that cost us time — so you pick the right effect the first time. Companion to `diplomacy-actions.md` (the action/response wiring) and the schema docs.

All claims below were checked against the **v1.4.0 install**. Abbreviations used throughout:

- `DGE` = `Base/modules/base-standard/data/diplomacy-gameeffects.xml`
- `DA` = `Base/modules/base-standard/data/diplomacy-actions.xml`
- `EXE` = `Base/Binaries/Win64/Civ7_Win64_DX12_FinalRelease.exe` (806 MB)
- Worked example: `civ-simp-gold-gifting/data/gift-gold-effects.xml` (`GG-effects`) and `.../data/gift-gold-action.xml` (`GG-action`). Both load via `<UpdateDatabase>` in the modinfo (`civ-simp-gold-gifting.modinfo:30-31`).

> **On binary line numbers:** the strings you extract from `EXE` (§6) are *not* stable across extractions — the line index depends on your tool and min-run-length. This doc cites the **effect-name string and the args that cluster immediately after it**, never a fragile absolute line number. Re-derive them with the §6 recipe.

---

## 0. How a modifier is authored

A `<Modifier>` in a `<GameEffects>` file binds one **effect** to a **collection** (who it applies to), with named `<Argument>`s. The engine compiles each into `Modifiers` / `ModifierArguments` / `DynamicModifiers` rows at load.

```xml
<Modifier id="MY_MOD" collection="COLLECTION_OWNER" effect="EFFECT_PLAYER_GRANT_YIELD" permanent="true">
  <Argument name="Amount">100</Argument>
  <Argument name="YieldType">YIELD_GOLD</Argument>
</Modifier>
```

- `collection` decides the subject. `COLLECTION_OWNER` = the player who owns the modifier (in an accept-gated child, *who owns it is set by the attach wrapper* — see §4). `COLLECTION_PLAYER_CITIES` iterates the owner's cities, `COLLECTION_PLAYER_COMBAT` their units (`DGE:241`), etc.
- `permanent="true"` means the effect's result is **not** auto-reverted when the source ends. For a **one-time lump** (gold grant, favor) you want `permanent="true"` so it isn't unwound; for a **per-turn rate** that should stop when an endeavor ends you leave it off. **[Confirmed in files]** — every one-shot grant/favor in `DGE` carries `permanent="true"` (e.g. `DGE:352`, `DGE:406`), while the per-turn `EFFECT_PLAYER_ADJUST_YIELD` accept-children do **not** (`DGE:249`, `DGE:36`).

---

## 1. The two yield effects you will reach for — and the trap between them

| Effect | Semantics | Real base usage | Use it for |
|---|---|---|---|
| `EFFECT_PLAYER_GRANT_YIELD` | **One-time LUMP** grant to the player | IMPROVE_TRADE_RELATIONS grants the target **+30 Gold** once (`DGE:352-355`) | Instant transfers / one-shot rewards |
| `EFFECT_PLAYER_ADJUST_YIELD` | **Per-turn RATE** change | MILITARY_AID grants the target **+2 Gold/turn** (`DGE:249-253`); OPEN_BORDERS, TRADE_MAP, FARMERS_MARKET all use it for ongoing yield (`DGE:36, 136, 185`) | Bonuses that run over an endeavor's duration |

Both take `Amount` + `YieldType`. A `type="ScaleByGameAge" extra="100"` scaler is common but its placement varies: on MILITARY_AID it sits on **`Amount`** (`DGE:251`), on IMPROVE_TRADE_RELATIONS on **`YieldType`** (`DGE:354`). `ADJUST_YIELD` rows also often carry a `Tooltip` (`DGE:252`).

> **Gotcha — RATE vs LUMP is the #1 footgun.** A permanent `EFFECT_PLAYER_ADJUST_YIELD` attached to an *instant* action sets a **rate that never stops** — it drains/credits **every turn forever**. MILITARY_AID's `+2/turn` is safe only because MILITARY_AID is a **15-turn endeavor** (`DA:333`, `BaseDuration="15"`) and the rate is unwound when it ends. IMPROVE_TRADE_RELATIONS is **instant** (`DA:353`, `BaseDuration="0"`) and therefore uses the **LUMP** `GRANT_YIELD`. **[Confirmed in files]** Gift Gold is instant (`GG-action:53`, `BaseDuration="0"`), so it uses `GRANT_YIELD` for both the +100 credit (`GG-effects:39-42`) and the −100 debit (`GG-effects:49-52`).

### 1a. Negative `GRANT_YIELD` to debit a player — no precedent, verify in-game

The worked example debits the giver with `EFFECT_PLAYER_GRANT_YIELD` `Amount="-100"` (`GG-effects:49-52`). **This has no base-game precedent.**

- **[Confirmed in files]** Across **29** `EFFECT_PLAYER_GRANT_YIELD` modifier blocks in **all `Base/modules`** (11 of them in `base-standard` alone), **zero** pass a negative `Amount`. The **92** negative `Amount` values that *do* exist in base data are on *other* effects — `ADJUST_YIELD` per-turn rates, city/tradition effects — where a negative rate is normal.
- **[Unverified in-game]** Whether the engine honors a negative lump `GRANT_YIELD` or clamps it at 0. A valid-looking arg does **not** prove the value is honored. **Confirm the giver's treasury actually drops by 100 once.** If it clamps, that child is the piece to rework (or drop, making it a free gift).

### 1b. The purpose-built gold-debit path — narrower than it looks

A `*CHANGE_INITIATOR_GOLD` effect with `RemoveGold` looks like a "purpose-built debit." Be precise about what exists:

- **[Confirmed in files]** The **only** `*CHANGE_INITIATOR_GOLD` effect in the binary is `EFFECT_DAE_FREE_CAPTURED_COMMANDER_CHANGE_INITIATOR_GOLD`; its sole declared argument is `RemoveGold`. In base data it's used at `DGE:420-422` (with `RemoveGold="true"`) and `DGE:425-426` (the reject branch, **no** arguments).
- It is **specific to the free-captured-commander ransom flow**, not a general-purpose "debit any player N gold" effect. There is **no** generic engine debit effect. Treat it as a dead end for Gift Gold and rely on the negative-`GRANT_YIELD` experiment in §1a (verified in-game) instead.

---

## 2. The gold-transfer effect Send Aid uses — and why it's a trap to reuse

`EFFECT_DAE_SEND_GOLD` is the transfer behind base "Send Aid" (`PLAYER_MOD_SEND_GOLD`, `DGE:450-451`).

- **[Confirmed in files]** The base modifier carries **no `<Argument>`s** (`DGE:450-451` is an empty body with `permanent="true"`), and the effect declares **no argument strings** in the binary — in the dump the name `EFFECT_DAE_SEND_GOLD` is immediately followed by the *next* effect (`EFFECT_DAE_START_GRANT_COOPERATIVE_YIELD`), with nothing between.
- The transfer amount does **not** live on the effect — it comes from the runtime **operation** `SEND_GOLD_DIPLOMATIC_ACTION` (the gold-amount picker), wired through `DiplomaticProjects_UI_Data.PlayerOperationType` (`DA:779`).

> **Gotcha — `EFFECT_DAE_SEND_GOLD` is useless detached from its op.** Without `SEND_GOLD_DIPLOMATIC_ACTION` driving it there is no amount, so it moves nothing. That op is **alliance-gated in the engine** (`m_bRequiresAlliance` is a real binary symbol; `SEND_GOLD` is `AllyOnly="true"`, `DA:329`) and was the only source of the picker. The worked example abandons both: it targets any met major leader via `COOPERATIVE_YIELDS_DIPLOMATIC_ACTION` (`GG-action:92`) and gifts a **fixed** amount via plain `GRANT_YIELD`. See `diplomacy-actions.md` for the targeting decision.

---

## 3. Cooperative-yield grant effects (per-side amounts)

If you want a single completion effect that grants different amounts to initiator vs target, use the cooperative-yield family rather than two attach children.

`EFFECT_DAE_COMPLETE_GRANT_COOPERATIVE_YIELD` — grant a yield to both sides **when the effect ends**. **[Confirmed in files]** Argument names from the binary cluster and the commented-out base test block (`DGE:14-28`, which exercises `Amount`/`TargetAmount`/`YieldType`):

| Arg | Meaning |
|---|---|
| `Amount` | base yield to the **initiator** |
| `TargetAmount` | base yield to the **target** |
| `EnvoyMultAmount` | initiator yield × number of envoys |
| `TargetEnvoyMultAmount` | target yield × envoys |
| `YieldType` | the yield |

Sibling effects in the same binary cluster: `EFFECT_DAE_START_GRANT_COOPERATIVE_YIELD` (grants on start), `EFFECT_DAE_GRANT_COOPERATIVE_YIELD_SUPPORT_BASE_PER_TURN` (per-turn over duration, args include `SupportAmount`, `BoostedSupportAmount`, `TargetPercent`, and `AyalyzeNumTurns` — note the engine's misspelling of "Analyze", used verbatim at `DGE:84, 94, 104, 114`), and the `EFFECT_DAE_DESCRIBE_*` variants that only generate tooltip text.

---

## 4. Accept-gating wrappers (the only way to fire on accept, not on auto-complete)

A diplomacy offer's completion-stage effects fire **regardless** of whether the target accepts. To fire **only on accept**, wrap the real effect in an attach modifier. **[Confirmed in files]** — argument names from the binary, plus live base usage:

| Effect | Args (binary, in declaration order) | Shape |
|---|---|---|
| `EFFECT_DAE_COOPERATIVE_ATTACH_MODIFIER` | `InitialPlayerAccept`, `TargetPlayerAccept`, `InitialPlayerSupport`, `TargetPlayerSupport`, `InitiatorAcceptEffectIsRemovable`, `TargetAcceptEffectIsRemovable` | both sides; each named child instantiates only when the target picks that response. Live: MILITARY_AID `DGE:234-240` |
| `EFFECT_DAE_TARGET_ATTACH_MODIFIER` | `AcceptEffectIsRemovable`, `SupportEffectIsRemovable` (the binary declares only these two after the effect name) | target-only. Live: IMPROVE_TRADE_RELATIONS `DGE:348-351`, which routes a `TargetPlayerAccept` child — that arg name is shared with the cooperative wrapper rather than re-declared in this effect's own binary cluster |

The engine strings spell out the gate verbatim, e.g. *"Modifier to give to the target player if the target selects accept"* (the description line right after `TargetPlayerAccept` in the `COOPERATIVE_ATTACH` cluster).

How the worked example uses it (`GG-effects:27-31`):

```xml
<Modifier id="PLAYER_MOD_GIFT_GOLD_COMPLETE" collection="COLLECTION_OWNER" effect="EFFECT_DAE_COOPERATIVE_ATTACH_MODIFIER">
  <Argument name="InitialPlayerAccept">PLAYER_MOD_GIFT_GOLD_INITIATOR_ACCEPT</Argument>  <!-- giver: -100 -->
  <Argument name="TargetPlayerAccept">PLAYER_MOD_GIFT_GOLD_TARGET_ACCEPT</Argument>      <!-- recipient: +100 -->
</Modifier>
```

> **Gotcha — collection ownership flips inside the children.** The wrapper makes the **target** the owner of the `TargetPlayerAccept` child, so a `COLLECTION_OWNER` + `GRANT_YIELD` child there credits the **recipient**, not the initiator. This mirrors `PLAYER_DIPLOMACY_IMPROVE_TRADE_RELATIONS_TARGET_GOLD` (`DGE:352`), which grants "the target" 30 gold using the same `COLLECTION_OWNER`. Don't add a manual `COLLECTION_PLAYER_TARGET` — the wrapper already routes it.

---

## 5. Favors & grievances (moving the relationship)

`EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES` posts a named relationship event between initiator and target. It is the canonical **engine-bound** effect (no args declared in any data/schema file) and the headline case for *reading the binary to learn arguments* (§6).

**[Confirmed in files]** — full argument set, from the binary cluster:

| Arg | Direction / meaning |
|---|---|
| `Amount` / `FavorAmount` | *"FavorAmount can be used in place of Amount"* (initiator favor) |
| `FavorsAmount` | favor to the initiator |
| `TargetFavorsAmount` | favor to the target |
| `GrievancesAmount` | grievance (negative relationship) to the initiator side |
| `TargetGrievancesAmount` | grievance to the target |
| `EventType` | *"The event to show in the relationship record"* — e.g. `FAVOR_FROM_ENDEAVOR` (positive) or `GRIEVANCE_FROM_REJECTED_ENDEAVOR` (negative) |

> **Gotcha — the positive `Favors*` args are binary-valid but [Unverified in practice].** **[Confirmed in files]** all **4** base-game usages of this effect pass only **`GrievancesAmount`** (`DGE:324, 406, 410, 414`); 3 of them add an `EventType` (`DGE:408, 412, 416`), and one (`DGE:324-327`, `CS_ORDER_ATTACK_ACTIVE`) passes `GrievancesAmount` alone. `FavorsAmount` / `TargetFavorsAmount` appear in the engine's string schema but in **no base data** — so the engine *parsing* them does not prove a positive favor is *honored*. The worked example passes both (`GG-effects:64-68`) and flags this as the first thing to change if the relationship doesn't move in-game.

**Where the mod actually binds this favor:** **not** the completion stage. It is wired to the **ACCEPT response** via `DiplomaticActionResponseModifiers` (`GG-action:136-142`, `ModifierTarget="DIPLOMACY_MODIFIER_TARGET_INITIAL"`), the symmetric counterpart of how the base game posts **grievances on REJECT** (e.g. `PLAYER_DIPLOMACY_GRIEVANCES_FOR_ACTION_REJECTION` bound to REJECT at `DA:985, 988`). Note base data only ever binds this table on REJECT, so the ACCEPT binding is **[Unverified in-game]**.

**Where base positive relationship actually comes from:** the `DiplomacyActions` **columns** `TargetFavors` / `TargetFavorsFreq` / `SupportFavors`, which tick favor **over an endeavor's duration**. **[Confirmed in files]** MILITARY_AID uses `SupportFavors="1500" TargetFavors="1000" TargetFavorsFreq="3"` (`DA:333`). Gift Gold is instant, so there's no duration to tick over — it sets those columns to `0` (`GG-action:56-57`) and relies on the response-bound favor effect instead. If your action *has* a duration, prefer the columns; they're the proven path.

---

## 6. Reading the binary for an engine effect's real arguments

Engine-bound effects (the `EFFECT_DAE_*` family, plus terse ones like `EFFECT_PLAYER_GRANT_YIELD`) **do not declare their accepted argument names in any data or schema file**. Those names are embedded as literal strings in `EXE`, clustered next to the effect name in declaration order. This is **the** way to discover an engine effect's arguments.

No `strings` binary ships with Git Bash, so extract printable runs yourself. The exe is ~806 MB; extract once, then grep the dump:

```bash
EXE="C:/Program Files (x86)/Steam/.../Civ7_Win64_DX12_FinalRelease.exe"
# 1) dump printable ASCII runs of length >=5
LC_ALL=C grep -a -o -E '[ -~]{5,}' "$EXE" > /tmp/civ7_strings.txt
# 2) read the cluster after the effect name (args follow it, in order)
grep -n -A12 "EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES" /tmp/civ7_strings.txt
```

Real output for that effect (verbatim):

```
EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES
FavorAmount can be used in place of Amount
GrievancesAmount
TargetFavorsAmount
TargetGrievancesAmount
The event to show in the relationship record   <- describes the EventType arg
Can give favors and/or grievances to the initial player and/or their target.
FavorsAmount
EFFECT_DAE_COMPLETE_IMPROVE_TRADE_RELATIONS    <- next effect: args above belong to FAVORS_GRIEVANCES
```

Tips:
- Args appear **between** the effect name and the **next** `EFFECT_*` token. If nothing appears before the next effect (as with `EFFECT_DAE_SEND_GOLD`), the effect takes **no arguments**.
- Some lines are prose, not arg names (e.g. *"The event to show in the relationship record"* describes `EventType`). Match prose to the nearest CamelCase token.
- Terse generic effects (`EFFECT_PLAYER_GRANT_YIELD`, `EFFECT_PLAYER_ADJUST_YIELD`) sit in a run of sibling effect names with **no adjacent arg strings** — their `Amount`/`YieldType` args are learned from data usage, not the binary.
- To audit how base data *uses* an effect (handles the spaced install path cleanly), e.g. confirming no base `GRANT_YIELD` uses a negative `Amount`:
  ```powershell
  Get-ChildItem "$base" -Recurse -Filter *.xml | ForEach-Object {
    [regex]::Matches((Get-Content -Raw $_.FullName),
      '(?s)<Modifier[^>]*effect="EFFECT_PLAYER_GRANT_YIELD"[^>]*>(.*?)</Modifier>')
  }  # then test each block body for <Argument name="Amount">-
  ```

> **Caveat — a valid arg string is necessary, not sufficient.** The binary proves the engine *parses* an argument name. It does **not** prove a given *value* is honored (a negative grant; a positive favor on an effect that base data only ever uses for grievances). Always confirm the in-game outcome.

---

## Gotchas (quick list)

- **LUMP vs RATE:** `GRANT_YIELD` = one-time; `ADJUST_YIELD` = per-turn. A permanent `ADJUST` on an instant action drains/credits every turn forever. **[Confirmed in files]**
- **Negative `GRANT_YIELD`:** zero base precedent (0 of 29 blocks across all Base modules); may clamp — verify the debit lands once in-game. **[Unverified in-game]**
- **`EFFECT_DAE_SEND_GOLD`:** no amount arg; amount comes from `SEND_GOLD_DIPLOMATIC_ACTION` (alliance-gated, `m_bRequiresAlliance`). Useless detached from that op. **[Confirmed in files]**
- **Positive `FavorsAmount`/`TargetFavorsAmount`:** binary-valid but in **no** base data; base positive relationship uses the `TargetFavors`/`SupportFavors` *columns* instead. **[Unverified in practice]**
- **`*CHANGE_INITIATOR_GOLD`:** only `EFFECT_DAE_FREE_CAPTURED_COMMANDER_CHANGE_INITIATOR_GOLD` exists; ransom-specific, not a general debit. **[Confirmed in files]**
- **Attach-child ownership:** inside a `TargetPlayerAccept` child, `COLLECTION_OWNER` resolves to the **target**, not the initiator. **[Confirmed in files]**
- **Accept-gating is mandatory:** plain completion-stage effects fire even on decline. Wrap them in `EFFECT_DAE_COOPERATIVE_ATTACH_MODIFIER` / `EFFECT_DAE_TARGET_ATTACH_MODIFIER`, or bind to a response via `DiplomaticActionResponseModifiers`. See `diplomacy-actions.md`. **[Confirmed in files]**

---

### Source line-number index (v1.4.0, for re-verification)

| Claim | Path:line |
|---|---|
| `GRANT_YIELD` one-time +30 gold (IMPROVE_TRADE_RELATIONS) | `DGE:352-355` |
| `ADJUST_YIELD` per-turn +2 gold (MILITARY_AID) | `DGE:249-253` |
| `COOPERATIVE_ATTACH_MODIFIER` live use (MILITARY_AID) | `DGE:234-240` |
| `TARGET_ATTACH_MODIFIER` live use (IMPROVE_TRADE_RELATIONS) | `DGE:348-351` |
| `SEND_GOLD` modifier (empty, `permanent="true"`) | `DGE:450-451` |
| Cooperative-yield test block | `DGE:14-28` |
| `AyalyzeNumTurns` (engine misspelling) live use | `DGE:84, 94, 104, 114` |
| `FAVORS_GRIEVANCES` grievance-only uses | `DGE:324, 406, 410, 414` |
| `*CHANGE_INITIATOR_GOLD` (ransom only; `RemoveGold`) | `DGE:420-422`, `DGE:425-426` |
| MILITARY_AID `BaseDuration="15"`, `SupportFavors`/`TargetFavors` | `DA:333` |
| IMPROVE_TRADE_RELATIONS `BaseDuration="0"` | `DA:353` |
| `SEND_GOLD` action `AllyOnly="true"` | `DA:329` |
| `SEND_GOLD` op `PlayerOperationType` | `DA:779` |
| Base grievance-on-REJECT bindings | `DA:985, 988` |
| Gift Gold action `BaseDuration="0"` | `GG-action:53` |
| Gift Gold favor bound to ACCEPT response | `GG-action:136-142` |
| Worked example gold/favor effects | `GG-effects:27-68` |
