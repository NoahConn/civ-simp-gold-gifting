# Schema notes — resolved against the 1.4.0 install

Status as of 2026-06-18. The `<< >>` token template that originally lived in
`data/gift-gold-endeavor.sql` is gone: the real schema was resolved by reading the
installed base game (1.4.0) and the action is now implemented in
`data/gift-gold-action.xml` + `data/gift-gold-effects.xml`. This file records what
was confirmed and the single remaining assumption.

## The big correction

There is **no generic "endeavor" table**. Civ VII models player-to-player cooperative
actions as **diplomacy actions** (`Kind = KIND_DIPLOMACY_ACTION`). The base game already
ships `DIPLOMACY_ACTION_SEND_GOLD` ("Send Aid"), which gifts Gold to an **ally**. Our mod
clones it under a new type, removes the ally restriction, and adds a relationship favor.

Reference files in the install
(`C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VII`):

- `Base/Assets/schema/gameplay/01_GameplaySchema.sql` — CREATE TABLE definitions
  (`DiplomacyActions`, `DiplomaticActionStages`, `EnterStageModifiers`,
  `DiplomaticProjects_UI_Data`, `DiplomacyBonusEnvoyData`,
  `DiplomaticActionInfluenceCosts`, `DiplomaticActionResponses`, `Modifiers`,
  `ModifierArguments`, `DynamicModifiers`, `GameEffects`, `Types`, ...).
- `Base/modules/base-standard/data/diplomacy-actions.xml` — the full `SEND_GOLD`
  definition (Types ~L39/L105, DiplomacyActions ~L329, ValidTokens ~L391,
  Stages ~L453, EnterStageModifiers ~L598, UI_Data ~L779, BonusEnvoyData ~L885,
  InfluenceCosts ~L921, Responses ~L936). Root element: `<Database>`.
- `Base/modules/base-standard/data/diplomacy-gameeffects.xml` — `PLAYER_MOD_SEND_GOLD`
  (effect `EFFECT_DAE_SEND_GOLD`, ~L450) and the favor/grievance modifiers
  (effect `EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES`, ~L406-417). Root element:
  `<GameEffects xmlns="GameEffects">`.
- `Base/modules/base-standard/text/en_us/DiplomacyText.xml` — localization via
  `<Database><EnglishText><Row Tag="..."><Text>...</Text></Row>`.

## Confirmed

- **Action Kind:** `KIND_DIPLOMACY_ACTION`. **Stage Kind:** `KIND_DIPLOMACY_ACTION_STAGE`.
- **Both file formats load through `<UpdateDatabase>`.** The base `base-standard.modinfo`
  lists `diplomacy-actions.xml` (a `<Database>` file) and `diplomacy-gameeffects.xml`
  (a `<GameEffects>` file) under one `<UpdateDatabase>` block. The loader detects the root
  element, so our manifest does the same.
- **Gold transfer:** `EFFECT_DAE_SEND_GOLD`. The base modifier carries no amount argument;
  the amount comes from the runtime operation `SEND_GOLD_DIPLOMATIC_ACTION`, which we reuse
  via `DiplomaticProjects_UI_Data.PlayerOperationType` so the gold-amount picker appears.
- **Relationship model:** numeric, bucketed by `DiplomacyPlayerRelationships`
  (Hostile -30..-2, Unfriendly, Neutral -1..1, Friendly 1..2, Helpful 2..30). Relationship
  is moved by favor (positive) and grievance (negative) events.
- **A positive favor event already exists:** `FAVOR_FROM_ENDEAVOR`
  (`DiplomacyFavorsGrievancesEventsData`, group `DIPLOMACY_FAVOR`). We reuse it rather than
  declaring a new event type.

## The favor argument — RESOLVED against the engine binary

`EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES` is **engine-bound**: its accepted argument
names are not declared in any data or schema file, and across all shipped base *data* only
`GrievancesAmount` (negative) is ever passed. That originally made `FavorsAmount` look like a
guess. It is not — the engine binary embeds the effect's argument schema as literal strings.

In `Base/Binaries/Win64/Civ7_Win64_DX12_FinalRelease.exe`, the printable strings clustered with
`EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES` are:

```
EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES
FavorAmount can be used in place of Amount
GrievancesAmount
TargetFavorsAmount
TargetGrievancesAmount
The event to show in the relationship record        <- the EventType arg
Can give favors and/or grievances to the initial player and/or their target.
FavorsAmount
```

So the effect accepts `Amount`/`FavorAmount`, `FavorsAmount`, `GrievancesAmount`,
`TargetFavorsAmount`, `TargetGrievancesAmount`, and a single `EventType`. We pass `FavorsAmount`
(favor to the initiator) **and** `TargetFavorsAmount` (favor to the target) so the relationship
improves in both directions, with `EventType="FAVOR_FROM_ENDEAVOR"` (a positive event, group
`DIPLOMACY_FAVOR`). `COLLECTION_OWNER` matches every base diplomacy-completion favor/grievance
modifier.

What the files still cannot tell us — confirm in-game:
- the exact in-UI relationship magnitude of `10` favor (tune in `data/gift-gold-effects.xml`);
- which side `FavorsAmount` vs `TargetFavorsAmount` lands on (we grant both, so a visible
  improvement is expected regardless of the mapping).

### Why not the `TargetFavors` column instead

The base game grants positive favor on **duration-based** endeavors via the
`DiplomacyActions.TargetFavors` / `TargetFavorsFreq` columns (e.g. MINOR_TRADE uses
`TargetFavors="1000" TargetFavorsFreq="3"`). That path ticks favor *over an endeavor's duration*.
Gift Gold is **instant** (`BaseDuration="0"`, single COMPLETE stage), so there is no duration to
tick over — the completion-stage modifier above is the correct mechanism, and `TargetFavors`
stays `0`.

## Why we mirror SEND_GOLD's flags exactly

`Symmetrical="true"` and `IsMutualSupport="true"` are kept as-is from SEND_GOLD so the reused
engine operation behaves identically. If non-ally gifting behaves oddly (e.g. the target is
treated as a mutual-support partner), these flags are the place to revisit — but mirroring
first minimises the chance the engine operation misbehaves.

## Sources consulted (community, for orientation only — the install is the source of truth)

- CivFanatics — Civ 7 Modding Questions: https://forums.civfanatics.com/threads/civ-7-modding-questions.695200/
- CivFanatics — Dynamic modifiers, effects, collections and arguments: https://forums.civfanatics.com/threads/chapter-2-dynamic-modifiers-effects-collections-and-arguments.608917/
- izica/civ7-modding-tools: https://github.com/izica/civ7-modding-tools
- mateicanavra/civ7-modding-tools: https://github.com/mateicanavra/civ7-modding-tools
