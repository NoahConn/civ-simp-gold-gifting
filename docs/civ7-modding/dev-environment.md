# Dev environment: install paths, the junction dev loop, tooling

Practical Windows setup for fast iteration on a Civ VII (v1.4.0) mod: where the game and Mods folders live, a no-admin live-edit loop via a directory junction, and the tooling used on this repo.

This is the "get productive" companion to the schema/diplomacy docs. For *what* the example mod does, see `diplomacy-actions.md` and `gift-gold-effects.md`; for table/column lookups see `gameplay-schema.md`; for symptom-first fixes see `TROUBLESHOOTING.md` and `GOTCHAS.md`.

---

## The three paths you need

| Purpose | Path | Confidence |
|---|---|---|
| **User Mods dir** (where the game loads mods from) | `%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VII\Mods` | **[Confirmed in files]** — exists at `C:\Users\noahd\AppData\Local\Firaxis Games\Sid Meier's Civilization VII\Mods`, currently holding `civ-simp-gold-gifting\` |
| **Game install** (source-of-truth files to grep) | `C:\Program Files (x86)\Steam\steamapps\common\Sid Meier's Civilization VII` | **[Confirmed in files]** — contains `Base\` and `DLC\`; base data lives under `Base\modules\` (`base-standard`, `core`, `age-antiquity`, `age-exploration`, `age-modern`) |
| **Gameplay schema** (DDL for the gameplay DB) | `…\Base\Assets\schema\gameplay\01_GameplaySchema.sql` | **[Confirmed in files]** — 325,620 bytes |

### Why the Mods dir is `%LOCALAPPDATA%` and not under Steam

The Mods directory is derived **purely from `%LOCALAPPDATA%`** — it has nothing to do with where Steam or the game is installed. On this machine `%LOCALAPPDATA%` is `C:\Users\noahd\AppData\Local`, confirmed straight from the registry **[Confirmed in files]**:

```
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders
  Local AppData = C:\Users\noahd\AppData\Local
```

**`AppData\Local` is never OneDrive-redirected.** OneDrive's "Known Folder Move" only relocates Desktop, Documents, and Pictures (the `Personal`-class shell folders), never `Local AppData`. On this box the registry shows `Personal = C:\Users\noahd\Documents` (also local), but even when Documents *is* redirected, `Local AppData` stays on the local disk. So you can hardcode the Mods path from `%LOCALAPPDATA%` and trust it. **[Confirmed in files]** (registry value is the literal local path) / **[Confirmed]** (OneDrive KFM scope).

The example installer derives the path exactly this way — no Steam lookup, no user prompt (`civsimp_gg.ps1:36-37`):

```powershell
$CivAppData = Join-Path $env:LOCALAPPDATA "Firaxis Games\Sid Meier's Civilization VII"
$ModsDir    = Join-Path $CivAppData "Mods"
```

### Finding the game install if it's not on C:

Steam can spread games across multiple library drives. The authoritative list is `…\Steam\steamapps\libraryfolders.vdf`. Civ VII is **Steam appid `1295660`** — confirmed two ways:

- `…\Steam\steamapps\appmanifest_1295660.acf` exists; its `AppState` block names `"Sid Meier's Civilization VII"` with `installdir = Sid Meier's Civilization VII`. **[Confirmed in files]**
- `libraryfolders.vdf:19` lists `"1295660"` under the `apps` block. **[Confirmed in files]**

On this machine there is exactly **one** library (`libraryfolders.vdf:5` → `path = C:\Program Files (x86)\Steam`), so the install is the path in the table above. On a machine with extra drives, read each library's `path` from `libraryfolders.vdf` and look for `steamapps\common\Sid Meier's Civilization VII`. The example installer does exactly this scan as a soft "is it installed?" check (`civsimp_gg.ps1:294-316`).

---

## The junction dev loop (no admin, no Developer Mode)

**Goal:** keep your repo wherever you want (e.g. `C:\Users\noahd\Desktop\claude_projects\civ-simp-gold-gifting`) and have the game load it live, so editing the repo *is* editing the installed mod.

**Mechanism:** a **directory junction** from `Mods\<modname>` → your repo.

```powershell
New-Item -ItemType Junction `
  -Path   "$env:LOCALAPPDATA\Firaxis Games\Sid Meier's Civilization VII\Mods\civ-simp-gold-gifting" `
  -Target "C:\Users\noahd\Desktop\claude_projects\civ-simp-gold-gifting"
