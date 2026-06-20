# Localization: `EnglishText` rows (not the Civ 6 `LocalizedText` insert pattern)

Purpose: how Civ VII v1.4.0 mods define and load localized UI strings, and the Civ 6 habit that quietly breaks. Worked example: `civ-simp-gold-gifting`. See `diplomacy-actions.md` for where these tags get referenced, `modinfo-and-loading.md` for the action-group/loader model, and `TROUBLESHOOTING.md` for the blank-text symptom table.

## TL;DR

- Author English strings as `<Database><EnglishText><Row Tag="LOC_..."><Text>...</Text></Row></EnglishText></Database>`.
- Load the file with `<UpdateText><Item>...</Item></UpdateText>` inside a `<modinfo>` `<ActionGroup>` — **not** `<UpdateDatabase>`. **[Confirmed in files]**
- Do **not** hand-write a Civ-6-style `INSERT INTO LocalizedText (Tag, Language, Text)`. That column tuple matches **neither** Civ 7 `LocalizedText` table. `EnglishText` is the supported authoring entry point: a *view + `INSTEAD OF INSERT` trigger* over the in-game `LocalizedText` table. **[Confirmed in files]**
- Missing/misspelled `LOC_` tags = blank or raw-tag UI text. The text DB is a lookup table, not a foreign-key target of gameplay data, so this is a quiet failure, not a crash. **[Inferred — see reasoning below]**

## The schema reality (why "EnglishText, not LocalizedText" is subtly wrong)

There are **two unrelated `LocalizedText` tables** in Civ 7, which is the source of the confusion:

| Table | Schema file | Columns | What it's for |
|---|---|---|---|
| `LocalizedText` (in-game text) | `schema-loc-10.sql:23` | `Language, Tag, Text, Gender, Plurality` (PK `Language, Tag`) | The strings the game UI renders at runtime |
| `LocalizedText` (modinfo descriptive strings) | `schema-modding-10.sql:246` | `ModRowId, Tag, Locale, Text` | Localized mod Name/Description shown in the mod browser |

For your in-game UI strings you want the **first** one — but for English you do **not** insert into it directly. The localization schema defines `EnglishText` as a temporary view with an `INSTEAD OF INSERT` trigger that writes into `LocalizedText` with `Language = 'en_US'`:

```sql
-- Base/Assets/schema/localization/schema-loc-10.sql:32-38
CREATE VIEW EnglishText AS
    SELECT Tag, Text, Gender, Plurality FROM LocalizedText WHERE Language = 'en_US';

CREATE TRIGGER AddEnglishText INSTEAD OF INSERT ON EnglishText
BEGIN
    INSERT INTO LocalizedText ('Language', 'Tag', 'Text', 'Gender', 'Plurality')
        VALUES('en_US', NEW.Tag, NEW.Text, NEW.Gender, NEW.Plurality);
END;
```

The schema comment confirms these are *"temporary ... used to simplify the XML files ... dropped in post processing"* (`schema-loc-10.sql:30-31`). So `<EnglishText><Row>` is the intended authoring shape; it is sugar over `LocalizedText`. Note there is exactly **one** view and **one** trigger in the whole loc schema — there is no `FrenchText`/`GermanText` view (verified: only `EnglishText` matches `CREATE VIEW`/`CREATE TRIGGER` in `Base/Assets/schema/localization/`). **[Confirmed in files]**

