<#
.SYNOPSIS
    Civilization VII - "Civ Simp Gold Gifting" mod installer.
.DESCRIPTION
    One-step installer for a non-technical player. Locates (or creates) the Civ VII
    user Mods directory, downloads the mod from GitHub (no git required), installs
    it, verifies it, and prints in-game instructions. Friendly, guided, retro-styled,
    and deliberately paced so it feels like an event rather than a flicker.

    Targets Windows PowerShell 5.1 (default on Windows 10/11) and is PowerShell 7
    compatible. No admin rights, no git, no developer mode required.

    Recommended one-liner (paste into PowerShell):
      [Net.ServicePointManager]::SecurityProtocol='Tls12'; iex (irm 'https://raw.githubusercontent.com/NoahConn/civ-simp-gold-gifting/main/install.ps1')

    Tip: set the environment variable CIVMOD_INSTANT=1 to skip all the pacing and
    install instantly (handy for the mod author re-testing).
#>

# ============================================================================
#  CONFIGURATION
# ============================================================================
$ModName     = 'civ-simp-gold-gifting'                 # final folder name in Mods
$InnerPrefix = 'civ-simp-gold-gifting'                 # zip top folder starts with this
$ZipUrl      = 'https://github.com/NoahConn/civ-simp-gold-gifting/archive/refs/heads/main.zip'
$ModInfoName = 'civ-simp-gold-gifting.modinfo'         # must land at dest root

# 'Stop' is intentional: it promotes non-terminating errors (a failed download,
# copy, etc.) to terminating ones so the single try/catch below can trap them and
# show a plain-English message instead of a scary red stack trace.
$ErrorActionPreference = 'Stop'

# --- Pacing knobs (the "experience"). CIVMOD_INSTANT=1 disables all of it. ----
$Instant     = ($env:CIVMOD_INSTANT -eq '1')
$TypeSpeedMs = 16     # per-character typewriter delay
$StepSpinMs  = 1100   # how long each step's spinner dances
$BeatMs      = 450    # the little pause between beats
$RevealMs    = 140    # delay between banner lines as they appear
# Carriage-return redraw (the spinner) only works cleanly in the real console.
$CanRedraw   = ($Host.Name -eq 'ConsoleHost')

# ============================================================================
#  RETRO CIV-STYLE PRESENTATION HELPERS
#  Uses -ForegroundColor (ConsoleColor) only, which renders reliably on stock
#  Windows PowerShell 5.1 consoles - no ANSI/256-color dependency.
# ============================================================================

# A beat of silence for dramatic effect.
function Beat { param([int]$Ms = $BeatMs) if (-not $Instant) { Start-Sleep -Milliseconds $Ms } }

# Plain colored line (instant).
function Say {
    param([string]$Text, [ConsoleColor]$Color = 'Gray')
    Write-Host $Text -ForegroundColor $Color
}

# Typewriter line - reveals one character at a time, like a herald's proclamation.
function Type-Line {
    param([string]$Text, [ConsoleColor]$Color = 'Gray')
    if ($Instant) { Write-Host $Text -ForegroundColor $Color; return }
    foreach ($ch in $Text.ToCharArray()) {
        Write-Host -NoNewline $ch -ForegroundColor $Color
        Start-Sleep -Milliseconds $TypeSpeedMs
    }
    Write-Host ""
}

# Roman-numeral step bullet, because of course.
function Say-Step {
    param([string]$Numeral, [string]$Text)
    Write-Host ("   [ {0,-3}] " -f $Numeral) -ForegroundColor DarkYellow -NoNewline
    Write-Host $Text -ForegroundColor White
}

# A spinner that dances for a fixed (cosmetic) duration under a flavor label,
# then clears itself. Purely for the experience - the real work runs right after.
function Spin {
    param([string]$Label, [int]$Ms = $StepSpinMs, [ConsoleColor]$Color = 'DarkYellow')
    if ($Instant) { return }
    $frames = '|','/','-','\'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $i = 0
    if ($CanRedraw) {
        while ($sw.ElapsedMilliseconds -lt $Ms) {
            Write-Host ("`r       ( {0} ) {1}" -f $frames[$i % 4], $Label) -ForegroundColor $Color -NoNewline
            Start-Sleep -Milliseconds 95
            $i++
        }
        # Wipe the spinner line so the real result prints cleanly beneath it.
        Write-Host ("`r" + (' ' * 74) + "`r") -NoNewline
    } else {
        Write-Host ("       " + $Label) -ForegroundColor $Color -NoNewline
        while ($sw.ElapsedMilliseconds -lt $Ms) { Write-Host "." -ForegroundColor $Color -NoNewline; Start-Sleep -Milliseconds 220 }
        Write-Host ""
    }
}

