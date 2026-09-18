; ParthLauncher – Windows telepítő (NSIS 3)
;
; Mit csinál?
;   - A ParthLauncher.exe-t a felhasználó saját programmappájába teszi
;     (%LOCALAPPDATA%\Programs\ParthLauncher) — így NEM kell rendszergazda,
;     és nem ugrik fel a UAC-ablak.
;   - Start menü és (kérésre) asztali parancsikont készít.
;   - Bejegyzi a Programok és szolgáltatások közé, és ír egy eltávolítót.
;   - Eltávolításkor felajánlja a letöltött játékok törlését is.
;
; Fordítás (a kiadás-munkafolyamat ezt futtatja Linuxon is):
;   makensis -DVERZIO=1.4 -DFORRAS=build/launcher/ParthLauncher.exe parthlauncher.nsi

Unicode true

!ifndef VERZIO
  !define VERZIO "1.0"
!endif
!ifndef FORRAS
  !define FORRAS "..\..\build\launcher\ParthLauncher.exe"
!endif
!ifndef KIMENET
  !define KIMENET "ParthLauncher-Setup.exe"
!endif

!define NEV      "ParthLauncher"
!define CEG      "Parthenon"
!define KULCS    "Software\Microsoft\Windows\CurrentVersion\Uninstall\ParthLauncher"

Name "${NEV} ${VERZIO}"
OutFile "${KIMENET}"
InstallDir "$LOCALAPPDATA\Programs\${NEV}"
InstallDirRegKey HKCU "Software\${NEV}" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUninstDetails show
BrandingText "${NEV} ${VERZIO}"

!include "MUI2.nsh"

!define MUI_ABORTWARNING
!define MUI_ICON "ikon.ico"
!define MUI_UNICON "ikon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\ParthLauncher.exe"
!define MUI_FINISHPAGE_RUN_TEXT "A ParthLauncher indítása"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Hungarian"
!insertmacro MUI_LANGUAGE "English"

Section "ParthLauncher" SecFo
  SectionIn RO
  SetOutPath "$INSTDIR"
  File "/oname=ParthLauncher.exe" "${FORRAS}"

  ; Start menü és asztal
  CreateDirectory "$SMPROGRAMS\${NEV}"
  CreateShortCut "$SMPROGRAMS\${NEV}\${NEV}.lnk" "$INSTDIR\ParthLauncher.exe"
  CreateShortCut "$DESKTOP\${NEV}.lnk" "$INSTDIR\ParthLauncher.exe"

  ; Eltávolító és a Programok listája
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\${NEV}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${KULCS}" "DisplayName"     "${NEV} — Birodalom és Heptarchia indító"
  WriteRegStr HKCU "${KULCS}" "DisplayVersion"  "${VERZIO}"
  WriteRegStr HKCU "${KULCS}" "Publisher"       "${CEG}"
  WriteRegStr HKCU "${KULCS}" "DisplayIcon"     "$INSTDIR\ParthLauncher.exe"
  WriteRegStr HKCU "${KULCS}" "UninstallString" "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "${KULCS}" "InstallLocation" "$INSTDIR"
  WriteRegDWORD HKCU "${KULCS}" "NoModify" 1
  WriteRegDWORD HKCU "${KULCS}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\ParthLauncher.exe"
  Delete "$INSTDIR\Uninstall.exe"

  ; A letöltött játékok az indító mellett laknak; csak azt a mappát
  ; bántjuk, amit maga az indító hozott létre (marker-fájl jelzi).
  IfFileExists "$INSTDIR\Birodalom\birodalom_launcher.marker" 0 +2
    RMDir /r "$INSTDIR\Birodalom"
  IfFileExists "$INSTDIR\Heptarchia\heptarchia_launcher.marker" 0 +2
    RMDir /r "$INSTDIR\Heptarchia"

  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\${NEV}\${NEV}.lnk"
  RMDir  "$SMPROGRAMS\${NEV}"
  Delete "$DESKTOP\${NEV}.lnk"
  DeleteRegKey HKCU "${KULCS}"
  DeleteRegKey HKCU "Software\${NEV}"
SectionEnd
