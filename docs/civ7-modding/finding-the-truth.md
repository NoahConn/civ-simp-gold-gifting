# Methodology: don't guess — mine the install

> The install is the source of truth for Civ 7 (v1.4.0) modding. Public docs are thin and mostly Civ 6 (which differs). This file teaches the verification workflow that built `civ-simp-gold-gifting`; for the resulting action schema see `diplomacy-actions.md` and `game-effects-modifiers.md`.

---

## Why this matters

Civ 7 modding is poorly documented publicly, and most search hits are for Civ 6, whose schema and modifier system are **not** compatible. During this mod almost every "obvious" online answer was wrong or absent (there is, for example, no generic *endeavor* table — see below). Every claim that survived was one we verified directly against the shipped files.

The two roots you will mine constantly:

| What | Path |
|---|---|
| Game install (source of truth) | `C:/Program Files (x86)/Steam/steamapps/common/Sid Meier's Civilization VII` |
| Worked-example mod | `C:/Users/noahd/Desktop/claude_projects/civ-simp-gold-gifting` |

The file classes that answer almost everything:

| Source | Path (under install) | Answers |
|---|---|---|
| Gameplay schema | `Base/Assets/schema/gameplay/01_GameplaySchema.sql` | `CREATE TABLE` column lists + **DEFAULT** values |
| Base data | `Base/modules/**/data/*.xml` | real `<Row>` examples to mirror |
| Localization | `Base/modules/**/text/en_us/*.xml` | `<Row Tag="LOC_…"><Text>…</Text></Row>` strings (file root is `<EnglishText>`) |
| Game effects | `Base/modules/**/data/*-gameeffects.xml` | `<Modifier>` / effect definitions |
| Engine binary | `Base/Binaries/Win64/Civ7_Win64_DX12_FinalRelease.exe` | the literal load SQL, effect arg schemas, enum values, C++ source names |

---

## Rule 1 — Mirror a working base analog end-to-end; never invent

The reliable method: find the **closest base action/feature** and copy its full wiring across **every** table, then change only what you must. A diplomacy action is not one row — it is the same key threaded through ~9 tables, and missing any one silently breaks it.

**[Confirmed in files]** The base game ships `DIPLOMACY_ACTION_SEND_GOLD` (display name "Send Aid"; `LOC_DIPLOMACY_PROJECT_SEND_GOLD_NO_DATA` = "Send Gold to an ally" — `base-standard/text/en_us/DiplomacyText.xml:169,172`), an ally-only Gold gift. `civ-simp-gold-gifting` clones it. Every table the clone touches has a base `SEND_GOLD` row at a known line in `base-standard/data/diplomacy-actions.xml`:

| Table (container tag) | SEND_GOLD row | Note |
|---|---|---|
| `Types` | `:39`, `:105` | action `Kind=KIND_DIPLOMACY_ACTION` + stage `Kind=KIND_DIPLOMACY_ACTION_STAGE` |
| `DiplomacyActions` | `:329` | `AllyOnly="true"` here is the alliance gate |
| `DiplomaticActionValidTokens` | `:391` | `DIPLOMACY_TOKEN_GLOBAL` |
| `DiplomaticActionStages` | `:453` | `ProgressRequirement="0"` = instant |
| `EnterStageModifiers` | `:598` | binds `PLAYER_MOD_SEND_GOLD` |
| `DiplomaticProjects_UI_Data` | `:779` | `PlayerOperationType="SEND_GOLD_DIPLOMATIC_ACTION"` + targets |
| `DiplomacyBonusEnvoyData` | `:885` | all-zero |
| `DiplomaticActionInfluenceCosts` | `:921` | per-relationship cost (all zero) |
| `DiplomaticActionResponses` | `:936` | the `ACCEPT` row that creates the reaction window |

The lesson learned the hard way: an earlier rewrite **deleted** the `DiplomaticActionResponses` row, and the action silently auto-completed with no target reaction. The base `SEND_GOLD` reacts *solely* because of its `ACCEPT` row at `diplomacy-actions.xml:936`. Mirror the analog's rows first; subtract only after you understand each one. (Full story in `TROUBLESHOOTING.md`.)

