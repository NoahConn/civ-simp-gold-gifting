<#
.SYNOPSIS
    Civ Simp Gold Gifting - one-step setup for the Civ VII mod.
.DESCRIPTION
    A guided, retro-styled setup that locates (or creates) the Civ VII user Mods
    directory, downloads the mod from GitHub (no git required), installs it,
    verifies it, and prints in-game instructions.

    The FIRST run on a machine plays the full ceremony (banner, varied loading
    animations, narration). Every run after that is FAST (no pacing), tracked by a
    small marker file in the Civ VII AppData folder.

    Targets Windows PowerShell 5.1 (default on Windows 10/11), PowerShell 7 compatible.
    No admin rights, no git, no developer mode required.

    One-liner:
      [Net.ServicePointManager]::SecurityProtocol='Tls12'; iex (irm 'https://raw.githubusercontent.com/NoahConn/civ-simp-gold-gifting/main/civsimp_gg.ps1')

    Env vars: CIVMOD_INSTANT=1 forces the fast path even on a first run;
              CIVMOD_SHOW=1 replays the full ceremony even after the first run.
#>

# ============================================================================
#  CONFIGURATION
# ============================================================================
$ModName     = 'civ-simp-gold-gifting'                 # final folder name in Mods
$InnerPrefix = 'civ-simp-gold-gifting'                 # zip top folder starts with this
$ZipUrl      = 'https://github.com/NoahConn/civ-simp-gold-gifting/archive/refs/heads/main.zip'
$ModInfoName = 'civ-simp-gold-gifting.modinfo'         # must land at dest root

# 'Stop' is intentional: it promotes non-terminating errors to terminating ones
# so the single try/catch below can trap them and show a plain-English message.
$ErrorActionPreference = 'Stop'

# --- Paths (derived purely from %LOCALAPPDATA%; no Steam, no user input). -----
$CivAppData = Join-Path $env:LOCALAPPDATA "Firaxis Games\Sid Meier's Civilization VII"
$ModsDir    = Join-Path $CivAppData "Mods"
$MarkerPath = Join-Path $CivAppData ".civsimp_gg-installed"   # "I've run here before"

# --- First-run vs fast-path decision --------------------------------------
# First run = full ceremony. Later runs = instant. Env vars can override either way.
$firstRun = $true
try { if (Test-Path -LiteralPath $MarkerPath) { $firstRun = $false } } catch { }
$Instant = ($env:CIVMOD_INSTANT -eq '1') -or ((-not $firstRun) -and ($env:CIVMOD_SHOW -ne '1'))

# --- Pacing knobs (the "ceremony"). Ignored entirely when $Instant. ----------
$TypeSpeedMs = 20     # per-character typewriter delay
$StepAnimMs  = 1700   # how long each step's animation plays
$BeatMs      = 600    # the pause between beats
$RevealMs    = 200    # delay between banner lines as they appear
# Carriage-return redraw (the animations) only works cleanly in the real console.
$CanRedraw   = ($Host.Name -eq 'ConsoleHost')

# ============================================================================
#  RETRO PRESENTATION HELPERS  (ConsoleColor only; ASCII-safe; PS 5.1 friendly)
# ============================================================================

function Beat { param([int]$Ms = $BeatMs) if (-not $Instant) { Start-Sleep -Milliseconds $Ms } }

function Say { param([string]$Text, [ConsoleColor]$Color = 'Gray') Write-Host $Text -ForegroundColor $Color }

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

function Say-Step {
    param([string]$Numeral, [string]$Text)
    Write-Host ("   [ {0,-3}] " -f $Numeral) -ForegroundColor DarkYellow -NoNewline
    Write-Host $Text -ForegroundColor White
}

# Clear the current redraw line.
function Clear-Line { if ($CanRedraw) { Write-Host ("`r" + (' ' * 78) + "`r") -NoNewline } }

