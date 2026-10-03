# A Birodalom hátralévő egységlapjainak renderelése (egyetlen Blender-folyamat, mert a gépnek kevés a memóriája).
# Ütemezett feladat indítja este 18:00-kor („Birodalom Blender-render”), rejtett ablakban.
$ErrorActionPreference = 'Continue'
$blender = 'C:\Users\student\Downloads\blender-5.2.2-windows-x64\blender.exe'
$dir = $PSScriptRoot
$out = 'C:\Users\student\AppData\Local\Temp\claude\C--Users-student-Documents-j-t-kaim\1c95f700-ab2e-45dc-a8a0-f692a6e5e0e2\scratchpad\blender_kesz\units'
$naplo = Join-Path $out 'ejszakai_render.log'
function Naplo($s) { Add-Content -Path $naplo -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $s) -Encoding UTF8 }

Naplo 'Indul: worker_3 újrarenderelése'
& $blender --background --python (Join-Path $dir 'render_egyseg.py') -- $out worker_3 --ujra *>> $naplo
Naplo 'Indul: a hátralévő lapok'
& $blender --background --python (Join-Path $dir 'render_egyseg.py') -- $out *>> $naplo
Naplo 'KÉSZ'