> Pick the *closest* analog, not just any. `SEND_GOLD` is ally-only (`AllyOnly="true"`, `diplomacy-actions.xml:329`) and uses the bespoke `PlayerOperationType="SEND_GOLD_DIPLOMATIC_ACTION"` (`:779`) with a runtime gold-amount picker. The non-ally cooperative actions — `MILITARY_AID` (`DiplomacyActions` row `:333`; UI_Data row `:783`) and `IMPROVE_TRADE_RELATIONS` (`DiplomacyActions` row `:353`; UI_Data row `:803`) — instead use `PlayerOperationType="COOPERATIVE_YIELDS_DIPLOMATIC_ACTION"` and were the right model for a non-ally gift. The mod mixes flags from both. **Note the split:** `AllyOnly` lives on the `DiplomacyActions` row; `PlayerOperationType` lives on the `DiplomaticProjects_UI_Data` row.

---

## Rule 2 — grep the install before you write a line

Targets, in priority order:

```bash
CIV="C:/Program Files (x86)/Steam/steamapps/common/Sid Meier's Civilization VII"

# Real data rows to copy (the analog hunt):
grep -rn "SEND_GOLD" "$CIV/Base/modules"/*/data/*.xml

# The exact column list + DEFAULTs for a table (note the single quotes around the name):
grep -n "CREATE TABLE 'DiplomacyActions'" \
  "$CIV/Base/Assets/schema/gameplay/01_GameplaySchema.sql"

# A LOC tag's text:
grep -rn "LOC_DIPLOMACY_PROJECT_SEND_GOLD" "$CIV/Base/modules"/*/text/en_us/*.xml

# A modifier / effect definition:
grep -rn "EFFECT_DAE" "$CIV/Base/modules"/*/data/*-gameeffects.xml
```

**[Confirmed in files]** The schema has **488** `CREATE TABLE` statements across **5192** lines (`01_GameplaySchema.sql`) — you will not memorize it; grep it every time. Table names in `CREATE TABLE` are wrapped in single quotes (`CREATE TABLE 'DiplomacyActions' (` at `:1392`), so match that form.

**[Confirmed in files] There is no generic "Endeavor" table.** `grep -niE "CREATE TABLE.*[Ee]ndeavor" 01_GameplaySchema.sql` returns nothing (exit 1). Cooperative player-to-player actions are modeled as **diplomacy actions** (`Kind = KIND_DIPLOMACY_ACTION`); "endeavor" survives only as a UI grouping (`DiplomacyActionGroup="DIPLOMACY_ACTION_GROUP_ENDEAVOR"`). Half a day was lost looking for the table the Civ-6-era mental model said should exist. When grep on the install returns nothing, the concept probably does not exist under that name — stop guessing and find what the base game actually calls it.

---

## Rule 3 — Read the engine binary strings (the tool of last resort that worked)

`Civ7_Win64_DX12_FinalRelease.exe` is **806,040,864 bytes (~806 MB)** and embeds printable strings the data files never expose. When nothing else could answer a question, the binary did. There is no `strings` binary on this box and the bundled `python3` is the Microsoft Store stub — use **perl** (real, at `/usr/bin/perl`) to scan in chunks:

```perl
# tools idiom: scan the 806MB exe for literal needles with context
perl -e '
  my $p=shift @ARGV;
  open(my $f,"<:raw",$p) or die "open: $!"; my $prev="";
  while(read($f,my $b,8*1024*1024)){
    my $d=$prev.$b;
    for my $n (@ARGV){ my $i=0;
      while(($i=index($d,$n,$i))>=0){
        my $s=substr($d,$i-40,length($n)+160); $s=~s/[^\x20-\x7e]/ /g;
        print "$n  =>  $s\n"; $i+=length($n); } }
    $prev=substr($d,-8192);
  }' "C:/Program Files (x86)/Steam/steamapps/common/Sid Meier's Civilization VII/Base/Binaries/Win64/Civ7_Win64_DX12_FinalRelease.exe" \
     "NEEDLE_ONE" "NEEDLE_TWO"
```