# --- ANIMATION 1: a bouncing scanner sweeping a track (survey / sort) ---------
function Anim-Scan {
    param([string]$Label, [int]$Ms = $StepAnimMs, [ConsoleColor]$Color = 'DarkYellow')
    if ($Instant) { return }
    $w = 16; $sw = [System.Diagnostics.Stopwatch]::StartNew(); $pos = 0; $dir = 1
    if ($CanRedraw) {
        while ($sw.ElapsedMilliseconds -lt $Ms) {
            $track = (' ' * $pos) + '<o>' + (' ' * ($w - $pos))
            Write-Host ("`r       {0} [{1}]" -f $Label, $track) -ForegroundColor $Color -NoNewline
            Start-Sleep -Milliseconds 75
            $pos += $dir; if ($pos -ge $w -or $pos -le 0) { $dir *= -1 }
        }
        Clear-Line
    } else {
        Write-Host ("       " + $Label) -ForegroundColor $Color -NoNewline
        while ($sw.ElapsedMilliseconds -lt $Ms) { Write-Host "." -NoNewline -ForegroundColor $Color; Start-Sleep -Milliseconds 200 }
        Write-Host ""
    }
}

# --- ANIMATION 2: a spinning gold coin (count / inspect) ---------------------
function Anim-Coin {
    param([string]$Label, [int]$Ms = $StepAnimMs, [ConsoleColor]$Color = 'Yellow')
    if ($Instant) { return }
    $frames = '( $ )', '( = )', '( - )', '( _ )', '( - )', '( = )'
    $sw = [System.Diagnostics.Stopwatch]::StartNew(); $i = 0
    if ($CanRedraw) {
        while ($sw.ElapsedMilliseconds -lt $Ms) {
            Write-Host ("`r       {0}  {1}" -f $frames[$i % $frames.Count], $Label) -ForegroundColor $Color -NoNewline
            Start-Sleep -Milliseconds 110
            $i++
        }
        Clear-Line
    } else {
        Write-Host ("       " + $Label) -ForegroundColor $Color -NoNewline
        while ($sw.ElapsedMilliseconds -lt $Ms) { Write-Host "." -NoNewline -ForegroundColor $Color; Start-Sleep -Milliseconds 200 }
        Write-Host ""
    }
}

# --- ANIMATION 3: a filling progress bar with a head and % (download/install) -
function Anim-Bar {
    param([string]$Label, [int]$Ms = $StepAnimMs, [ConsoleColor]$Color = 'DarkYellow')
    if ($Instant) { return }
    $w = 22; $sw = [System.Diagnostics.Stopwatch]::StartNew()
    if ($CanRedraw) {
        while ($sw.ElapsedMilliseconds -lt $Ms) {
            $p = [math]::Min(1.0, $sw.ElapsedMilliseconds / $Ms)
            $fill = [int]($p * $w)
            $bar = ('=' * $fill)
            if ($fill -lt $w) { $bar += '>'; $bar += (' ' * ($w - $fill - 1)) }
            Write-Host ("`r       {0} [{1}] {2,3}%" -f $Label, $bar, [int]($p * 100)) -ForegroundColor $Color -NoNewline
            Start-Sleep -Milliseconds 55
        }
        Write-Host ("`r       {0} [{1}] 100%" -f $Label, ('=' * $w)) -ForegroundColor Green -NoNewline
        Start-Sleep -Milliseconds 200
        Clear-Line
    } else {
        Write-Host ("       " + $Label) -ForegroundColor $Color -NoNewline
        while ($sw.ElapsedMilliseconds -lt $Ms) { Write-Host "=" -NoNewline -ForegroundColor $Color; Start-Sleep -Milliseconds 120 }
        Write-Host ""
    }
}

function Show-Banner {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor DarkYellow
    if (-not $Instant) { Start-Sleep -Milliseconds $RevealMs }
    Write-Host '       .------.' -ForegroundColor Yellow
    if (-not $Instant) { Start-Sleep -Milliseconds $RevealMs }
    Write-Host '      ( $$$$$$ )     CIV SIMP  -  GOLD GIFTING' -ForegroundColor Yellow
    if (-not $Instant) { Start-Sleep -Milliseconds $RevealMs }
    Write-Host "       '------'      a Civ VII mod  -  one-step setup" -ForegroundColor Yellow
    if (-not $Instant) { Start-Sleep -Milliseconds $RevealMs }
    Write-Host "  ==============================================================" -ForegroundColor DarkYellow
    Beat
    Type-Line "     Sit back, Consul. I shall see your gift delivered." Gray
    Write-Host ""
    Beat
}

