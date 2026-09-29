# A renderelt lapok és épületképek átmásolása a játékba.
#   telepit.ps1 -Units <render mappa> -Buildings <render mappa>
# - a PNG-ket az assets/art3d/units és assets/art3d/buildings mappába teszi,
# - a darabonkénti <kulcs>.json-okból egy manifest.json-t fűz össze,
# - minden képhez .import fájlt ír: VRAM-tömörítés + mipmap (a gyenge gépen
#   ez negyedére csökkenti a textúramemóriát, és a kicsinyített kép nem vibrál).
param([string]$Units = "", [string]$Buildings = "")
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$utf8 = New-Object Text.UTF8Encoding $false

function Import-Fajl($png, $resPath) {
  $imp = "$png.import"
  if (Test-Path $imp) { return }
  $t = @"
[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="$resPath"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"@
  [IO.File]::WriteAllText($imp, $t, $utf8)
}

function Telepit($src, $sub) {
  if (-not $src -or -not (Test-Path $src)) { return }
  $dst = Join-Path $root "assets\art3d\$sub"
  New-Item -ItemType Directory -Force $dst | Out-Null
  $man = [ordered]@{}
  foreach ($j in Get-ChildItem $src -Filter *.json | Where-Object { $_.Name -ne "manifest.json" -and $_.Name -notlike "*_proba.json" } | Sort-Object Name) {
    $d = Get-Content $j.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $d.PSObject.Properties) { $man[$p.Name] = $p.Value }
    $kulcs = $j.BaseName
    foreach ($png in Get-ChildItem $src -Filter "$kulcs*.png") {
      if ($png.Name -like "*_proba*") { continue }
      $b = $png.BaseName
      if ($b -ne $kulcs -and $b -ne "$($kulcs)_m" -and $b -notmatch "^$([regex]::Escape($kulcs))_(epit|rom)(_m)?$") { continue }
      Copy-Item $png.FullName (Join-Path $dst $png.Name) -Force
      Import-Fajl (Join-Path $dst $png.Name) "res://assets/art3d/$sub/$($png.Name)"
    }
  }
  $json = $man | ConvertTo-Json -Depth 8 -Compress
  [IO.File]::WriteAllText((Join-Path $dst "manifest.json"), $json, $utf8)
  Write-Output "$sub : $($man.Count) bejegyzés"
}

Telepit $Units "units"
Telepit $Buildings "buildings"