Four kinds of truth came out of the binary, each verified for this doc:

**1. The literal load SQL — reveals which columns the engine actually reads.** Searching `FROM DiplomaticActionResponses` returns the verbatim query:
```
... Type, CostDescription, Description, InfCost, Name
  FROM DiplomaticActionResponses ORDER BY rowid
```
(The leading select column is `Type`, the action-response key — *not* the `DiplomacyActionType` foreign key; the latter shows up in a separate join query.) This is *why* deleting the `DiplomaticActionResponses` row broke the action: the engine runs this literal `SELECT`, and with no row it builds no accept/decline buttons. If the engine reads a column via `SELECT`, that column matters even when the schema lets you omit it.

**2. Enum values.** `DIPLOMACY_RESPONSE_NOT_NEEDED` is real and sits clustered with `DIPLOMACY_RESPONSE_REJECT` / `DIPLOMACY_RESPONSE_ACCEPT` and the `DIPLOMACY_MODIFIER_TYPE_*` / `DIPLOMACY_MODIFIER_TARGET_*` enums. That `NOT_NEEDED` value is what the engine resolves to when no response row exists — the auto-complete bug, named.

**3. Effect argument schemas not declared anywhere in data.** `EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES` accepts arguments that **most shipped data never passes**. The binary embeds the schema as literal strings:
```
…E_GRANT_FAVORS_GRIEVANCES
FavorAmount can be used in place of Amount
GrievancesAmount   TargetFavorsAmount   TargetGrievancesAmount
The event to show in the relationship record      <- the EventType arg
Can give favors and/or grievances to the initial player and/or their target.
```
**[Confirmed in files]** Across all `Base/modules`, shipped data passes only `GrievancesAmount` (positive integers — 1/15/30/20 in `base-standard/data/diplomacy-gameeffects.xml:322,407,411,415` — grievances worsen relations) and `EventType` (5 files, e.g. `GRIEVANCE_FROM_REJECTED_ENDEAVOR` at `:408`). The *favor-side* arg names **`FavorsAmount` / `TargetFavorsAmount`** (and `FavorAmount` / `TargetGrievancesAmount`) appear in **zero** data files — the binary is the *only* source that confirms them. The mod's relationship favor (`data/gift-gold-effects.xml:64-68`) relies on `FavorsAmount` / `TargetFavorsAmount` / `EventType`; without the binary the two favor names would be unverifiable guesses.

**4. C++ source file names + compiled gates.** Right after each load `SELECT` the binary carries the source path, e.g. `G:/BuildAgent/work/2d0e2181d6461615/dev/Civ7/Src/GameCore/Base/Common/Definitions/Definition_DiplomaticActionInfluenceCosts.cpp` — useful for guessing which subsystem owns a behavior. And `m_bRequiresAlliance` appears as a field name (clustered with `m_bStandardYieldOff`): a **compiled-in** alliance gate that the `AllyOnly` data column cannot override — the reason the mod could not just flip `AllyOnly="false"` on `SEND_GOLD` and had to switch from `SEND_GOLD_DIPLOMATIC_ACTION` to `COOPERATIVE_YIELDS_DIPLOMATIC_ACTION`.

> Practical note: scanning 806 MB takes a few seconds. Restrict to 2–4 needles per run, keep an 8 KB overlap between chunks so a needle straddling a boundary isn't missed, and map non-printable bytes to spaces so adjacent strings read cleanly.

---

## Rule 4 — Beware schema DEFAULTs: "we didn't set X" ≠ "X is off"

A column omitted from your `<Row>` takes the table's `CREATE TABLE` **DEFAULT**, which is frequently *not* zero/false. Always read the default before theorizing about behavior.

**[Confirmed in files]** in `01_GameplaySchema.sql`:

| Column | Default | Line |
|---|---|---|
| `UIStartProject` | `BOOLEAN NOT NULL DEFAULT 1` (on!) | `:1647` |
| `SupportFavors` | `INTEGER NOT NULL DEFAULT 100` | `:1428` |