```

### Why a junction, not a symlink

A junction needs **no admin and no Windows Developer Mode**. A directory *symlink* (`-ItemType SymbolicLink`) requires either elevation or `SeCreateSymbolicLinkPrivilege` (granted by Developer Mode). Junctions don't — they're an older NTFS reparse-point type with no such gate.

**[Confirmed in-environment]** — on this non-elevated session, `whoami /priv` does **not** list `SeCreateSymbolicLinkPrivilege` at all, yet a junction created here resolves and reads through live (no copy step). So edits to the repo are visible through the Mods path immediately — no build/copy/sync. (You still need a **new game** for the game to pick them up; see below.)

### Verifying / re-pointing a junction

```powershell
# Is the Mods entry a link or a real copy?
(Get-Item "$env:LOCALAPPDATA\Firaxis Games\Sid Meier's Civilization VII\Mods\civ-simp-gold-gifting").LinkType
#   -> "Junction"  = live link    |   $null = a static copy

# Remove a junction WITHOUT deleting your repo (deletes the link only):
[IO.Directory]::Delete("$env:LOCALAPPDATA\Firaxis Games\Sid Meier's Civilization VII\Mods\civ-simp-gold-gifting")
```

> ⚠️ **`Remove-Item -Recurse` on a junction can recurse into the target** and delete files in your repo. Drop just the link with `[IO.Directory]::Delete($linkPath)` (no recurse). The example installer branches on exactly this: it deletes the *link only* when the path is a reparse point, and reserves `Remove-Item -Recurse` for the real-copy case. **[Confirmed in files]** (`civsimp_gg.ps1:387-390`):
>
> ```powershell
> if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq [IO.FileAttributes]::ReparsePoint) {
>     [IO.Directory]::Delete($dest)        # junction/symlink: remove LINK only
> } else {
>     Remove-Item -LiteralPath $dest -Recurse -Force
> }
> ```

### Gotcha: a copy-based installer overwrites your junction

The example mod ships a copy-based installer (`civsimp_gg.ps1`) for non-technical players: it downloads the repo zip from GitHub, `Expand-Archive`s it, and `Copy-Item`s it into `Mods\<modname>`. Run over a path that is currently your dev **junction**, STEP V detects the reparse point, **deletes the link, and `Copy-Item`s a static copy in its place** — your live loop is gone until you recreate the junction. **[Confirmed in files]** (`civsimp_gg.ps1:385-394`).

It's "junction-safe" only in that it won't nuke your repo *through* the link (it deletes the link, not the target) — but it *does* replace the link with a copy. **After running any copy-based installer over your dev path, re-create the junction.**

> The current state of this machine is exactly this trap: `Mods\civ-simp-gold-gifting` is a **plain directory (a static copy), not a junction** — `(Get-Item …).LinkType` returns `$null` and the ReparsePoint attribute is not set. So before assuming live edits work, check `LinkType` (above). **[Confirmed in-environment]**

---

## Tooling

| Tool | Use | Status on this machine |
|---|---|---|
| `git` | version control for the repo | **[Confirmed]** `git version 2.45.2.windows.1` |
| `gh` (GitHub CLI) | repo/PR/release operations against GitHub | **[Confirmed]** — **not on PATH** (`gh` not found via Bash or PowerShell `Get-Command`). Install with `winget install GitHub.cli` if you need it; the distribution workflow assumes it. |
| `bash` (Git Bash / msys) | runs the schema-discovery script | **[Confirmed]** `GNU bash 5.2.26(1)` |
| Windows PowerShell | installer + junction commands | **[Confirmed]** 5.1.26100 (default on Win10/11) |

### Schema discovery (do this first on a new mod)

`tools/discover-schema.sh` greps the **installed base game** for the real endeavor / diplomatic-action / Gold / relationship / modifier names your mod needs. **No game launch** — it only reads the shipped `*.sql`, `*.xml`, and `*.modinfo` definition files (`discover-schema.sh:51`). It auto-detects the install from a candidate list (Windows Steam, macOS, Linux, Epic) or takes `CIV_DIR` (`discover-schema.sh:23-31`):

```bash
bash tools/discover-schema.sh
# or, if the install is somewhere unusual:
CIV_DIR="C:/Program Files (x86)/Steam/steamapps/common/Sid Meier's Civilization VII" \
  bash tools/discover-schema.sh
