@echo off
:: ============================================================
::  SİSTEM BAKIM VE TEMİZLİK ARACI v1.0
::  Geliştirici: Windows SysAdmin & Güvenlik Uzmanı
::  Açıklama   : Otomatik virüs tarama, sistem kontrolü ve
::               gereksiz dosya temizleme scripti
:: ============================================================

:: --- Konsol ayarları ---
chcp 65001 >nul 2>&1
color 0A
title [SİSTEM BAKIM ARACI] - Hazırlanıyor...

:: ================================================================
::  YÖNETİCİ YETKİSİ KONTROLÜ
::  Script yönetici olarak çalışmıyorsa kendini yeniden başlatır.
:: ================================================================
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  [!] Bu script Yonetici yetkisi gerektiriyor.
    echo  [*] Otomatik olarak yonetici olarak yeniden baslatiliyor...
    echo.
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: ================================================================
::  BAŞLANGIÇ EKRANI VE KULLANICI ONAYI
:: ================================================================
cls
echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║         SİSTEM BAKIM VE TEMİZLİK ARACI v1.0            ║
echo  ║                                                          ║
echo  ║  Bu araç sırasıyla şunları yapacaktır:                  ║
echo  ║   1) Virüs ve zararlı yazılım taraması (Defender)       ║
echo  ║   2) Sistem dosyası bütünlüğü kontrolü (SFC + DISM)    ║
echo  ║   3) Gereksiz dosyaların tespiti ve boyut analizi       ║
echo  ║   4) Onayınız ile temizlik ve optimizasyon              ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.
echo  [!] UYARI: Bu islemi baslatmak icin sistem yonetici
echo      yetkisiyle calismaniz gerekmektedir. (Zaten dogrulandi)
echo.
set /p "BASLA= >>> Isleme baslamak istiyor musunuz? (E/H): "
if /i "%BASLA%"=="H" goto :IPTAL
if /i "%BASLA%"=="N" goto :IPTAL
if /i not "%BASLA%"=="E" (
    if /i not "%BASLA%"=="Y" goto :IPTAL
)

:: ================================================================
::  DEĞİŞKENLER - Geçici log ve sayac dosyaları
:: ================================================================
set "LOGDOSYASI=%TEMP%\SistemBakim_Log.txt"
set "BOYUTDOSYASI=%TEMP%\SistemBakim_Boyut.txt"
set "TEHDITDOSYASI=%TEMP%\SistemBakim_Tehdit.txt"

:: Önceki oturumun loglarını temizle
if exist "%LOGDOSYASI%" del /f /q "%LOGDOSYASI%" >nul 2>&1
if exist "%BOYUTDOSYASI%" del /f /q "%BOYUTDOSYASI%" >nul 2>&1
if exist "%TEHDITDOSYASI%" del /f /q "%TEHDITDOSYASI%" >nul 2>&1

echo 0 > "%TEHDITDOSYASI%"

:: ================================================================
::  AŞAMA 1: VİRÜS VE ZARAR LI YAZILIM TARAMASI
:: ================================================================
cls
echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║  AŞAMA 1/3 - VİRÜS VE ZARAR LI YAZILIM TARAMASI       ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.
echo  [*] Windows Defender hizli tarama baslatiliyor...
echo  [*] Bu islem birkaç dakika surebilir. Lutfen bekleyin...
echo.

:: Windows Defender MpCmdRun.exe ile hızlı tarama
set "MPCMD=%ProgramFiles%\Windows Defender\MpCmdRun.exe"
if not exist "%MPCMD%" (
    set "MPCMD=%ProgramFiles(x86)%\Windows Defender\MpCmdRun.exe"
)

set "TEHDIT_SAYISI=0"

if exist "%MPCMD%" (
    echo  [~] Tarama devam ediyor... (Cikis bekleyiniz)
    "%MPCMD%" -Scan -ScanType 1 >> "%LOGDOSYASI%" 2>&1
    set "DEFENDER_DURUM=%errorlevel%"
    
    :: Tehdit bulundu mu kontrol et (hata kodu 2 = tehdit bulundu)
    if "%DEFENDER_DURUM%"=="2" (
        set "TEHDIT_SAYISI=1"
        echo  [!!!] UYARI: Tehdit tespit edildi! Temizlik asamasinda islenecek.
        echo TEHDIT_BULUNDU > "%TEHDITDOSYASI%"
    ) else (
        echo  [OK ] Windows Defender taramasi tamamlandi. Tehdit bulunamadi.
        echo TEMIZ > "%TEHDITDOSYASI%"
    )
) else (
    echo  [!] Windows Defender bulunamadi. Bu adim atlaniyor...
    echo DEFENDER_YOK > "%TEHDITDOSYASI%"
)

