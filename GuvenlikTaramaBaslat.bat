@echo off
chcp 65001 >nul
title Guvenlik Tarama Araci

:: Yonetici kontrolu - degilse yeniden yonetici olarak baslat
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Yonetici yetkisi gerekiyor, yeniden baslatiliyor...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo =====================================================
echo   WINDOWS + WEB SITESI GUVENLIK TARAMA ARACI
echo =====================================================
echo.

set /p siteurl="Taramak istediginiz web sitesi adresi (bos birakabilirsiniz, orn: https://siteniz.com): "
set /p autofix="Riskli ayarlari otomatik duzeltsin mi? (E/H): "

set fixflag=
if /I "%autofix%"=="E" set fixflag=-AutoFix

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0GuvenlikTarama.ps1" -WebSiteUrl "%siteurl%" %fixflag%

echo.
pause
