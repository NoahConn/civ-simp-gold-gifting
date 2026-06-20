# Gotchas log

A running log of traps we fell into, in the order we learned them. Each entry: the trap,
what actually happened, and the takeaway. The point is to preserve the *reasoning* (not
just the fix) so future devs/AI understand **why**. Append new entries at the bottom; promote
durable conclusions into the topic docs and the [troubleshooting table](TROUBLESHOOTING.md).

Confidence: **[confirmed in-game]**, **[confirmed in files]**, **[inferred]**.

---

### 1. "Endeavors" don't exist as a table — it's all diplomacy actions  **[confirmed in files]**
The mod was scaffolded around a generic "endeavor" abstraction with `<< >>` placeholder
tokens. There is no such table. Player-to-player cooperative actions are **diplomacy
actions** (`Kind = KIND_DIPLOMACY_ACTION`). Most "how to make an endeavor" intuition comes
from Civ 6, which is different.
**Takeaway:** find the real base-game analog first; don't model from a borrowed mental model.

### 2. Most online docs are Civ 6 and mislead  **[confirmed in files]**
Civ 6's `DiplomaticActions` schema did not carry over. The install is the only reliable
source of truth.
**Takeaway:** grep the install + read the binary; treat web results as hints at best. See
[`finding-the-truth.md`](finding-the-truth.md).

### 3. Localization is `<EnglishText>`, not `LocalizedText`  **[confirmed in files]**
The first text file used the Civ 6 `LocalizedText (Tag, Language, Text)` SQL table. Civ 7
uses `<Database><EnglishText><Row Tag><Text>` loaded via `<UpdateText>`.
**Takeaway:** wrong-table localization fails quietly (blank UI), not loudly.

### 4. Engine effect arguments live in the binary, not in data  **[confirmed in files]**
`EFFECT_DAE_*` effects are engine-bound; their accepted argument names are **not** declared
in any data/schema file. They *are* present as literal strings in
`Base/Binaries/Win64/Civ7_Win64_DX12_FinalRelease.exe`. Reading those strings resolved the
favor-effect argument names when nothing in the data files would.
**Takeaway:** the binary is a legitimate, often necessary, source of truth. **But:** a valid
argument *name* doesn't prove a given *value* is honored (see #9).

### 5. The reused operation carries a compiled ally-gate the data can't override  **[confirmed in-game]**
We cloned "Send Aid" (`SEND_GOLD`) to reach non-allies and set `AllyOnly="false"` — but got
**"No Valid Targets."** The op `SEND_GOLD_DIPLOMATIC_ACTION` has an alliance requirement
compiled into the engine (`m_bRequiresAlliance` / `FAILURE_NOT_ALLIES`); the data column
doesn't reach it. That same op is also the only source of the runtime gold-amount picker.
**Takeaway:** `PlayerOperationType` is an engine operation with its own logic. To target
non-allies use `COOPERATIVE_YIELDS_DIPLOMATIC_ACTION` — and accept that you lose the picker.

### 6. The auto-suggested "fix" would have gifted 0 gold  **[confirmed in files]**
After switching ops, the obvious move (keep `EFFECT_DAE_SEND_GOLD`, add an `Amount`) is a
no-op: that effect reads its amount from the `SEND_GOLD` operation context, which no longer
exists. Adversarial verification caught this before a wasted test.
**Takeaway:** verify the effect actually *delivers*, not just that it's "wired up."

### 7. `ADJUST_YIELD` is a per-turn rate; `GRANT_YIELD` is a lump  **[confirmed in files]**
A proposed giver-debit used `EFFECT_PLAYER_ADJUST_YIELD` `-100` — which would drain 100 gold
**every turn forever**, not once. `MILITARY_AID` uses ADJUST for a 15-turn aid stipend;
`IMPROVE_TRADE_RELATIONS` (instant) uses `EFFECT_PLAYER_GRANT_YIELD` for a one-time payout.
**Takeaway:** match the effect to instant-vs-duration. GRANT = once, ADJUST = per turn.

### 8. Omitted columns take the schema DEFAULT, not zero  **[confirmed in files]**
We theorized our action auto-completed because `UIStartProject`/`SupportFavors` were "unset."
They weren't — `01_GameplaySchema.sql` defaults `UIStartProject` to `1` and `SupportFavors`
to `100`. The broken action already *had* them on.
**Takeaway:** read the `CREATE TABLE` default before reasoning about a column's live value.

### 9. Positive-favor args are unattested in base data  **[inferred]**
`EFFECT_DAE_COMPLETE_GRANT_FAVORS_GRIEVANCES` is given only `GrievancesAmount` (negative) in
all shipped data; `FavorsAmount`/`TargetFavorsAmount` appear in the binary but in no data
row, so they may be ignored. Base positive relationship comes from the `DiplomacyActions`
`TargetFavors`/`SupportFavors` columns instead.
**Takeaway:** "the binary lists the arg" ≠ "this effect honors it here." Still needs an
in-game check; prefer the column-driven path for relationship gains.

### 10. THE big one — no reaction without a `DiplomaticActionResponses` row  **[confirmed in-game + binary]**
The action fired (played a sound) but silently auto-completed: `DiplomacySummary.csv` showed
`target=-1`, instant `Success`, no accept/decline, no effects — in both single-player **and**
multiplayer (even with a human receiver). The engine decides whether to show an accept/decline
window by querying the **`DiplomaticActionResponses`** table (a literal `SELECT ... FROM
DiplomaticActionResponses` in the binary); with no row it resolves `DIPLOMACY_RESPONSE_NOT_NEEDED`
and self-resolves on the initiator. `SEND_GOLD` reacts *solely* because of its `ACCEPT` row.
We had earlier **deleted** our `DiplomaticActionResponses` row and replaced it with
`DiplomaticActionResponseModifiers` — a different table that only attaches effects *after* a
response and does **not** create one. That deletion is why every effect (all accept-gated)
never fired.
**Takeaway:** `DiplomaticActionResponses` = the accept/decline buttons. No row → silent
auto-complete. It is **not** gated by action group, operation, or `UIStartProject`.

### 11. An installer's "end-to-end test" clobbered the dev junction  **[confirmed in-game]**
A subagent ran the real installer on the dev machine, which replaced the live Mods-folder
**junction** with a static copy — silently breaking live edits.
**Takeaway:** sandbox destructive/installer tests to temp paths; never run the real installer
against your dev machine. Re-create the junction if this happens
([`dev-environment.md`](dev-environment.md)).

---

*Status at last update: the action now has its `DiplomaticActionResponses` rows back (#10);
pending in-game confirmation that the accept/decline window appears and that gold/relationship
deliver (the #7/#9 effect pieces are the next to verify).*