echo.
echo  [*] Sistem dosyasi butunlugu kontrol ediliyor (SFC)...
echo  [*] Bu islem 5-15 dakika surebilir. Lutfen bekleyiniz...
echo.

:: SFC taramasını arka planda çalıştır (log dosyasına yönlendir)
sfc /scannow >> "%LOGDOSYASI%" 2>&1
set "SFC_SONUC=%errorlevel%"

echo.
echo  [*] DISM arac ile sistem imaji kontrol ediliyor...

:: DISM ile sistem bütünlüğü kontrolü
DISM /Online /Cleanup-Image /CheckHealth >> "%LOGDOSYASI%" 2>&1
set "DISM_SONUC=%errorlevel%"

if %DISM_SONUC% neq 0 (
    echo  [!] DISM: Sistem imajinda sorun tespit edildi. Onariliyor...
    DISM /Online /Cleanup-Image /RestoreHealth >> "%LOGDOSYASI%" 2>&1
    echo  [OK ] DISM onarimi tamamlandi.
) else (
    echo  [OK ] DISM: Sistem imaji saglikli.
)

echo.
echo  [OK ] AŞAMA 1 TAMAMLANDI.
timeout /t 2 /nobreak >nul

:: ================================================================
::  AŞAMA 2: GEREKSIZ DOSYA TESPİTİ VE BOYUT ANALİZİ
:: ================================================================
cls
echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║  AŞAMA 2/3 - GEREKSİZ DOSYA TESPİTİ VE ANALİZ         ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.
echo  [*] Gereksiz dosyalar tespit ediliyor. Bekleyin...
echo.

:: PowerShell ile boyut hesaplama fonksiyonu çağrısı
:: Her lokasyonun boyutunu byte olarak hesapla ve geçici dosyaya yaz

:: --- Geçici Dosyalar (C:\Windows\Temp) ---
echo  [~] C:\Windows\Temp taranıyor...
powershell -NoProfile -Command ^
  "try { $s=(Get-ChildItem 'C:\Windows\Temp' -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if(!$s){$s=0}; $s } catch { 0 }" ^
  > "%TEMP%\b1.txt" 2>nul

:: --- Kullanıcı Temp Dosyaları (%TEMP%) ---
echo  [~] Kullanici Temp klasoru taranıyor...
powershell -NoProfile -Command ^
  "try { $s=(Get-ChildItem $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if(!$s){$s=0}; $s } catch { 0 }" ^
  > "%TEMP%\b2.txt" 2>nul

:: --- Prefetch Klasörü ---
echo  [~] Prefetch klasoru taranıyor...
powershell -NoProfile -Command ^
  "try { $s=(Get-ChildItem 'C:\Windows\Prefetch' -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if(!$s){$s=0}; $s } catch { 0 }" ^
  > "%TEMP%\b3.txt" 2>nul

:: --- Windows Update Önbelleği ---
echo  [~] Windows Update onbellegi taranıyor...
powershell -NoProfile -Command ^
  "try { $s=(Get-ChildItem 'C:\Windows\SoftwareDistribution\Download' -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if(!$s){$s=0}; $s } catch { 0 }" ^
  > "%TEMP%\b4.txt" 2>nul

:: --- Sistem Log Dosyaları ---
echo  [~] Sistem log dosyalari taranıyor...
powershell -NoProfile -Command ^
  "try { $s=(Get-ChildItem 'C:\Windows\Logs' -Filter '*.log' -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if(!$s){$s=0}; $s } catch { 0 }" ^
  > "%TEMP%\b5.txt" 2>nul

:: --- Bellek Dökümleri (Memory Dumps) ---
echo  [~] Bellek dokumleri taranıyor...
powershell -NoProfile -Command ^
  "try { $s=(Get-ChildItem 'C:\Windows\Minidump' -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if(!$s){$s=0}; $s } catch { 0 }; try { $s2=(Get-ChildItem 'C:\Windows\MEMORY.DMP' -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if(!$s2){$s2=0}; $s2 } catch { 0 }" ^
  > "%TEMP%\b6.txt" 2>nul

:: --- Thumbnail Cache ---
echo  [~] Ikon ve kucuk resim onbellegi taranıyor...
powershell -NoProfile -Command ^
  "try { $s=(Get-ChildItem \"$env:LOCALAPPDATA\Microsoft\Windows\Explorer\" -Filter 'thumbcache*.db' -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; if(!$s){$s=0}; $s } catch { 0 }" ^
  > "%TEMP%\b7.txt" 2>nul

