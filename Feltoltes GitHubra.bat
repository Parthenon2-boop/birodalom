@echo off
chcp 65001 > nul
title Birodalom - feltoltes a GitHubra
set GIT=C:\Users\student\Documents\játékaim\PortableGit\cmd\git.exe
cd /d "%~dp0"

echo.
echo === BIRODALOM: feltoltes a GitHubra ===
echo Tarolo: https://github.com/Parthenon2-boop/birodalom
echo.

if not exist "%GIT%" (
  echo Nem talalom a Gitet itt: %GIT%
  echo Ird at ebben a fajlban a GIT sort a helyes utvonalra.
  pause
  exit /b 1
)

set /p MSG=Mi valtozott? (Enter = "Frissites"):
if "%MSG%"=="" set MSG=Frissites

"%GIT%" add -A
"%GIT%" commit -m "%MSG%"
echo.
echo Feltoltes... (ha bejelentkezest ker, valaszd a "Sign in with your browser" lehetoseget)
"%GIT%" push -u origin main

echo.
if errorlevel 1 (
  echo HIBA: a feltoltes nem sikerult. Nezd meg a fenti uzenetet.
  pause
  exit /b 1
)

echo KESZ! A tobbi gepen az indito mar ezt fogja letolteni.
echo.
echo Ha KESZ JATEKOT (exe-t) is akarsz kiadni, kell egy verzio-cimke:
echo    "%GIT%" tag v1.0
echo    "%GIT%" push origin v1.0
echo Ekkor a GitHub Actions leforditja a Windows es a macOS csomagot,
echo es kozzeteszi kiadaskent - az indito ezt tolti le a tobbi gepre.
pause
