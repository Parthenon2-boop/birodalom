# Gyors előnézet rácsban: a megadott sprite-okat (maszkkal színezve) a render
# N-szeresére nagyítva (legközelebbi szomszéd) fűháttérre rakja.
#   elonezet.ps1 -Kimenet out.png -Nagyitas 3 -Oszlop 8 -Kepek a.png,b.png,...
param([string]$Kimenet, [double]$Nagyitas = 2, [int]$Oszlop = 8, [string]$Szin = "c8322a",
      [string[]]$Kepek)
Add-Type -ReferencedAssemblies System.Drawing -Path (Join-Path $PSScriptRoot "kepmuvelet.cs")
$team = [System.Drawing.ColorTranslator]::FromHtml("#" + $Szin)
$acc = [System.Drawing.ColorTranslator]::FromHtml("#e8c860")
$lista = @()
foreach ($k in $Kepek) {
  $c = [Kep]::Load($k)
  $mp = $k -replace '\.png$', '_m.png'
  $m = $null; if (Test-Path $mp) { $m = [Kep]::Load($mp) }
  $lista += ,([Kep]::Tint($c, $m, $team, $acc))
}
$cw = 0; $ch = 0
foreach ($b in $lista) { $cw = [Math]::Max($cw, $b.Width); $ch = [Math]::Max($ch, $b.Height) }
$cw = [int]($cw * $Nagyitas) + 6; $ch = [int]($ch * $Nagyitas) + 6
$n = $lista.Count; $cols = [Math]::Min($Oszlop, $n); $rows = [Math]::Ceiling($n / $cols)
$bg = [Kep]::Grass($cols * $cw + 6, $rows * $ch + 6, 1)
$g = [Kep]::G($bg)
for ($i = 0; $i -lt $n; $i++) {
  $x = 6 + ($i % $cols) * $cw; $y = 6 + [Math]::Floor($i / $cols) * $ch
  [Kep]::Draw($g, $lista[$i], $x, $y, $Nagyitas, $false)
}
$bg.Save($Kimenet, [System.Drawing.Imaging.ImageFormat]::Png)