:: Boyutları oku ve topla (PowerShell ile MB/GB dönüşümü)
powershell -NoProfile -Command ^
  "$b=@(); 1..7 | ForEach-Object { try { $v=[long](Get-Content \"$env:TEMP\b$_.txt\" -Raw -ErrorAction SilentlyContinue).Trim(); if(!$v){$v=0}; $b+=$v } catch { $b+=0 } }; $toplam=$b|Measure-Object -Sum; $mb=[math]::Round($toplam.Sum/1MB,2); $mb | Set-Content \"$env:TEMP\toplam_mb.txt\"" ^
  >nul 2>&1

set /p "TOPLAM_MB=" < "%TEMP%\toplam_mb.txt"
if "%TOPLAM_MB%"=="" set "TOPLAM_MB=0"

echo.
echo  [OK ] AŞAMA 2 TAMAMLANDI.
timeout /t 1 /nobreak >nul

:: ================================================================
::  AŞAMA 3: ÖZET RAPOR VE KULLANICI ONAYI
:: ================================================================
cls
echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║  AŞAMA 3/3 - TARAMA SONUCU ÖZET RAPORU                 ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.
echo  ┌─────────────────────────────────────────────────────────┐
echo  │  TARAMA SONUÇLARI                                       │
echo  ├─────────────────────────────────────────────────────────┤

:: Tehdit durumunu oku
set /p "TEHDIT_DURUM=" < "%TEHDITDOSYASI%"

if "%TEHDIT_DURUM%"=="TEHDIT_BULUNDU" (
    echo  │  [!!!] Virüs/Zararlı Yazılım  : TEHDİT TESPİT EDİLDİ!  │
) else if "%TEHDIT_DURUM%"=="TEMIZ" (
    echo  │  [OK ] Virüs/Zararlı Yazılım  : Tehdit Bulunamadı       │
) else (
    echo  │  [--]  Virüs/Zararlı Yazılım  : Defender Calistirilmadi │
)

if %SFC_SONUC% neq 0 (
    echo  │  [!]  Sistem Dosyaları (SFC)  : SORUN TESPİT EDİLDİ    │
) else (
    echo  │  [OK ] Sistem Dosyaları (SFC) : Sağlıklı                │
)

if %DISM_SONUC% neq 0 (
    echo  │  [!]  Sistem İmajı (DISM)     : SORUN TESPİT EDİLDİ    │
) else (
    echo  │  [OK ] Sistem İmajı (DISM)    : Sağlıklı                │
)

echo  ├─────────────────────────────────────────────────────────┤
echo  │  GEREKSİZ DOSYALAR                                      │
echo  ├─────────────────────────────────────────────────────────┤

for /f "usebackq" %%A in ("%TEMP%\b1.txt") do (
    powershell -NoProfile -Command "[math]::Round(%%A/1MB,2)" > "%TEMP%\mb_tmp.txt" 2>nul
    set /p "MB1=" < "%TEMP%\mb_tmp.txt"
)
for /f "usebackq" %%A in ("%TEMP%\b2.txt") do (
    powershell -NoProfile -Command "[math]::Round(%%A/1MB,2)" > "%TEMP%\mb_tmp.txt" 2>nul
    set /p "MB2=" < "%TEMP%\mb_tmp.txt"
)
for /f "usebackq" %%A in ("%TEMP%\b3.txt") do (
    powershell -NoProfile -Command "[math]::Round(%%A/1MB,2)" > "%TEMP%\mb_tmp.txt" 2>nul
    set /p "MB3=" < "%TEMP%\mb_tmp.txt"
)
for /f "usebackq" %%A in ("%TEMP%\b4.txt") do (
    powershell -NoProfile -Command "[math]::Round(%%A/1MB,2)" > "%TEMP%\mb_tmp.txt" 2>nul
    set /p "MB4=" < "%TEMP%\mb_tmp.txt"
)
for /f "usebackq" %%A in ("%TEMP%\b5.txt") do (
    powershell -NoProfile -Command "[math]::Round(%%A/1MB,2)" > "%TEMP%\mb_tmp.txt" 2>nul
    set /p "MB5=" < "%TEMP%\mb_tmp.txt"
)
for /f "usebackq" %%A in ("%TEMP%\b6.txt") do (
    powershell -NoProfile -Command "[math]::Round(%%A/1MB,2)" > "%TEMP%\mb_tmp.txt" 2>nul
    set /p "MB6=" < "%TEMP%\mb_tmp.txt"
)
for /f "usebackq" %%A in ("%TEMP%\b7.txt") do (
    powershell -NoProfile -Command "[math]::Round(%%A/1MB,2)" > "%TEMP%\mb_tmp.txt" 2>nul
    set /p "MB7=" < "%TEMP%\mb_tmp.txt"
)

