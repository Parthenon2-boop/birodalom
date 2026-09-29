# Áttekintő kép a teljes egységkészletről: korszakonként egy sor, minden
# egységből a délnek néző pihenő, a délkeletre lépő, a támadó és a halott kocka.
#   katalogus.ps1 -Units <assets\art3d\units> -Kimenet out.png [-Nagyitas 1.5]
param([string]$Units, [string]$Kimenet, [double]$Nagyitas = 1.5, [string]$Szin = "c8322a")
Add-Type -ReferencedAssemblies System.Drawing -Path (Join-Path $PSScriptRoot "kepmuvelet.cs")
$man = Get-Content (Join-Path $Units "manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$roles = "worker", "melee", "spear", "ranged", "cav", "hero", "priest", "spy", "medic", "siege", "ram",
         "fisher", "transport", "warship", "galleon", "fighter", "bomber"
$team = [System.Drawing.ColorTranslator]::FromHtml("#" + $Szin)
$acc = [System.Drawing.ColorTranslator]::FromHtml("#e8c860")
$cache = @{}
function Lap($k) {
  if (-not $cache.ContainsKey($k)) {
    $c = [Kep]::Load((Join-Path $Units "$k.png")); $m = [Kep]::Load((Join-Path $Units "$($k)_m.png"))
    $cache[$k] = [Kep]::Tint($c, $m, $team, $acc)
  }
  return $cache[$k]
}
$cell = 0; $rowh = @(0, 0, 0, 0)
foreach ($p in $man.PSObject.Properties) { $cell = [Math]::Max($cell, [int]$p.Value.cw) }
$W = 40; $H = 30
$rows = @()
for ($a = 0; $a -lt 4; $a++) {
  $items = @()
  foreach ($r in $roles) {
    $k = "$($r)_$a"; if (-not $man.$k) { continue }
    $items += $k
  }
  $rows += , $items
}
$lap_w = 0; $lap_h = 0
foreach ($items in $rows) {
  $w = 20; $h = 0
  foreach ($k in $items) { $m = $man.$k; $w += 4 * [int]($m.cw * $Nagyitas / 2) + 16; $h = [Math]::Max($h, [int]($m.ch * $Nagyitas / 2)) }
  $lap_w = [Math]::Max($lap_w, $w); $lap_h += $h + 40
}
$bg = [Kep]::Grass($lap_w + 20, $lap_h + 40, 5); $g = [Kep]::G($bg)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$y = 30
for ($a = 0; $a -lt 4; $a++) {
  [Kep]::Text($g, "korszak $a", 10, $y - 24, 16, [System.Drawing.Color]::White)
  $x = 20; $h = 0
  foreach ($k in $rows[$a]) {
    $m = $man.$k; $b = Lap $k; $cw = [int]$m.cw; $ch = [int]$m.ch
    $c0 = [int]$m.anim.idle[0]; $c1 = [int]$m.anim.walk[0] + 2; $c2 = [int]$m.anim.attack[0] + 1
    $c3 = [int]$m.anim.death[0] + [int]$m.anim.death[1] - 1
    $fr = @(@($c0, 2), @($c1, 1), @($c2, 1), @($c3, 3))
    foreach ($f in $fr) {
      $src = New-Object System.Drawing.Rectangle ($f[0] * $cw), ($f[1] * $ch), $cw, $ch
      $dst = New-Object System.Drawing.RectangleF $x, $y, ($cw * $Nagyitas / 2), ($ch * $Nagyitas / 2)
      $g.DrawImage($b, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
      $x += [int]($cw * $Nagyitas / 2)
    }
    [Kep]::Text($g, $k, $x - 4 * [int]($cw * $Nagyitas / 2), $y + [int]($ch * $Nagyitas / 2) - 2, 11, [System.Drawing.Color]::White)
    $x += 16; $h = [Math]::Max($h, [int]($ch * $Nagyitas / 2))
  }
  $y += $h + 40
}
$bg.Save($Kimenet, [System.Drawing.Imaging.ImageFormat]::Png)
