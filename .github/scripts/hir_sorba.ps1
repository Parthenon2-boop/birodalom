# Hír a várólistára: éjfél után a „Napi hírösszesítő” (napi_hir.yml) teszi ki a nap összes hírét
# egyetlen bejegyzésként a docs/hirek.json-ba (honlap + launcher).
#   .\.github\scripts\hir_sorba.ps1 -json uj_hir.json
# Az uj_hir.json egy objektum vagy tömb, a hirek.json bejegyzéseivel azonos mezőkkel
# (datum, cim, cimke, szoveg, cim_en, szoveg_en, cim_de, szoveg_de, cimke_en, cimke_de).
# A datum elhagyható: ilyenkor a mai nap kerül bele.
param([Parameter(Mandatory)] [string]$json)
$ErrorActionPreference = 'Stop'
$gyoker = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ut = Join-Path $gyoker 'hirek_varolista.json'
$lista = @()
# (PowerShell 5.1: az üres "[]" egy elemként jönne át, ezért elemenként gyűjtjük)
if (Test-Path $ut) { foreach ($x in ([IO.File]::ReadAllText($ut, [Text.Encoding]::UTF8) | ConvertFrom-Json)) { $lista += $x } }
$uj = @()
foreach ($x in ([IO.File]::ReadAllText((Resolve-Path $json), [Text.Encoding]::UTF8) | ConvertFrom-Json)) { $uj += $x }
foreach ($h in $uj) {
	if (-not $h.datum) { $h | Add-Member -NotePropertyName datum -NotePropertyValue (Get-Date -Format 'yyyy-MM-dd') -Force }
	$lista += $h
}
# PowerShell 5.1: az egyelemű tömböt is tömbként írjuk ki
$ki = if ($lista.Count -eq 1) { '[' + ($lista[0] | ConvertTo-Json -Depth 5) + ']' } else { ConvertTo-Json @($lista) -Depth 5 }
[IO.File]::WriteAllText($ut, $ki + "`n", (New-Object Text.UTF8Encoding $false))
"várólistán: $($lista.Count) hír (éjfél után kerülnek ki)"
