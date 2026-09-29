# Kontaktlap és játékbeli makett a Blender-mintákból.
#   kontaktlap.ps1 -Minta <blender_minta mappa>
# Bemenet: <Minta>\epulet\*.png, <Minta>\egyseg\*.png (+ _m.png maszkok),
#          <Minta>\jatek_hatter.png (1x zoom), <Minta>\jatek_hatter_z2.png (2x zoom)
# Kimenet: <Minta>\kontaktlap.png, <Minta>\makett_1x.png, <Minta>\makett_2x.png
param([string]$Minta)
Add-Type -ReferencedAssemblies System.Drawing -Path (Join-Path $PSScriptRoot "kepmuvelet.cs")
$E = Join-Path $Minta "epulet"; $U = Join-Path $Minta "egyseg"
function C($h) { [System.Drawing.ColorTranslator]::FromHtml("#" + $h) }
$ACC = C "e8c860"
$NEMZET = @(@("magyar", "c8322a"), @("francia", "2e56b8"), @("osztrák", "e0b020"), @("orosz", "3a8a3a"), @("lengyel", "8a3ab0"))
$cache = @{}
function Kep($path, $szin = "c8322a") {
  $k = "$path|$szin"
  if (-not $cache.ContainsKey($k)) {
    $c = [Kep]::Load($path); $mp = $path -replace '\.png$', '_m.png'; $m = $null
    if (Test-Path $mp) { $m = [Kep]::Load($mp) }
    $cache[$k] = [Kep]::Tint($c, $m, (C $szin), $ACC)
  }
  return $cache[$k]
}
$DIRS = "e", "se", "s", "sw", "w", "nw", "n", "ne"
$EPUL = "hq_0", "house_0", "barracks_0", "farm_0", "tower_0", "market_0", "barracks_3"
$EGYS = @(@("worker_0", "munkás"), @("spear_0", "dárdás"), @("ranged_0", "számszeríjász"), @("cav_0", "lovag"),
          @("ranged_3", "lövész (1940-es évek)"), @("tank_3", "harckocsi (1940-es évek)"))

# sorok: @{cim; kepek = @(@(bitmap, felirat))}
function Sorok() {
  $s = @()
  $s += @{ cim = "Épületek — 15. század (+ laktanya az 1940-es évekből)"; kepek = @($EPUL | % { ,@((Kep "$E\$_.png"), $_) }) }
  $s += @{ cim = "Építkezés (állvány)"; kepek = @($EPUL | % { ,@((Kep "$E\$($_)_epit.png"), ($_ + " építés")) }) }
  foreach ($egy1 in $EGYS) {
    $n = $egy1[0]; $k = @()
    foreach ($d in $DIRS) { $k += ,@((Kep "$U\$($n)_stand_$d.png"), $d) }
    if ($n -ne "tank_3") { for ($i = 0; $i -lt 8; $i++) { $k += ,@((Kep "$U\$($n)_walk_se_$i.png"), "járás $i") }
                          $k += ,@((Kep "$U\$($n)_idle_se.png"), "pihen") }
    $k += ,@((Kep "$U\$($n)_attack_se.png"), "támad")
    $s += @{ cim = "$($egy1[1]) — 8 irány, járásciklus (DK), pihenő, támadás"; kepek = $k }
  }
  $k = @()
  foreach ($nz in $NEMZET) { $k += ,@((Kep "$E\hq_0.png" $nz[1]), $nz[0]) }
  foreach ($nz in $NEMZET) { $k += ,@((Kep "$U\cav_0_stand_se.png" $nz[1]), $nz[0]) }
  foreach ($nz in $NEMZET) { $k += ,@((Kep "$U\tank_3_stand_se.png" $nz[1]), $nz[0]) }
  $s += @{ cim = "Csapatszín a maszkból (ugyanaz a render, 5 nemzet)"; kepek = $k }
  return $s
}

$sorok = Sorok
$szakaszok = @(@(0.5, "JÁTÉKBELI MÉRET (1x zoom: 1 világképpont = 1 képpont)"), @(1.0, "2x NAGYÍTÁS (a render natív felbontása)"))
$W = 0; $H = 60
foreach ($sz in $szakaszok) {
  $H += 50
  foreach ($r in $sorok) {
    $x = 20; $hh = 0
    foreach ($p in $r.kepek) { $x += [int]($p[0].Width * $sz[0]) + 8; $hh = [Math]::Max($hh, [int]($p[0].Height * $sz[0])) }
    $W = [Math]::Max($W, $x + 20); $H += $hh + 44
  }
}
$bg = [Kep]::Grass($W, $H, 7)
$g = [Kep]::G($bg)
$fehér = [System.Drawing.Color]::White
[Kep]::Text($g, "BIRODALOM — Blender stílusminta (15. század + 1940-es évek), csapatszín: maszk + árnyaló", 20, 16, 26, $fehér)
$y = 60
foreach ($sz in $szakaszok) {
  $y += 10; [Kep]::Text($g, $sz[1], 20, $y, 22, (C "ffe9a0")); $y += 40
  foreach ($r in $sorok) {
    [Kep]::Text($g, $r.cim, 20, $y, 14, $fehér); $y += 20
    $x = 20; $hh = 0
    foreach ($p in $r.kepek) { $hh = [Math]::Max($hh, [int]($p[0].Height * $sz[0])) }
    foreach ($p in $r.kepek) {
      $b = $p[0]; $w2 = [int]($b.Width * $sz[0]); $h2 = [int]($b.Height * $sz[0])
      [Kep]::Draw($g, $b, $x, $y + $hh - $h2, $sz[0], $false)
      if ($sz[0] -ge 1.0 -or $r.cim -like "Épület*" -or $r.cim -like "Építk*" -or $r.cim -like "Csapat*") {
        [Kep]::Text($g, $p[1], $x, $y + $hh + 2, 11, (C "e0e0e0")) }
      $x += $w2 + 8
    }
    $y += $hh + 24
  }
}
$bg.Save((Join-Path $Minta "kontaktlap.png"), [System.Drawing.Imaging.ImageFormat]::Png)