**The Civ 6 mistake** (this mod's first text file made it — see `docs/civ7-modding/GOTCHAS.md:25-27`) is reaching for a Civ-6-style `LocalizedText` insert with columns `(Tag, Language, Text)`. That tuple matches *neither* Civ 7 table — the in-game one is `(Language, Tag, Text, Gender, Plurality)` and the modinfo one is `(ModRowId, Tag, Locale, Text)` — so it fails to populate. Use `EnglishText` rows for English and let the trigger do the insert. **[Confirmed in files]**

## The correct pattern (English)

### 1. Text file (`text/en_us/<name>.xml`)

Mirror `Base/modules/base-standard/text/en_us/DiplomacyText.xml` (root `<Database>`, then `<EnglishText>`, `DiplomacyText.xml:1-3`). This repo's `text/en_us/gift-gold-text.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Database>
  <EnglishText>
    <Row Tag="LOC_DIPLOMACY_PROJECT_GIFT_GOLD_NAME">
      <Text>Gift Gold</Text>
    </Row>
    <Row Tag="LOC_DIPLOMACY_PROJECT_GIFT_GOLD_DESCRIPTION">
      <Text>Send [icon:YIELD_GOLD]Gold directly to another leader as a gift. Improves your relationship with them.</Text>
    </Row>
    <!-- plus _REQUEST, _ACCEPT, _REJECT (gift-gold-text.xml:16-24) -->
  </EnglishText>
</Database>
```

The real file defines five tags: `_NAME`, `_DESCRIPTION`, `_REQUEST`, `_ACCEPT`, `_REJECT` (`gift-gold-text.xml:10-24`).

### 2. Load it via `<UpdateText>` in the modinfo

Text files load through `<UpdateText>`, **not** `<UpdateDatabase>`. From this repo's `civ-simp-gold-gifting.modinfo:33-35`:

```xml
<UpdateText>
  <Item>text/en_us/gift-gold-text.xml</Item>
</UpdateText>
```

This matches the base game, which lists every English text file under one big `<UpdateText>` block opening at `base-standard.modinfo:466` (e.g. `<Item>text/en_us/ActionPanelText.xml</Item>` at line 469). **[Confirmed in files]**

> Note: the empty `<LocalizedText></LocalizedText>` element at the *modinfo root* (`base-standard.modinfo:1077`) is the **modinfo descriptive-strings** mechanism (the second table above — for the mod's own Name/Description), not your in-game UI text. Don't conflate it with `<EnglishText>` rows.

## Markup you can use inside `<Text>`

All confirmed against base `DiplomacyText.xml`:

| Markup | Meaning | Real example |
|---|---|---|
| `[icon:YIELD_GOLD]` | Inline icon glyph | `LOC_DIPLOMACY_PROJECT_COST_GOLD` → `{1_costGold} [icon:YIELD_GOLD].` (`DiplomacyText.xml:13-14`) |
| `{1_paramName}` | Runtime parameter supplied by the calling system | `{1_leaderName} is requesting that you open your borders to them.` (`DiplomacyText.xml:83`) |
| `[n]` | Line break | `...Influence is refunded.[n]No new Endeavors...` (`DiplomacyText.xml:86`) |
| `[TIP:LOC_..._TOOLTIP]text[/TIP]` | Hover tooltip wrapping inline text | `[TIP:LOC_PEDIA_CONCEPTS_CITY_STATE_TOOLTIP]City-State[/TIP]` (`DiplomacyText.xml:23`) |

`[icon:YIELD_GOLD]` is heavily used — 20 occurrences in `DiplomacyText.xml`, 183 across `base-standard/text/en_us/`, and 608 across all base/DLC module `en_us` text (verified counts; treat them as indicative, not load-bearing). Parameter tokens like `{1_leaderName}` / `{1_initialName}` are the standard way leader names get injected; this repo reuses exactly those names (`{1_leaderName}` at `gift-gold-text.xml:17`; `{1_initialName}` at `:20,23`). **[Confirmed in files]**

> Parameter numbering/names (e.g. `{1_leaderName}` vs `{1_initialName}`) are dictated by **what the calling code/diplomacy system passes in**, not chosen freely. Reuse the token names the base game uses for the same context (request prompts use `{1_leaderName}`; accept/reject responses use `{1_initialName}`) so the substitution resolves. **[Inferred from base usage patterns]**

## Reuse existing tags before minting your own

Many response/label strings already ship in base — reuse them and only define tags for your own copy. Confirmed present in `DiplomacyText.xml`:

| Tag | Text | Line |
|---|---|---|
| `LOC_DIPLOMACY_RESPONSE_ACCEPT` | `Accept` | `DiplomacyText.xml:1715-1716` |
| `LOC_DIPLOMACY_RESPONSE_ACCEPTED` | `Accepted` | `DiplomacyText.xml:1718-1719` |
| `LOC_DIPLOMACY_RESPONSE_REJECT` | `Reject` | `DiplomacyText.xml:1721-1722` |
| `LOC_DIPLOMACY_RESPONSE_REJECTED` | `Rejected` | `DiplomacyText.xml:1724-1725` |

So you typically only author NAME / DESCRIPTION / REQUEST plus any custom accept/reject *flavor* lines (as this mod does), and lean on base `LOC_DIPLOMACY_RESPONSE_*` for generic button labels. **[Confirmed in files]**

## Why a bad tag is a *quiet* failure

The localization DB is separate, populated by `<UpdateText>`, and resolved by tag at render time. A `LOC_` tag referenced from gameplay/UI but never defined has no row to look up, so the UI shows blank text or the raw `LOC_...` tag — but nothing in the **gameplay** database load depends on that row existing, so the mod still loads and runs. **[Inferred]** — consistent with the design (text is a view-backed lookup table, not a foreign-key target of gameplay data) but not reproduced live in v1.4.0; treat the "does not block load" specifics as **[Inferred]**. Practical takeaway: *if your action appears with empty/placeholder labels, suspect a missing or misspelled `LOC_` tag or a text file you forgot to list under `<UpdateText>`, not a crash* (see `TROUBLESHOOTING.md:45`).

## Other locales (the real pattern, and why it differs from English)

English is special-cased through the `EnglishText` view. **Every other language inserts directly into the in-game `LocalizedText` table** — there is no per-locale view. The base game authors non-English text with `<LocalizedText>` + `<Replace>` carrying an explicit `Language` attribute:

```xml
<!-- Base/modules/base-standard/l10n/fr_FR_Text.xml:2-8 -->
<Database>
  <LocalizedText>
    <Replace Tag="LOC_ARMYNAME_PREFIX_1ST" Language="fr_FR">
      <Text>Le Premier|La Première|Les Premiers|Les Premières</Text>
      <Gender>masculine|feminine|masculine|feminine</Gender>
      <Plurality>2</Plurality>
    </Replace>
    ...
```

Conventions, all **[Confirmed in files]**:

- Non-English files live at `l10n/<locale>_Text.xml` (e.g. `l10n/fr_FR_Text.xml`), **not** `text/<locale>/`. The `l10n/<locale>/` *folders* hold only `.vtt` subtitles.
- They are listed in the **same** `<UpdateText>` block as English, but each `<Item>` carries a `locale` attribute: `<Item locale="fr_FR">l10n/fr_FR_Text.xml</Item>` (`base-standard.modinfo:566-576`). English items in that block have **no** locale attribute (`:467-563`).
- Supported locales are enumerated in `schema-loc-20-languages.sql:2-13` (en_US, fr_FR, de_DE, it_IT, es_ES, ja_JP, ru_RU, pt_BR, pl_PL, ko_KR, zh_Hans_CN, zh_Hant_HK).

So the blanket "never insert into `LocalizedText`" is too strong: the **non-English** path legitimately does, via `<Replace ... Language="...">`. The Civ 6 mistake is specifically the wrong *column tuple* `(Tag, Language, Text)` in a raw SQL-style insert. This repo only ships `en_us`, so the non-English authoring shape above is **[Confirmed in files]** from the base game but **[Unverified]** end-to-end for this mod.

## Gotchas

- **Use `<UpdateText>`, never `<UpdateDatabase>`, for text files.** `<UpdateDatabase>` targets the gameplay DB; your text rows belong to the localization DB.
- **Don't write Civ-6 `INSERT INTO LocalizedText (Tag, Language, Text)`.** That column tuple matches neither Civ 7 `LocalizedText` table. Author `<EnglishText><Row>` for English; `<LocalizedText><Replace Language="...">` for other locales. **[Confirmed in files]**
- **Root element is `<Database>`, child is `<EnglishText>`** (English) or `<LocalizedText>` (other locales) — not `<GameData>`/`<GameInfo>`.
- **Tag typos fail silently** in the UI; there is no load error. Grep your gameplay/data XML for every `LOC_` tag and confirm each has a defining `<Row Tag=...>`.
- **Forgetting to list the file under `<UpdateText>`** produces the same blank-text symptom as a typo. Check the modinfo first.
- **Other-locale items need `locale="..."` on the `<Item>`**, and use `l10n/<locale>_Text.xml` (not `text/<locale>/`). Omitting the attribute or using the English `<EnglishText>` shape for another language won't localize correctly.