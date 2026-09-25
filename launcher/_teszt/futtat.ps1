param(
	[string[]]$csak = @(),          # csak ezek (pl. -csak fiok,dlc  vagy  -csak indulas)
	[int]$korlat = 240              # tesztenként ennyi másodperc
)
# ParthLauncher – automatikus tesztek.
#
#   .\_teszt\futtat.ps1                   minden teszt
#   .\_teszt\futtat.ps1 -csak fiok,dlc
#
# BIZTONSÁG: a futás idejére a projekt mellé egy override.cfg kerül, amely a user:// mappát a
# %APPDATA%\ParthTeszt\ParthLauncher próbamappába irányítja. A launcher a játékok adatmappáit a
# user:// szülőjéből számolja (…\ParthTeszt\Heptarchia, …\ParthTeszt\Kard és Mágia), így a valódi
# beállítás, a belépés és a telepített kiegészítők érintetlenek maradnak. A végén az override.cfg
# és a próbamappa törlődik, és ellenőrizzük, hogy a valódi ParthLauncher.cfg nem változott.
# A fiókszerverhez (Supabase) egyik teszt sem küld kérést: a válaszokat a _teszt/_mock.gd adja.
# Csak nyilvános címeket olvasunk (GitHub-kiadások, a hírfolyam).
# Ablak: headless, vagy (a képekhez) a képernyőn kívül (--position 20000,20000).

$g = 'C:\Users\student\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$mappa = Split-Path -Parent $MyInvocation.MyCommand.Path
$projekt = Split-Path -Parent $mappa
$homokozo = Join-Path $env:APPDATA 'ParthTeszt'
$valodi = Join-Path $env:APPDATA 'Godot\app_userdata\ParthLauncher\ParthLauncher.cfg'
$override = Join-Path $projekt 'override.cfg'
$kepek = Join-Path $mappa '_kepek'
$ki = Join-Path $env:TEMP 'parth_teszt_ki.txt'

function Hash($p) { if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { 'nincs' } }
$elotte = Hash $valodi

if (Test-Path $override) { Write-Error "Már van override.cfg a launcher mappájában – nem írom felül."; exit 2 }
if (Test-Path $homokozo) { Remove-Item -Recurse -Force $homokozo }
Set-Content -LiteralPath $override -Encoding Ascii -Value @(
	'[application]', '', 'config/use_custom_user_dir=true', 'config/custom_user_dir_name="ParthTeszt/ParthLauncher"')
New-Item -ItemType Directory -Force $kepek | Out-Null

# név -> @(szkript vagy '' = a főjelenet, ablakos?, további argumentumok, előkészítés)
$TESZTEK = [ordered]@{
	'dlc_verzio'      = @('res://_test/dlc_verzio.gd', $false, @(), '')
	'fiok'            = @('res://_teszt/fiok.gd', $false, @('--', '--halozat-nelkul'), '')
	'dlc'             = @('res://_teszt/dlc.gd', $false, @('--', '--halozat-nelkul'), '')
	'halozat'         = @('res://_teszt/halozat.gd', $false, @('--', '--halozat-nelkul'), '')
	'kepek'           = @('res://_teszt/kepek.gd', $true, @('--', '--halozat-nelkul', "--kepek=$kepek"), 'mentett')
	'kepek_mac'       = @('res://_teszt/kepek.gd', $true, @('--', '--halozat-nelkul', '--mac-proba', "--kepek=$kepek"), 'mentett')
	'indulas_ures'    = @('', $true, @('--quit-after', '900'), '')
	'indulas_mentett' = @('', $true, @('--quit-after', '900'), 'mentett')
}