```

This is how the example mod reverse-engineered the 1.4.0 diplomacy schema instead of trusting outdated web docs. See `gameplay-schema.md` for what the schema actually contains.

> **Note:** the script's header still refers to an older `data/gift-gold-endeavor.sql` with `<< >>` tokens, but the mod that actually ships uses two XML files — `data/gift-gold-action.xml` (the `<Database>` action rows) and `data/gift-gold-effects.xml` (the `<GameEffects>` modifiers). The discovery *queries* are still valid; only that filename in the header comment is stale. **[Confirmed in files]**

### The distributable installer (optional, for end users)

The repo also carries a **ps2exe-based one-step installer** (`civsimp_gg.ps1` compiled to `civsimp_gg.exe`, with `civsimp_gg.ico`/preview PNG) so non-technical players can install without git: it locates/creates the Mods dir, downloads from GitHub, extracts, verifies, and drops a Desktop shortcut. The compiled `.exe` and the throwaway preview PNG are git-ignored (`.gitignore`) — distribute the exe via GitHub Releases. You **don't need any of this for development** (use the junction). None of it is part of the mod the game loads: the game reads only the `.modinfo` plus the `data/` and `text/` files it lists.

---

## The cross-cutting rule: new game after edits

**Database changes apply at database-build time, so a reload is not enough — start a NEW game.** Civ VII compiles the mod's `<Database>`/`<GameEffects>` XML into the gameplay DB when a game is built; an already-running game (or a save) has the old DB baked in. This is true whether you edit through a junction or reinstall a copy. **[Confirmed in files]** — stated verbatim in the repo README (`README.md:66`: "Database changes apply at **database build time**, so a reload is not enough — start a **new game**") and echoed in `TROUBLESHOOTING.md:19` ("the DB builds at new-game time, not on reload").

Practical loop:
1. Edit repo files (live through the junction).
2. Ensure the mod is **enabled** in the in-game Add-Ons / Mods menu (once).
3. **Start a new game** with at least one other major leader to see the change.

> The example mod loads its data and text under a single `scope="game"` `ActionGroup` via `<UpdateDatabase>` / `<UpdateText>` (`civ-simp-gold-gifting.modinfo`), so its changes only exist inside an active game — which is exactly why a fresh game build is required. **[Confirmed in files]**

---

## Gotchas (quick list)

- **Mods entry is a copy, not a link?** Check `(Get-Item …).LinkType`. If it's `$null`, your "live" edits aren't live — recreate the junction. (This machine is currently in that state.)
- **Ran the installer over your dev junction?** It replaced the link with a static copy. Recreate the junction.
- **Tried a symlink and got "access denied"?** Use a **junction** instead — no admin, no Developer Mode needed (`SeCreateSymbolicLinkPrivilege` isn't even granted here).
- **`Remove-Item -Recurse` on the Mods link** can delete *through* it into your repo. Use `[IO.Directory]::Delete($linkPath)` to remove only the link.
- **Edits not showing up in-game?** You almost certainly reloaded instead of starting a **new game** — DB changes build at game start.
- **`gh` "command not found"?** It's not installed on this box; `winget install GitHub.cli` (plain `git` is present).
- **Multiple Steam drives?** Don't assume `C:`. Read library `path`s from `steamapps\libraryfolders.vdf` and find appid `1295660`.