# Pause at the very end so a double-clicked window does not vanish.
function Pause-AtEnd {
    Write-Host ""
    Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkGray
    try   { Read-Host "  Press ENTER to close this window" | Out-Null }
    catch { Start-Sleep -Seconds 8 }
}

# ============================================================================
#  DESKTOP-APP INSTALL  (compiled-exe only; fail-soft; idempotent)
# ----------------------------------------------------------------------------
#  On a successful install, AND only when running as the compiled ps2exe .exe
#  (not the iex/irm one-liner under powershell.exe/pwsh.exe), copy the running
#  exe to a stable per-user home and (re)create a Desktop shortcut with the
#  embedded gold-coin icon. Wrapped so ANY failure is swallowed and never
#  breaks the install.
# ============================================================================
function New-DesktopApp {
    # ----- 0) Determine the running image path -----------------------------
    $selfPath = $null
    try {
        $selfPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    } catch { return }            # can't tell who we are -> do nothing, silently
    if ([string]::IsNullOrWhiteSpace($selfPath) -or -not (Test-Path -LiteralPath $selfPath)) { return }

    # ----- 1) EXE-ONLY GUARD ----------------------------------------------
    # The host is itself a .exe, so do NOT key off the extension. Reject the
    # known PowerShell host names; anything else is our compiled exe.
    $leaf = [System.IO.Path]::GetFileName($selfPath)
    $hostNames = @('powershell.exe','pwsh.exe','powershell_ise.exe')
    if ($hostNames -contains $leaf.ToLowerInvariant()) { return }   # one-liner path: skip entirely
    if ([System.IO.Path]::GetExtension($selfPath).ToLowerInvariant() -ne '.exe') { return }

    try {
        # ----- 2) Stable per-user home + filename --------------------------
        $appName   = 'Civ Simp Gold Gifting'
        $homeDir   = Join-Path $env:LOCALAPPDATA 'CivSimpGoldGifting'
        $stableExe = Join-Path $homeDir ($appName + '.exe')

        # ----- 3) Copy running exe -> stable home (idempotent; skip self) --
        $runningFull = [System.IO.Path]::GetFullPath($selfPath)
        $stableFull  = [System.IO.Path]::GetFullPath($stableExe)
        $isSelf = [string]::Equals($runningFull, $stableFull, [System.StringComparison]::OrdinalIgnoreCase)

        if (-not $isSelf) {
            try {
                New-Item -ItemType Directory -Path $homeDir -Force -ErrorAction Stop | Out-Null
                Copy-Item -LiteralPath $selfPath -Destination $stableExe -Force -ErrorAction Stop
            } catch {
                # Couldn't stage the stable copy (locked / perms): fall back to
                # pointing the shortcut at the exe we ARE running.
                $stableExe = $selfPath
            }
        }
        if (-not (Test-Path -LiteralPath $stableExe)) { $stableExe = $selfPath }

        # ----- 4) Desktop path (OneDrive-redirect safe) --------------------
        $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
        if ([string]::IsNullOrWhiteSpace($desktop)) {
            $desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
        }
        if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop)) { return }
        $lnkPath = Join-Path $desktop ($appName + '.lnk')

        # ----- 5) Create / refresh the shortcut via WScript.Shell ----------
        $wsh = $null
        try {
            $wsh = New-Object -ComObject WScript.Shell
            $sc  = $wsh.CreateShortcut($lnkPath)
            $sc.TargetPath       = $stableExe
            $sc.WorkingDirectory = [System.IO.Path]::GetDirectoryName($stableExe)
            $sc.IconLocation     = "$stableExe,0"
            $sc.Description       = 'Civ Simp Gold Gifting - run again to update the mod'
            $sc.Save()
        } finally {
            if ($wsh) { try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) } catch { } }
        }

        # ----- 6) Friendly note --------------------------------------------
        Write-Host ""
        Say "  I also placed a shortcut on your Desktop:" White
        Say ("     " + $appName + "   (gold-coin icon)") Yellow
        Say "  Double-click it any time to re-run this setup and pull the latest mod." Gray
    }
    catch {
        try { Say "  (Note: couldn't add the Desktop shortcut this time - the mod is still installed fine.)" DarkGray } catch { }
    }
}