$jo = 0; $rossz = @()
try {
	$lista = if ($csak.Count -gt 0) { @($TESZTEK.Keys | Where-Object { $n = $_; $csak | Where-Object { $n -like "$_*" } }) } else { @($TESZTEK.Keys) }
	foreach ($t in $lista) {
		$szkript, $ablakos, $extra, $elo = $TESZTEK[$t]
		# minden teszt tiszta próbamappával indul
		if (Test-Path $homokozo) { Remove-Item -Recurse -Force $homokozo }
		New-Item -ItemType Directory -Force (Join-Path $homokozo 'ParthLauncher') | Out-Null
		if ($elo -eq 'mentett' -and (Test-Path $valodi)) {
			# a felhasználó beállításainak MÁSOLATA, a munkamenet kulcsa nélkül (a próba nem léphet be
			# a nevében, és nem is újíthatja meg – az a valódi belépését érvénytelenítené), és
			# automatikus letöltés nélkül (a telepítési mappákat csak olvassa); a képeken se látsszon a valódi fióknév és e-mail-cím
			$sorok = Get-Content -LiteralPath $valodi -Encoding UTF8 | ForEach-Object {
				if ($_ -match '^refresh_token=') { 'refresh_token=""' }
				elseif ($_ -match '^auto_update=') { 'auto_update=false' }
				elseif ($_ -match '^auto_play=') { 'auto_play=false' }
				elseif ($_ -match '^email=') { 'email="proba@pelda.hu"' }
				elseif ($_ -match '^fioknev=') { 'fioknev="Probafiok"' }
				else { $_ } }
			[IO.File]::WriteAllLines((Join-Path $homokozo 'ParthLauncher\ParthLauncher.cfg'), [string[]]$sorok, (New-Object Text.UTF8Encoding $false))
		}
		$arg = @('--path', $projekt)
		if ($szkript -ne '') { $arg += @('-s', $szkript) }
		if ($ablakos) { $arg = @('--position', '20000,20000') + $arg } else { $arg = @('--headless') + $arg }
		$arg += $extra
		$p = Start-Process -FilePath $g -ArgumentList $arg -NoNewWindow -PassThru -RedirectStandardOutput $ki -RedirectStandardError "$ki.err"
		$null = $p.Handle
		if (-not $p.WaitForExit($korlat * 1000)) {
			Stop-Process -Id $p.Id -Force
			"{0,-16} IDŐTÚLLÉPÉS ({1} mp)" -f $t, $korlat; $rossz += $t; continue
		}
		$sorok = @(Get-Content $ki -Encoding UTF8) + @(Get-Content "$ki.err" -Encoding UTF8)
		Set-Content -LiteralPath (Join-Path $kepek "$t.log") -Value $sorok -Encoding UTF8
		$hibak = @($sorok | Where-Object { $_ -match '^\s*HIBA|SCRIPT ERROR|^\s*ERROR:|Parse Error|USER ERROR' -and $_ -notmatch 'resources still in use at exit' })
		$okok = @($sorok | Where-Object { $_ -match '^\s*OK ' }).Count
		if ($p.ExitCode -eq 0 -and $hibak.Count -eq 0) { "{0,-16} ok ({1} ellenőrzés)" -f $t, $okok; $jo++ }
		else {
			"{0,-16} HIBA (kilépési kód {1}, {2} ok)" -f $t, $p.ExitCode, $okok; $rossz += $t
			foreach ($h in ($hibak | Select-Object -First 12)) { "      $h" }
		}
	}
}
finally {
	Remove-Item -LiteralPath $override -Force -ErrorAction SilentlyContinue
	if (Test-Path $homokozo) { Remove-Item -Recurse -Force $homokozo -ErrorAction SilentlyContinue }
	Remove-Item "$ki", "$ki.err" -Force -ErrorAction SilentlyContinue
}
""
"Összesen: $jo rendben, $($rossz.Count) hibás" + $(if ($rossz.Count -gt 0) { ": " + ($rossz -join ', ') } else { '' })
$utana = Hash $valodi
if ($utana -eq $elotte) { "A valódi ParthLauncher.cfg változatlan." } else { "FIGYELEM: a valódi ParthLauncher.cfg megváltozott!" }
"Képek és naplók: $kepek"
