@echo off
setlocal enabledelayedexpansion

rem capture_logs_after_flash.bat
rem Collect post-flash state and logs from a popsicle device in Android.
rem Does NOT flash anything.
rem
rem Usage:
rem   capture_logs_after_flash.bat

set TIMESTAMP=%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%%time:~3,2%%time:~6,2%
set TIMESTAMP=%TIMESTAMP: =0%
set OUTDIR=%USERPROFILE%\Desktop\popsicle_logs_%TIMESTAMP%
mkdir "%OUTDIR%" 2>nul

echo ==========================================
echo  popsicle post-flash log capture
echo  output: %OUTDIR%
echo ==========================================

echo.
echo [1/4] Checking adb device...
adb devices > "%OUTDIR%\adb_devices.txt" 2>&1
findstr /C:"device" "%OUTDIR%\adb_devices.txt" >nul
if errorlevel 1 (
    echo ERROR: no device in Android mode. Reboot to system first.
    type "%OUTDIR%\adb_devices.txt"
    exit /b 1
)

echo.
echo [2/4] Collecting fastboot getvars (reboot to fastboot if you want these)...
rem Fastboot vars require bootloader mode. Keep the commands here for reference,
rem but they will fail if the device is in Android. The user can run this section
rem manually after `adb reboot bootloader`.
(
    echo === fastboot getvar all ===
    fastboot getvar all 2>&1
    echo.
    echo === fastboot getvar gbl-chainload_mode ===
    fastboot getvar gbl-chainload_mode 2>&1
    echo.
    echo === fastboot getvar gbl-chainload_build ===
    fastboot getvar gbl-chainload_build 2>&1
) > "%OUTDIR%\fastboot_vars.txt" 2>&1

echo.
echo [3/4] Collecting Android properties...
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
    echo.
    echo === ro.product.manufacturer ===
    adb shell getprop ro.product.manufacturer
    echo.
    echo === ro.product.device ===
    adb shell getprop ro.product.device
) > "%OUTDIR%\props.txt" 2>&1

echo.
echo [4/4] Collecting logs...
adb logcat -d -b main -b system -b events > "%OUTDIR%\logcat.txt" 2>&1
adb shell dmesg > "%OUTDIR%\dmesg.txt" 2>&1
adb shell su -c "cat /proc/last_kmsg" > "%OUTDIR%\last_kmsg.txt" 2>&1 || true

echo.
echo ==========================================
echo  Done. Logs saved to:
echo  %OUTDIR%
echo.
echo  Send the whole folder to the assistant.
echo ==========================================

pause
