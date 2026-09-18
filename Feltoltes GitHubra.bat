@echo off
setlocal
title Birodalom - feltoltes a GitHubra
cd /d "%~dp0"

set "GIT=%~dp0..\PortableGit\cmd\git.exe"
if not exist "%GIT%" set "GIT=git"

echo.
echo === BIRODALOM: feltoltes a GitHubra ===
echo Tarolo: https://github.com/Parthenon2-boop/birodalom
echo.

set "MSG="
set /p MSG=Mi valtozott? (Enter = "Frissites"): 
if not defined MSG set "MSG=Frissites"

"%GIT%" add -A
"%GIT%" commit -m "%MSG%"
echo.
echo Feltoltes... (ha bejelentkezest ker, valaszd a "Sign in with your browser" lehetoseget)
"%GIT%" push -u origin main
if errorlevel 1 goto hiba

echo.
echo KESZ! A tobbi gepen az indito mar ezt fogja letolteni.
echo.
echo Ha KESZ JATEKOT (exe-t) is akarsz kiadni, kell egy verzio-cimke:
echo     git tag v1.0
echo     git push origin v1.0
echo A GitHub Actions ekkor leforditja a Windows es a macOS csomagot.
pause
exit /b 0

:hiba
echo.
echo HIBA: a feltoltes nem sikerult. Nezd meg a fenti uzenetet.
pause
exit /b 1
