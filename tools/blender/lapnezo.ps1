# Egy egységlap kockáinak nagyított, színezett nézete fűháttéren.
#   lapnezo.ps1 -Lap <e.png> -Json <e.json|manifest.json> -Kimenet out.png [-Nagyitas 3] [-Sorok 0,1] [-Oszlopok 0-16]
param([string]$Lap, [string]$Json = "", [int]$Osz = 17, [int]$Sorszam = 2, [string]$Kimenet, [double]$Nagyitas = 3, [string]$Sorok = "",
      [int]$Max = 17, [int]$Tol = 0, [string]$Szin = "c8322a")
Add-Type -ReferencedAssemblies System.Drawing -Path (Join-Path $PSScriptRoot "kepmuvelet.cs")
$nev = [IO.Path]::GetFileNameWithoutExtension($Lap) -replace '_proba$', ''
if ($Json) { $j = Get-Content $Json -Raw -Encoding UTF8 | ConvertFrom-Json; $m = $j.$nev }
$c = [Kep]::Load($Lap); $mk = [Kep]::Load(($Lap -replace '\.png$', '_m.png'))
$t = [Kep]::Tint($c, $mk, [System.Drawing.ColorTranslator]::FromHtml("#" + $Szin), [System.Drawing.ColorTranslator]::FromHtml("#e8c860"))
if ($Json) { $cw = [int]$m.cw; $ch = [int]$m.ch } else { $cw = [int]($t.Width / $Osz); $ch = [int]($t.Height / $Sorszam) }
$nr = [int]($t.Height / $ch); $nc = [Math]::Min([int]($t.Width / $cw) - $Tol, $Max)
$rows = if ($Sorok) { $Sorok.Split(',') | % { [int]$_ } } else { 0..($nr - 1) }
$W = [int]($nc * ($cw * $Nagyitas + 4)) + 8; $H = [int]($rows.Count * ($ch * $Nagyitas + 4)) + 8
$bg = [Kep]::Grass($W, $H, 3); $g = [Kep]::G($bg)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$ri = 0
foreach ($r in $rows) {
  for ($ci = 0; $ci -lt $nc; $ci++) {
    $src = New-Object System.Drawing.Rectangle (($ci + $Tol) * $cw), ($r * $ch), $cw, $ch
    $dst = New-Object System.Drawing.RectangleF (4 + $ci * ($cw * $Nagyitas + 4)), (4 + $ri * ($ch * $Nagyitas + 4)), ($cw * $Nagyitas), ($ch * $Nagyitas)
    $g.DrawImage($t, $dst, $src, [System.Drawing.GraphicsUnit]::Pixel)
  }
  $ri++
}
$bg.Save($Kimenet, [System.Drawing.Imaging.ImageFormat]::Png)