# ============================================================================
#  MAIN
# ============================================================================
$installOK = $false
$work = $null
try {
    Show-Banner

    # --- Force TLS 1.2 BEFORE any web call (stock Win10/PS 5.1 may default low). -
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor 3072
    }

    # ------------------------------------------------------------------------
    #  STEP I - Locate / create the Civ VII user Mods directory.
    # ------------------------------------------------------------------------
    Say-Step 'I' "Finding your Civilization VII Mods folder..."
    Anim-Scan "Surveying the realm for the royal archives..."

    try {
        New-Item -ItemType Directory -Path $ModsDir -Force | Out-Null
    } catch {
        throw "PERMISSION: Could not create the Mods folder at:`n      $ModsDir`n      $($_.Exception.Message)"
    }
    Say ("       Mods folder ready:`n       " + $ModsDir) Green
    Beat

    # ------------------------------------------------------------------------
    #  STEP II - Soft "is Civ VII installed?" check. INFORMATIONAL ONLY.
    # ------------------------------------------------------------------------
    Say-Step 'II' "Checking that Civilization VII looks installed..."
    Anim-Coin "Consulting the royal census..."

    $appDataPresent = Test-Path -LiteralPath $CivAppData

    $manifestFound = $false
    if (-not $appDataPresent) {
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
    #  STEP III - Download the mod's main-branch zip from GitHub (no git).
    # ------------------------------------------------------------------------
    Say-Step 'III' "Downloading the mod from GitHub..."
    Anim-Bar "Couriers ride for the Great Library of GitHub..."

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
    #  STEP IV - Extract. Archive has ONE top folder "civ-simp-gold-gifting-main".
    # ------------------------------------------------------------------------
    Say-Step 'IV' "Unpacking the mod files..."
    Anim-Scan "Unloading the caravan and sorting the goods..."

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
    #  STEP V - Install: replace any prior copy IDEMPOTENTLY (junction-safe).
    # ------------------------------------------------------------------------
    Say-Step 'V' "Installing into your Mods folder..."
    Anim-Bar "Laying the golden mosaic into place..."

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
    Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force

    # ------------------------------------------------------------------------
    #  STEP VI - Verify the .modinfo landed at the destination root.
    # ------------------------------------------------------------------------
    Say-Step 'VI' "Verifying the installation..."
    Anim-Coin "Pressing the imperial seal..."

    if (-not (Test-Path -LiteralPath (Join-Path $dest $ModInfoName))) {
        throw "Verification failed: '$ModInfoName' is missing after install."
    }

    $installOK = $true
    Say ("       Seal verified. Installed to:`n       " + $dest) Green

    # Record that the ceremony has played here, so future runs go fast.
    try { Set-Content -LiteralPath $MarkerPath -Value ((Get-Date).ToString('o')) -ErrorAction SilentlyContinue } catch { }
    Beat
}
catch {
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
    if ($work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

# ============================================================================
#  SUCCESS MESSAGE + WHAT-TO-DO-IN-GAME
# ============================================================================
if ($installOK) {
    Beat
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor DarkYellow
    if (-not $Instant) { Start-Sleep -Milliseconds 350 }
    Write-Host "        *   *   *    H U Z Z A H !    *   *   *" -ForegroundColor Green
    if (-not $Instant) { Start-Sleep -Milliseconds 350 }
    Write-Host "        Civ Simp Gold Gifting is installed, Consul." -ForegroundColor Green
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
    Write-Host "     an update later, just run this setup again." -ForegroundColor Yellow
    Write-Host ""
    Type-Line "  May your treasury be generous and your rivals grateful." Green

    # Make it a real app on the Desktop (compiled-exe only; fail-soft).
    New-DesktopApp
}

Pause-AtEnd