So a `DiplomaticProjects_UI_Data` row that omits `UIStartProject` gets `1`, not off. Before concluding "X is disabled because we never set it," run:
```bash
grep -n "'<ColumnName>'" "$CIV/Base/Assets/schema/gameplay/01_GameplaySchema.sql"
```

---

## Rule 5 — Per-age content: base-standard isn't the whole game

Some definitions live **per age**, not in `base-standard`. A `base-standard`-only search will miss them.

**[Confirmed in files]** every age ships its own effects, e.g. `Base/modules/age-antiquity/data/diplomacy-gameeffects.xml`. That one age folder holds **31** `*-gameeffects.xml` files; there are **123** across all of `Base/modules`. When a modifier or effect "doesn't exist," widen the search:
```bash
find "$CIV/Base/modules" -name "*-gameeffects.xml"   # all ages, not just base-standard
```

---

## The repo's own discovery tool

`civ-simp-gold-gifting/tools/discover-schema.sh` automates Rules 1–2. It auto-detects the install (or honors `CIV_DIR=…`), then greps the base modules for the diplomacy/effect/relationship schema names this mod needed: files mentioning `Endeavor`/`DiplomaticAction`, `INSERT INTO` / `CREATE TABLE` targets, `KIND_*(ENDEAVOR|DIPLOMA)` values, and effect names matching `EFFECT_*(GOLD|TREASURY)` and `EFFECT_*(RELATIONSHIP|DIPLOMAC|FAVOR|ATTITUDE)`. It reads only shipped `*.xml` / `*.sql` / `*.modinfo` files (`--include` filters in the script) — **no game launch required**. Use it as the first pass when starting a new feature; fall back to the perl binary scan (Rule 3) for anything the data files don't declare.

> The script's header still references an early `data/gift-gold-endeavor.sql`; the mod shipped instead as two authoring files, `data/gift-gold-action.xml` (the ~9 table rows) and `data/gift-gold-effects.xml` (the `<GameEffects>` modifiers). The discovery logic is unchanged — only the file layout evolved.

---

## Gotchas

- **No generic `Endeavor` table** — cooperative actions are `KIND_DIPLOMACY_ACTION`; "endeavor" is only a `DiplomacyActionGroup`. Don't port Civ-6 mental models.
- **Most online results are Civ 6.** Treat community threads as orientation only; verify everything against the install. (The mod's `docs/schema-notes.md:101` lists the community links it consulted, all marked "for orientation only.")
- **A diplomacy action is ~9 coordinated rows**, not one. Missing the `DiplomaticActionResponses` row makes the action auto-complete with no target reaction (the engine resolves `DIPLOMACY_RESPONSE_NOT_NEEDED`) — and the failure is silent.
- **Omitted column ≠ zero.** Check the `CREATE TABLE` DEFAULT (`UIStartProject` defaults to `1`, `SupportFavors` to `100`).
- **An effect's valid arguments may exist only in the binary**, never in data — e.g. `FavorsAmount` / `TargetFavorsAmount` for `EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES`. If a `<Modifier>` argument seems undocumented, grep the exe before assuming it's a guess.
- **`m_bRequiresAlliance` and friends are compiled gates** — some restrictions live in C++, not in a data column you can flip. `SEND_GOLD`'s `SEND_GOLD_DIPLOMATIC_ACTION` operation is alliance-gated in the engine; flipping `AllyOnly="false"` won't help — switch `PlayerOperationType` (to `COOPERATIVE_YIELDS_DIPLOMATIC_ACTION`) instead.
- **Split flags across tables** — `AllyOnly` is on the `DiplomacyActions` row; `PlayerOperationType` is on the `DiplomaticProjects_UI_Data` row. Don't expect one row to carry both.
- **Search all ages**, not just `base-standard` — per-age `*-gameeffects.xml` files (31 in age-antiquity alone, 123 total) hold real definitions.
- **No `strings`/usable `python3` on the modding PC** — the perl chunk-scanner above is the portable way to read the binary.

See also: `diplomacy-actions.md` (the full table-by-table action schema), `game-effects-modifiers.md` (the `<Modifier>` system and effect args), `GOTCHAS.md`, and `TROUBLESHOOTING.md`.