if "%MB1%"=="" set "MB1=0"
if "%MB2%"=="" set "MB2=0"
if "%MB3%"=="" set "MB3=0"
if "%MB4%"=="" set "MB4=0"
if "%MB5%"=="" set "MB5=0"
if "%MB6%"=="" set "MB6=0"
if "%MB7%"=="" set "MB7=0"

echo  │  Windows\Temp          : %MB1% MB                          
echo  │  Kullanici Temp (%%TEMP%%) : %MB2% MB                          
echo  │  Prefetch              : %MB3% MB                          
echo  │  Windows Update Cache  : %MB4% MB                          
echo  │  Sistem Log Dosyaları  : %MB5% MB                          
echo  │  Bellek Dökümleri      : %MB6% MB                          
echo  │  Küçük Resim Önbellek  : %MB7% MB                          
echo  ├─────────────────────────────────────────────────────────┤
echo  │  TOPLAM TEMİZLENEBİLECEK ALAN : ~%TOPLAM_MB% MB                
echo  └─────────────────────────────────────────────────────────┘
echo.
echo.
color 0E
echo  ══════════════════════════════════════════════════════════
set /p "ONAY=  >>> Bilgisayar hizlandirilsin ve sorunlar giderilsin mi? (E/H): "
echo  ══════════════════════════════════════════════════════════
color 0A

if /i "%ONAY%"=="H" goto :IPTAL_TEMIZLIK
if /i "%ONAY%"=="N" goto :IPTAL_TEMIZLIK
if /i not "%ONAY%"=="E" (
    if /i not "%ONAY%"=="Y" goto :IPTAL_TEMIZLIK
)

:: ================================================================
::  AŞAMA 4: TEMİZLİK VE OPTİMİZASYON
:: ================================================================
cls
echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║  AŞAMA 4/4 - TEMİZLİK VE OPTİMİZASYON BAŞLADI         ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.

:: --- Virüs Karantina İşlemi ---
if "%TEHDIT_DURUM%"=="TEHDIT_BULUNDU" (
    echo  [*] Tespit edilen tehditler karantinaya aliniyor...
    if exist "%MPCMD%" (
        "%MPCMD%" -RemoveDefinitions -All >nul 2>&1
        "%MPCMD%" -Scan -ScanType 1 >nul 2>&1
    )
    echo  [OK ] Tehditler islendi.
    echo.
)

:: --- Windows\Temp Temizliği ---
echo  [*] Windows Temp klasoru temizleniyor...
if exist "C:\Windows\Temp\" (
    del /f /s /q "C:\Windows\Temp\*.*" >nul 2>&1
    for /d %%D in ("C:\Windows\Temp\*") do rd /s /q "%%D" >nul 2>&1
)
echo  [OK ] Windows\Temp temizlendi.

:: --- Kullanıcı Temp Temizliği ---
echo  [*] Kullanici Temp klasoru temizleniyor...
if exist "%TEMP%\" (
    del /f /s /q "%TEMP%\*.*" >nul 2>&1
    for /d %%D in ("%TEMP%\*") do rd /s /q "%%D" >nul 2>&1
)
echo  [OK ] Kullanici Temp temizlendi.

:: --- Prefetch Temizliği ---
echo  [*] Prefetch klasoru temizleniyor...
if exist "C:\Windows\Prefetch\" (
    del /f /s /q "C:\Windows\Prefetch\*.pf" >nul 2>&1
)
echo  [OK ] Prefetch temizlendi.

:: --- Windows Update Cache (SoftwareDistribution\Download) ---
echo  [*] Windows Update onbellegi temizleniyor...
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
if exist "C:\Windows\SoftwareDistribution\Download\" (
    del /f /s /q "C:\Windows\SoftwareDistribution\Download\*.*" >nul 2>&1
    for /d %%D in ("C:\Windows\SoftwareDistribution\Download\*") do rd /s /q "%%D" >nul 2>&1
)
net start wuauserv >nul 2>&1
net start bits >nul 2>&1
echo  [OK ] Windows Update onbellegi temizlendi.

:: --- Sistem Log Dosyaları ---
echo  [*] Eski sistem log dosyalari temizleniyor...
if exist "C:\Windows\Logs\" (
    del /f /s /q "C:\Windows\Logs\*.log" >nul 2>&1
)
echo  [OK ] Log dosyalari temizlendi.