function Show-Banner {
    # Revealed line by line for a little drama.
    $lines = @(
        @("  ==============================================================", 'DarkYellow'),
        @("       .-------.      C I V I L I Z A T I O N   V I I", 'Yellow'),
        @("      (  `$ `$ `$  )", 'Yellow'),
        @("       '-------'    G O L D   G I F T I N G   -   M O D   S E T U P", 'Yellow'),
        @("  ==============================================================", 'DarkYellow')
    )
    Write-Host ""
    foreach ($l in $lines) {
        Write-Host $l[0] -ForegroundColor $l[1]
        if (-not $Instant) { Start-Sleep -Milliseconds $RevealMs }
    }
    Beat
    Type-Line "     Sit back, Consul. I shall handle the installation for you." Gray
    Write-Host ""
    Beat
}

# Always pause at the very end so a double-clicked window does not vanish before
# the result can be read. Safe under a non-interactive host (falls back to wait).
function Pause-AtEnd {
    Write-Host ""
    Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkGray
    try   { Read-Host "  Press ENTER to close this window" | Out-Null }
    catch { Start-Sleep -Seconds 8 }
}

# ============================================================================
#  MAIN
# ============================================================================
$installOK = $false
$work = $null
try {
    Show-Banner

    # --- Force TLS 1.2 BEFORE any web call. Stock Windows 10 / PS 5.1 can ------
    # --- otherwise default to TLS 1.0 and fail GitHub's TLS handshake. -bor ----
    # --- keeps TLS 1.3 where the platform already negotiates it. --------------
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        # Some old frameworks don't expose Tls12 by name; 3072 is its numeric value.
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor 3072
    }

    # ------------------------------------------------------------------------
    #  STEP I - Locate / create the Civ VII user Mods directory.
    #  Path is 100% derived from $env:LOCALAPPDATA, independent of where Steam
    #  or Civ VII is installed, and immune to OneDrive (AppData\Local is never
    #  redirected). No user input required - he never has to find Steam.
    # ------------------------------------------------------------------------
    Say-Step 'I' "Finding your Civilization VII Mods folder..."
    Spin "Surveying the empire for the royal archives..."

    $CivAppData = Join-Path $env:LOCALAPPDATA "Firaxis Games\Sid Meier's Civilization VII"
    $ModsDir    = Join-Path $CivAppData "Mods"

    try {
        # -Force builds the full parent chain and is a SAFE no-op if it already
        # exists (returns the existing dir; does NOT error, does NOT wipe it).
        New-Item -ItemType Directory -Path $ModsDir -Force | Out-Null
    } catch {
        throw "PERMISSION: Could not create the Mods folder at:`n      $ModsDir`n      $($_.Exception.Message)"
    }
    Say ("       Mods folder ready:`n       " + $ModsDir) Green
    Beat

    # ------------------------------------------------------------------------
    #  STEP II - Soft "is Civ VII installed?" check. INFORMATIONAL ONLY.
    #  Never blocks the install; the files land regardless.
    # ------------------------------------------------------------------------
    Say-Step 'II' "Checking that Civilization VII looks installed..."
    Spin "Consulting the royal census..."

    $appDataPresent = Test-Path -LiteralPath $CivAppData

    $manifestFound = $false
    if (-not $appDataPresent) {
        # Only bother with the Steam fallback if the AppData signal is absent.
        $steamPath = $null
        foreach ($k in 'HKCU:\SOFTWARE\Valve\Steam',
                       'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
                       'HKLM:\SOFTWARE\Valve\Steam') {
            try {
                $p = Get-ItemProperty -Path $k -ErrorAction Stop
                if ($p.SteamPath)   { $steamPath = $p.SteamPath;   break }
                if ($p.InstallPath) { $steamPath = $p.InstallPath; break }
            } catch { }
        }
        if ($steamPath) {
            $libs = New-Object System.Collections.Generic.List[string]
            $libs.Add($steamPath)
            $vdf = Join-Path $steamPath "steamapps\libraryfolders.vdf"
            if (Test-Path -LiteralPath $vdf) {
                try {
                    Select-String -LiteralPath $vdf -Pattern '"path"\s+"([^"]+)"' -AllMatches |
                        ForEach-Object { $_.Matches } |
                        ForEach-Object { $libs.Add(($_.Groups[1].Value -replace '\\\\','\')) }
                } catch { }
            }
            foreach ($lib in ($libs | Sort-Object -Unique)) {
                $mani = Join-Path $lib "steamapps\appmanifest_1295660.acf"   # Civ VII appid
                if (Test-Path -LiteralPath $mani) { $manifestFound = $true; break }
            }
        }
    }

    if ($appDataPresent) {
        Say "       Civilization VII detected. Good to go." Green
    } elseif ($manifestFound) {
        Say "       Civ VII is installed but may not have been launched yet." Yellow
        Say "       Start the game once so it creates its mod folders, then re-run me." Yellow
    } else {
        Say "       Heads up: I couldn't detect Civilization VII on this PC." Yellow
        Say "       I'll still install the mod in the correct folder, but make sure" Yellow
        Say "       Civ VII is installed (via Steam) and launched at least once." Yellow
    }
    Beat

    # ------------------------------------------------------------------------
    #  STEP III - Download the mod's main-branch zip from GitHub (no git needed).
    #  The github.com URL 302-redirects to codeload; Invoke-WebRequest follows it
    #  automatically. Repo is public, so no auth/token is required.
    # ------------------------------------------------------------------------
    Say-Step 'III' "Downloading the mod from GitHub..."
    Spin "Dispatching couriers to the Great Library of GitHub..."

    $work = Join-Path $env:TEMP ('civmod_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $zip = Join-Path $work 'mod.zip'
    $ex  = Join-Path $work 'extract'

    $oldPref = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # PS 5.1 progress bar can slow IWR 10-50x
    try {
        Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing -ErrorAction Stop
    } finally {
        $ProgressPreference = $oldPref
    }
    Say "       The couriers return, scrolls in hand. Download complete." Green
    Beat

    # ------------------------------------------------------------------------
    #  STEP IV - Extract. The archive contains ONE top folder named
    #  "civ-simp-gold-gifting-main" (repo + branch). Match by prefix so a future
    #  default-branch rename doesn't break us.
    # ------------------------------------------------------------------------
    Say-Step 'IV' "Unpacking the mod files..."
    Spin "Unloading the caravan..."

    Expand-Archive -Path $zip -DestinationPath $ex -Force

    $src = $null
    $cand = Get-ChildItem -LiteralPath $ex -Directory |
            Where-Object { $_.Name -like ($InnerPrefix + '*') } |
            Select-Object -First 1
    if ($cand) {
        $src = $cand.FullName
    } else {
        $only = Get-ChildItem -LiteralPath $ex -Directory | Select-Object -First 1
        if ($only) { $src = $only.FullName }
    }
    if (-not $src -or -not (Test-Path -LiteralPath (Join-Path $src $ModInfoName))) {
        throw "The downloaded file did not contain '$ModInfoName' where expected. The download may be corrupt - please try again."
    }
    Say "       Crates opened. The goods are genuine." Green
    Beat

    # ------------------------------------------------------------------------
    #  STEP V - Install: replace any prior copy IDEMPOTENTLY, then copy in.
    #  Guard against a junction/symlink: Remove-Item -Recurse THROUGH a reparse
    #  point can delete the LINK TARGET's real files. So when the existing entry
    #  is a link, delete the LINK ONLY.
    # ------------------------------------------------------------------------
    Say-Step 'V' "Installing into your Mods folder..."
    Spin "Laying the golden mosaic into place..."

    $dest = Join-Path $ModsDir $ModName
    if (Test-Path -LiteralPath $dest) {
        $item = Get-Item -LiteralPath $dest -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq [IO.FileAttributes]::ReparsePoint) {
            [IO.Directory]::Delete($dest)            # junction/symlink: remove LINK only
        } else {
            Remove-Item -LiteralPath $dest -Recurse -Force
        }
        Say "       Cleared the old tapestry from the wall." DarkGray
    }
    # dest no longer exists, so -Recurse copies the CONTENTS of $src into a fresh
    # $dest (modinfo lands at dest root, no nested -main folder).
    Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force

    # ------------------------------------------------------------------------
    #  STEP VI - Verify the .modinfo landed at the destination root.
    # ------------------------------------------------------------------------
    Say-Step 'VI' "Verifying the installation..."
    Spin "Inspecting the imperial seal..."

    if (-not (Test-Path -LiteralPath (Join-Path $dest $ModInfoName))) {
        throw "Verification failed: '$ModInfoName' is missing after install."
    }

    $installOK = $true
    Say ("       Seal verified. Installed to:`n       " + $dest) Green
    Beat
}
catch {
    # ----- Plain-English error routing for a non-technical user -----
    $msg = $_.Exception.Message
    $resp = $null
    try { $resp = $_.Exception.Response } catch { }

    Write-Host ""
    Write-Host "  XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" -ForegroundColor Red
    Write-Host "   THE SENATE REPORTS A PROBLEM - the mod was NOT installed." -ForegroundColor Red
    Write-Host "  XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" -ForegroundColor Red
    Write-Host ""

    if ($resp -and ([int]$resp.StatusCode -eq 404)) {
        Say "  The mod download link returned 'not found' (404)." Yellow
        Say "  This usually means the mod's GitHub page was set to PRIVATE, renamed," Yellow
        Say "  or moved. Ask Noah to confirm the repository is PUBLIC, then try again." Yellow
    }
    elseif ($msg -match 'PERMISSION:') {
        Say "  Windows would not let me write to your Mods folder." Yellow
        Say "  Close Civilization VII if it is open, then run this again." Yellow
        Say ("  Details: " + $msg) DarkGray
    }
    elseif ($msg -match 'SSL|TLS|secure channel') {
        Say "  Couldn't make a secure connection to GitHub." Yellow
        Say "  Your Windows may be missing updates. Run Windows Update, then try again." Yellow
    }
    elseif ($msg -match 'remote name|could not be resolved|connect|timed out|connection|network|Unable to connect|resolve') {
        Say "  I couldn't reach GitHub - this looks like an internet problem." Yellow
        Say "  Check that you're online (open a website in your browser), then try again." Yellow
    }
    else {
        Say ("  Details: " + $msg) Yellow
        Say "  Please try again. If it keeps failing, send this message to Noah." Yellow
    }
}
finally {
    # Always clean up scratch space; ignore failures.
    if ($work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

# ============================================================================
#  SUCCESS MESSAGE + WHAT-TO-DO-IN-GAME (only when the install actually worked)
# ============================================================================
if ($installOK) {
    Beat
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor DarkYellow
    if (-not $Instant) { Start-Sleep -Milliseconds 250 }
    Write-Host "        *   *   *    H U Z Z A H !    *   *   *" -ForegroundColor Green
    if (-not $Instant) { Start-Sleep -Milliseconds 250 }
    Write-Host "             The mod is installed, Consul." -ForegroundColor Green
    Write-Host "  ==============================================================" -ForegroundColor DarkYellow
    Write-Host ""
    Beat
    Write-Host "  NEXT STEPS - do these inside the game:" -ForegroundColor White
    Write-Host ""
    Write-Host "     1. Start Civilization VII." -ForegroundColor Gray
    Write-Host "     2. From the Main Menu, open  Add-Ons  (the Mods menu)." -ForegroundColor Gray
    Write-Host "     3. Find  'civ-simp-gold-gifting'  and turn it ON." -ForegroundColor Gray
    Write-Host "     4. Back out / restart if the game asks you to." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  IMPORTANT FOR MULTIPLAYER:" -ForegroundColor Yellow
    Write-Host "     BOTH players must have the SAME mod AND the SAME version" -ForegroundColor Yellow
    Write-Host "     enabled, or the match won't start together. If Noah sends" -ForegroundColor Yellow
    Write-Host "     an update later, just run this installer again." -ForegroundColor Yellow
    Write-Host ""
    Type-Line "  May your treasury be generous and your rivals grateful." Green
}

Pause-AtEnd