# ---- makett a játék képernyőképén -------------------------------------------
# A játékablak 1028x749, a nézet 1280x720-as vetítése "expand" módban:
# 1 világképpont = 0,803 képernyőképpont 1x zoomon (2x zoomon 1,606).
$SK = [Math]::Min(1028 / 1280.0, 749 / 720.0)
$man = @{}
foreach ($f in @("$E\manifest.json", "$U\manifest.json")) {
  $j = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($p in $j.PSObject.Properties) { $man[$p.Name] = $p.Value }
}
function Tesz($g, $nev, $dir, $wx, $wy, $zoom, $szin = "c8322a") {
  # (wx, wy): a talppont képernyőhelye; a sprite a 2x-es renderből kicsinyítve
  $b = Kep "$dir\$nev.png" $szin
  $m = $man[$nev]; $k = $SK * $zoom / 2.0
  [Kep]::Draw($g, $b, $wx - $m.ox * $k, $wy - $m.oy * $k, $k, $true)
}
function Makett($hatter, $zoom, $ki, $d) {
  $bg = [Kep]::Load($hatter); $g = [Kep]::G($bg)
  $z = $zoom; $o = $d
  # egy kis falu: vár, házak, laktanya, tanya, torony, piac + egységek
  Tesz $g "farm_0" $E ($o[0] + 60 * $z) ($o[1] - 95 * $z) $z
  Tesz $g "hq_0" $E ($o[0] + 0) ($o[1] + 0) $z
  Tesz $g "house_0" $E ($o[0] + 110 * $z) ($o[1] - 40 * $z) $z
  Tesz $g "house_0_epit" $E ($o[0] + 170 * $z) ($o[1] - 50 * $z) $z
  Tesz $g "tower_0" $E ($o[0] - 100 * $z) ($o[1] - 70 * $z) $z
  Tesz $g "barracks_0" $E ($o[0] - 130 * $z) ($o[1] + 60 * $z) $z
  Tesz $g "market_0" $E ($o[0] + 130 * $z) ($o[1] + 40 * $z) $z
  $egy = @(@("worker_0_walk_se_2", 60, 70), @("worker_0_attack_se", 80, 80), @("worker_0_stand_sw", 48, 88),
           @("spear_0_stand_s", -40, 110), @("spear_0_stand_s", -28, 114), @("spear_0_walk_se_4", -16, 118),
           @("ranged_0_stand_se", -60, 128), @("ranged_0_attack_se", -46, 132), @("cav_0_walk_se_3", 20, 130),
           @("cav_0_stand_e", 60, 125))
  foreach ($eg in $egy) { Tesz $g $eg[0] $U ($o[0] + $eg[1] * $z) ($o[1] + $eg[2] * $z) $z }
  # ellenség: kék
  Tesz $g "cav_0_stand_w" $U ($o[0] + 150 * $z) ($o[1] + 125 * $z) $z "2e56b8"
  Tesz $g "spear_0_stand_sw" $U ($o[0] + 175 * $z) ($o[1] + 118 * $z) $z "2e56b8"
  Tesz $g "ranged_0_stand_w" $U ($o[0] + 190 * $z) ($o[1] + 128 * $z) $z "2e56b8"
  # 1940-es évek csoport a kép szélén
  Tesz $g "barracks_3" $E ($o[0] + 300 * $z) ($o[1] - 40 * $z) $z "2e56b8"
  Tesz $g "tank_3_stand_sw" $U ($o[0] + 280 * $z) ($o[1] + 40 * $z) $z "2e56b8"
  Tesz $g "ranged_3_walk_se_1" $U ($o[0] + 310 * $z) ($o[1] + 30 * $z) $z "2e56b8"
  Tesz $g "ranged_3_attack_se" $U ($o[0] + 322 * $z) ($o[1] + 42 * $z) $z "2e56b8"
  $bg.Save($ki, [System.Drawing.Imaging.ImageFormat]::Png)
}
Makett (Join-Path $Minta "jatek_hatter.png") 1.0 (Join-Path $Minta "makett_1x.png") @(560, 330)
Makett (Join-Path $Minta "jatek_hatter_z2.png") 2.0 (Join-Path $Minta "makett_2x.png") @(330, 345)
