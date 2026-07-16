@echo off
setlocal enabledelayedexpansion

rem flash_and_test_popsicle.bat
rem Flash a gbl-chainload EFISP image for Xiaomi popsicle and capture
rem post-boot state to verify whether mode-1 hooks installed correctly.
rem
rem Usage:
rem   flash_and_test_popsicle.bat C:\path\to\gbl-chainload-popsicle.img

if "%~1"=="" (
    echo Usage: %~nx0 path\to\gbl-chainload-popsicle.img
    exit /b 1
)

set IMG=%~f1
set TIMESTAMP=%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set TIMESTAMP=%TIMESTAMP: =0%
set OUTDIR=%USERPROFILE%\Desktop\gbl_chainload_test_%TIMESTAMP%
mkdir "%OUTDIR%" 2>nul

echo ==========================================
echo  gbl-chainload popsicle test
echo  image: %IMG%
echo  output: %OUTDIR%
echo ==========================================

echo.
echo [1/5] Checking fastboot device...
fastboot devices > "%OUTDIR%\fastboot_devices.txt" 2>&1
findstr /C:"fastboot" "%OUTDIR%\fastboot_devices.txt" >nul
if errorlevel 1 (
    echo ERROR: no device in fastboot mode. Reboot to fastboot first.
    type "%OUTDIR%\fastboot_devices.txt"
    exit /b 1
)

echo.
echo [2/5] Flashing efisp...
fastboot flash efisp "%IMG%" > "%OUTDIR%\flash.log" 2>&1
if errorlevel 1 (
    echo ERROR: fastboot flash efisp failed.
    type "%OUTDIR%\flash.log"
    exit /b 1
)

echo.
echo [3/5] Rebooting device...
fastboot reboot > "%OUTDIR%\reboot.log" 2>&1

echo.
echo [4/5] Waiting for adb...
adb wait-for-device >nul 2>&1
timeout /t 12 /nobreak >nul

echo.
echo [5/5] Collecting boot state and logs...
(
    echo === ro.boot.vbmeta.device_state ===
    adb shell getprop ro.boot.vbmeta.device_state
    echo.
    echo === ro.boot.verifiedbootstate ===
    adb shell getprop ro.boot.verifiedbootstate
    echo.
    echo === ro.boot.flash.locked ===
    adb shell getprop ro.boot.flash.locked
    echo.
    echo === ro.boot.slot_suffix ===
    adb shell getprop ro.boot.slot_suffix
    echo.
    echo === ro.build.version.incremental ===
    adb shell getprop ro.build.version.incremental
) > "%OUTDIR%\props.txt" 2>&1

adb logcat -d -b main -b system -b events > "%OUTDIR%\logcat.txt" 2>&1

rem dmesg usually needs root; do not fail if it is unavailable.
adb shell dmesg > "%OUTDIR%\dmesg.txt" 2>&1

echo.
echo ==========================================
echo  Done. Results saved to:
echo  %OUTDIR%
echo.
echo  Send the whole folder to the assistant.
echo ==========================================

pause
