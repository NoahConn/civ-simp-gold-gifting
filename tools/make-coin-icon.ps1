<#
  make-coin-icon.ps1 - generates an 8-bit gold-coin icon for the setup exe.

  Draws a 16x16 pixel-art coin (rim + shaded gold face + white shine + a blocky
  "$"), scales it up with nearest-neighbor (so it stays crisp/blocky), and packs
  several sizes into a multi-resolution .ico. Also writes a 256px preview PNG.

  Output (next to the repo root by default):
    civsimp_gg.ico          - the icon for ps2exe -iconFile
    civsimp_gg_preview.png   - a preview to eyeball

  Usage:  powershell -ExecutionPolicy Bypass -File tools\make-coin-icon.ps1
#>
param(
    [string]$IcoPath     = (Join-Path $PSScriptRoot '..\civsimp_gg.ico'),
    [string]$PreviewPath = (Join-Path $PSScriptRoot '..\civsimp_gg_preview.png')
)
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$N = 16   # base grid: 16x16 pixels of chunky 8-bit goodness

# --- palette ---------------------------------------------------------------
$transparent = [System.Drawing.Color]::FromArgb(0,0,0,0)
$rim   = [System.Drawing.Color]::FromArgb(255,110,79,0)     # dark bronze edge
$gold  = [System.Drawing.Color]::FromArgb(255,242,183,5)    # coin gold
$hi    = [System.Drawing.Color]::FromArgb(255,255,226,122)  # upper-left highlight
$sh    = [System.Drawing.Color]::FromArgb(255,200,134,10)   # lower-right shadow
$sign  = [System.Drawing.Color]::FromArgb(255,90,62,0)      # the "$"
$shine = [System.Drawing.Color]::FromArgb(255,255,255,255)  # sparkle

# --- base 16x16 coin -------------------------------------------------------
$base = New-Object System.Drawing.Bitmap($N,$N,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$cx = 7.5; $cy = 7.5; $R = 8.0
for ($y=0; $y -lt $N; $y++) {
    for ($x=0; $x -lt $N; $x++) {
        $dx = $x - $cx; $dy = $y - $cy
        $d = [math]::Sqrt($dx*$dx + $dy*$dy)
        $col = $transparent
        if ($d -le $R) {
            if ($d -gt ($R - 1.5)) { $col = $rim }
            else {
                $col = $gold
                if (($dx + $dy) -lt -2.5)    { $col = $hi }
                elseif (($dx + $dy) -gt 3.0) { $col = $sh }
            }
        }
        $base.SetPixel($x, $y, $col)
    }
}

# white shine sparkle (upper-left of the face)
foreach ($pt in @(@(4,4),@(5,4),@(4,5))) { $base.SetPixel($pt[0], $pt[1], $shine) }

# a blocky "$" (5x7), only painted where there's coin underneath
$dollar = @('..#..', '.####', '#.#..', '.###.', '..#.#', '####.', '..#..')
$dx0 = 6; $dy0 = 5
for ($gy=0; $gy -lt $dollar.Count; $gy++) {
    $rowStr = $dollar[$gy]
    for ($gx=0; $gx -lt $rowStr.Length; $gx++) {
        if ($rowStr[$gx] -eq '#') {
            $px = $dx0 + $gx; $py = $dy0 + $gy
            if ($px -ge 0 -and $px -lt $N -and $py -ge 0 -and $py -lt $N) {
                if ($base.GetPixel($px,$py).A -ne 0) { $base.SetPixel($px, $py, $sign) }
            }
        }
    }
}

# --- render each size (nearest-neighbor = stays pixel-art) -> PNG bytes -----
function New-ScaledPng {
    param([System.Drawing.Bitmap]$Src, [int]$Size)
    $b = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.DrawImage($Src, 0, 0, $Size, $Size)
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $b.Dispose()
    return ,$ms.ToArray()
}

$sizes = 16,32,48,64,128,256
$entries = @()
foreach ($sz in $sizes) { $entries += [pscustomobject]@{ Size = $sz; Bytes = (New-ScaledPng -Src $base -Size $sz) } }

# --- write the multi-resolution .ico (each image stored as PNG) ------------
$fs = New-Object System.IO.FileStream($IcoPath, [System.IO.FileMode]::Create)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$entries.Count)   # ICONDIR
$offset = 6 + 16 * $entries.Count
foreach ($e in $entries) {
    $dim = if ($e.Size -ge 256) { 0 } else { $e.Size }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim)      # width, height
    $bw.Write([byte]0);    $bw.Write([byte]0)         # colorCount, reserved
    $bw.Write([uint16]1);  $bw.Write([uint16]32)      # planes, bitCount
    $bw.Write([uint32]$e.Bytes.Length)                # bytesInRes
    $bw.Write([uint32]$offset)                         # imageOffset
    $offset += $e.Bytes.Length
}
foreach ($e in $entries) { $bw.Write($e.Bytes) }
$bw.Flush(); $bw.Close(); $fs.Close()

# --- preview png (256) -----------------------------------------------------
[System.IO.File]::WriteAllBytes($PreviewPath, ($entries | Where-Object { $_.Size -eq 256 }).Bytes)
$base.Dispose()

"Wrote $IcoPath ($([math]::Round((Get-Item $IcoPath).Length/1KB,1)) KB) and $PreviewPath"