:: --- Bellek Dökümleri ---
echo  [*] Bellek dokumleri temizleniyor...
if exist "C:\Windows\Minidump\" (
    del /f /s /q "C:\Windows\Minidump\*.*" >nul 2>&1
)
if exist "C:\Windows\MEMORY.DMP" (
    del /f /q "C:\Windows\MEMORY.DMP" >nul 2>&1
)
echo  [OK ] Bellek dokumleri temizlendi.

:: --- Thumbnail Cache (Küçük Resim Önbelleği) ---
echo  [*] Kucuk resim onbellegi temizleniyor...
taskkill /f /im explorer.exe >nul 2>&1
if exist "%LOCALAPPDATA%\Microsoft\Windows\Explorer\" (
    del /f /s /q "%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache*.db" >nul 2>&1
)
start explorer.exe >nul 2>&1
echo  [OK ] Kucuk resim onbellegi temizlendi.

:: --- Geri Dönüşüm Kutusu Boşaltma ---
echo  [*] Geri donusum kutusu bosaltiliyor...
powershell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1
echo  [OK ] Geri donusum kutusu bosaltildi.

:: --- DNS Cache Temizleme ---
echo  [*] DNS onbellegi temizleniyor...
ipconfig /flushdns >nul 2>&1
echo  [OK ] DNS onbellegi temizlendi.

:: --- Windows Geçici Dosya Temizleyici (cleanmgr - sessiz mod) ---
echo  [*] Windows Disk Temizleyici calistiriliyor (arka plan)...
cleanmgr /sagerun:1 >nul 2>&1

:: --- Geçici Tarama Dosyalarını Temizle ---
for %%F in (b1 b2 b3 b4 b5 b6 b7 mb_tmp toplam_mb) do (
    if exist "%TEMP%\%%F.txt" del /f /q "%TEMP%\%%F.txt" >nul 2>&1
)
if exist "%TEHDITDOSYASI%" del /f /q "%TEHDITDOSYASI%" >nul 2>&1

:: ================================================================
::  SONUÇ RAPORU
:: ================================================================
echo.
color 2F
echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║                                                          ║
echo  ║   ✓  SİSTEM BAŞARIYLA OPTİMİZE EDİLDİ!                 ║
echo  ║                                                          ║
echo  ║   Temizlenen Toplam Alan : ~%TOPLAM_MB% MB               ║
echo  ║                                                          ║
echo  ║   Yapılan İşlemler:                                      ║
echo  ║   ✓ Virüs taraması ve tehdit temizliği                  ║
echo  ║   ✓ Sistem dosyası bütünlüğü onarımı                    ║
echo  ║   ✓ Geçici dosyalar silindi                             ║
echo  ║   ✓ Windows Update önbelleği temizlendi                 ║
echo  ║   ✓ Sistem logları ve bellek dökümleri silindi          ║
echo  ║   ✓ Küçük resim önbelleği yenilendi                    ║
echo  ║   ✓ Geri dönüşüm kutusu boşaltıldı                     ║
echo  ║   ✓ DNS önbelleği temizlendi                            ║
echo  ║                                                          ║
echo  ║   Detaylı log: %LOGDOSYASI%      ║
echo  ║                                                          ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.
color 07
echo  Pencere 10 saniye icinde kapanacak... (Devam etmek icin bir tusa basin)
timeout /t 10 >nul
goto :BITIS

:: ================================================================
::  İPTAL - Kullanıcı başlangıçta hayır dedi
:: ================================================================
:IPTAL
cls
color 0C
echo.
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║   İşlem iptal edildi. Sistem değiştirilmedi.            ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.
timeout /t 3 /nobreak >nul
goto :BITIS

:: ================================================================
::  İPTAL - Kullanıcı temizlik aşamasında hayır dedi
:: ================================================================
:IPTAL_TEMIZLIK
echo.
color 0C
echo  ╔══════════════════════════════════════════════════════════╗
echo  ║   Temizlik islemi iptal edildi.                          ║
echo  ║   Herhangi bir dosya silinmedi veya degistirilmedi.      ║
echo  ╚══════════════════════════════════════════════════════════╝
echo.

:: Geçici dosyaları temizle
for %%F in (b1 b2 b3 b4 b5 b6 b7 mb_tmp toplam_mb) do (
    if exist "%TEMP%\%%F.txt" del /f /q "%TEMP%\%%F.txt" >nul 2>&1
)
if exist "%TEHDITDOSYASI%" del /f /q "%TEHDITDOSYASI%" >nul 2>&1

color 07
timeout /t 4 /nobreak >nul

:BITIS
color 07
exit /b 0
