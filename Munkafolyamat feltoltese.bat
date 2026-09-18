@echo off
setlocal
title Birodalom - kiadas-munkafolyamat feltoltese
cd /d "%~dp0"

rem A Git a szomszedos PortableGit mappabol jon (az utvonalat a %~dp0 adja,
rem igy az ekezetes mappanev sem okoz gondot); ha nincs ott, a PATH-rol.
set "GIT=%~dp0..\PortableGit\cmd\git.exe"
if not exist "%GIT%" set "GIT=git"

echo.
echo === A KIADAS-MUNKAFOLYAMAT FELTOLTESE ===
echo.
echo A .github\workflows\kiadas.yml az a fajl, amelyik a GitHubon elkesziti a
echo kesz Windows .exe-t es a macOS csomagot. A GitHub ezt CSAK "workflow"
echo jogosultsagu bejelentkezessel engedi felkuldeni, ezert most kijelentkeztetlek.
echo.
echo A kovetkezo lepesnel megnyilik a bongeszo: jelentkezz be a GitHubra
echo (Parthenon2-boop), es engedelyezd a kerest.
echo.
pause

cmdkey /delete:LegacyGeneric:target=git:https://github.com >nul 2>&1

"%GIT%" add -f ".github/workflows/kiadas.yml"
"%GIT%" commit -m "Kiadas-munkafolyamat (Windows + macOS)"
"%GIT%" push origin main
if errorlevel 1 goto hiba

echo.
echo KESZ! Innentol egy verziocimke elkesziti a kesz csomagokat:
echo     git tag v1.0
echo     git push origin v1.0
echo.
echo A .gitignore-bol a ".github/workflows/" sort mar kiveheted.
pause
exit /b 0

:hiba
echo.
echo NEM SIKERULT. Valoszinuleg a bejelentkezes megint "workflow" jog nelkul jott.
echo Visszavonom a helyi commitot, hogy a tobbi feltoltes tovabbra is mukodjon.
"%GIT%" reset --soft HEAD~1
"%GIT%" restore --staged ".github/workflows/kiadas.yml"
echo.
echo Masik ut: a GitHub webfeluleten add hozza kezzel:
echo   github.com/Parthenon2-boop/birodalom - Add file - Create new file
echo   fajlnev:  .github/workflows/kiadas.yml
echo   es masold be a helyi fajl tartalmat.
pause
exit /b 1
