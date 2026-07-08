#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Otomatik Sistem Bakim, Temizlik ve Optimizasyon Scripti
    Gelistirici: Windows SysAdmin / Cybersecurity uzmanina uygun standartlar
.DESCRIPTION
    4 asama: Virus taramasi, gereksiz dosya tespiti, kullanici onayi, temizlik.
.NOTES
    PowerShell 5.1+ | Windows 10/11 | Yonetici yetkisi zorunludur.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

# ──────────────────────────────────────────────
# YARDIMCI FONKSIYONLAR
# ──────────────────────────────────────────────

function Write-Header {
    param([string]$Metin)
    $cizgi = "=" * 60
    Write-Host ""
    Write-Host $cizgi -ForegroundColor Cyan
    Write-Host "  $Metin" -ForegroundColor Yellow
    Write-Host $cizgi -ForegroundColor Cyan
}

function Write-Adim {
    param([string]$Metin)
    Write-Host ""
    Write-Host "  >> $Metin" -ForegroundColor Green
}

function Write-Bilgi {
    param([string]$Metin)
    Write-Host "     $Metin" -ForegroundColor Gray
}

function Write-Uyari {
    param([string]$Metin)
    Write-Host "  [!] $Metin" -ForegroundColor Red
}

function Format-Boyut {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes Byte"
}

function Get-KlasorBoyutu {
    param([string]$Yol)
    if (-not (Test-Path $Yol)) { return 0 }
    try {
        return (Get-ChildItem -Path $Yol -Recurse -Force -File `
            -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    } catch { return 0 }
}

# ──────────────────────────────────────────────
# BASLIK EKRANI
# ──────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     WINDOWS SISTEM BAKIM & OPTIMIZASYON ARACI       ║" -ForegroundColor Cyan
Write-Host "  ║          Guclu | Guvenli | Interaktif                ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Tarih : $(Get-Date -Format 'dd.MM.yyyy HH:mm')" -ForegroundColor DarkGray
Write-Host "  Sistem: $env:COMPUTERNAME  |  Kullanici: $env:USERNAME" -ForegroundColor DarkGray
Write-Host ""

# Yonetici kontrolu (ek guvenlik)
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Uyari "Bu script YONETICI yetkisiyle calistirilmalidir!"
    Write-Uyari "Lutfen PowerShell'i 'Yonetici olarak calistir' secenegiyle acin."
    Read-Host "`n  Cikmak icin Enter'a basin"
    exit 1
}

# Log dosyasi hazirla
$logDosyasi = "$env:TEMP\SistemBakim_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $logDosyasi -Append -NoClobber | Out-Null

# ──────────────────────────────────────────────
# AŞAMA 1: SİSTEM VE VİRÜS TARAMASI
# ──────────────────────────────────────────────

Write-Header "ASAMA 1/4 — SISTEM VE VIRUS TARAMASI"

# --- 1A: Windows Defender Hizli Tarama ---
Write-Adim "Windows Defender hizli taramasi baslatiliyor..."

$defenderYol = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
$tehditSayisi = 0

if (Test-Path $defenderYol) {
    Write-Bilgi "Tarama devam ediyor, lutfen bekleyin..."
    $defProc = Start-Process -FilePath $defenderYol `
        -ArgumentList "-Scan -ScanType 1" `
        -WindowStyle Hidden -PassThru -Wait

    # Defender bulgu kontrolu (MpThreatDetection)
    try {
        $tehditler = Get-MpThreatDetection -ErrorAction Stop
        $tehditSayisi = ($tehditler | Measure-Object).Count
        if ($tehditSayisi -gt 0) {
            Write-Uyari "$tehditSayisi adet tehdit tespit edildi!"
            $tehditler | ForEach-Object {
                Write-Bilgi "Tehdit: $($_.ThreatName) | Dosya: $($_.Resources -join ', ')"
            }
        } else {
            Write-Bilgi "Virus taramasi temiz — tehdit bulunamadi."
        }
    } catch {
        Write-Bilgi "Defender tehdit sorgulama atildi (modul yok), tarama cikis kodu: $($defProc.ExitCode)"
    }
} else {
    Write-Uyari "Windows Defender bulunamadi, tarama atlaniyor."
}

# --- 1B: SFC Taramasi ---
Write-Adim "SFC sistem dosyasi denetimi baslatiliyor (arka plan)..."
$sfcProc = Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" `
    -WindowStyle Hidden -PassThru
Write-Bilgi "SFC arka planda calisiyor (PID: $($sfcProc.Id))..."

# --- 1C: DISM Taramasi ---
Write-Adim "DISM Windows goruntu saglik kontrolu baslatiliyor (arka plan)..."
$dismProc = Start-Process -FilePath "dism.exe" `
    -ArgumentList "/Online /Cleanup-Image /CheckHealth" `
    -WindowStyle Hidden -PassThru
Write-Bilgi "DISM arka planda calisiyor (PID: $($dismProc.Id))..."

# SFC ve DISM bitmesini bekle
Write-Adim "SFC ve DISM tamamlanmasi bekleniyor..."
$sfcProc  | Wait-Process -Timeout 600 -ErrorAction SilentlyContinue
$dismProc | Wait-Process -Timeout 300 -ErrorAction SilentlyContinue

# SFC sonuc analizi
$sfcLog = "$env:windir\Logs\CBS\CBS.log"
$sfcSorun = $false
if (Test-Path $sfcLog) {
    $sfcIcerik = Get-Content $sfcLog -Tail 50 -ErrorAction SilentlyContinue
    if ($sfcIcerik -match "repaired|corrupt|could not") { $sfcSorun = $true }
}
Write-Bilgi "SFC tamamlandi. Sorun tespit edildi: $(if($sfcSorun){'EVET - Onarım denendi'}else{'Hayir'})"
Write-Bilgi "DISM tamamlandi. Cikis kodu: $($dismProc.ExitCode)"

# ──────────────────────────────────────────────
# AŞAMA 2: GEREKSİZ DOSYA TESPİTİ
# ──────────────────────────────────────────────

Write-Header "ASAMA 2/4 — PERFORMANS DARBOGAZI & GEREKSIZ DOSYA TESPITI"

Write-Adim "Temizlenebilecek konumlar taranıyor..."

# Taranacak konumlar listesi
$konumlar = @{
    "Sistem Temp Klasoru"              = $env:SystemRoot + "\Temp"
    "Kullanici Temp Klasoru"           = $env:TEMP
    "Prefetch Dosyalari"               = $env:SystemRoot + "\Prefetch"
    "Windows Update Onbellegi"         = $env:SystemRoot + "\SoftwareDistribution\Download"
    "Sistem Log Dosyalari"             = $env:SystemRoot + "\Logs"
    "Kullanici Yerel Uygulama Onbel."  = $env:LOCALAPPDATA + "\Temp"
    "Windows Hata Raporlari"           = $env:LOCALAPPDATA + "\Microsoft\Windows\WER"
    "Thumbnail Onbellegi DB"           = $env:LOCALAPPDATA + "\Microsoft\Windows\Explorer"
    "Cokme Dokuleri (MiniDump)"        = $env:SystemRoot + "\Minidump"
    "Bellek Dokumu (Memory.dmp)"       = $env:SystemRoot
}

$toplamBoyut = 0L
$konumSonuclari = [ordered]@{}

foreach ($konum in $konumlar.GetEnumerator()) {
    $boyut = 0L

    if ($konum.Key -eq "Bellek Dokumu (Memory.dmp)") {
        # Sadece memory.dmp dosyasini kontrol et
        $dmpYol = Join-Path $konum.Value "memory.dmp"
        if (Test-Path $dmpYol) {
            $boyut = (Get-Item $dmpYol -ErrorAction SilentlyContinue).Length
        }
    } elseif ($konum.Key -eq "Sistem Log Dosyalari") {
        # Sadece *.log dosyalarini say
        if (Test-Path $konum.Value) {
            $boyut = (Get-ChildItem -Path $konum.Value -Recurse -Force -Filter "*.log" `
                -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        }
    } else {
        $boyut = Get-KlasorBoyutu -Yol $konum.Value
    }

    $boyut = if ($null -eq $boyut) { 0L } else { [long]$boyut }
    $konumSonuclari[$konum.Key] = @{ Yol = $konum.Value; Boyut = $boyut }
    $toplamBoyut += $boyut

    $boyutStr = Format-Boyut -Bytes $boyut
    $durum = if ($boyut -gt 0) { "[$boyutStr]" } else { "[Bos/Yok]" }
    Write-Bilgi "$($konum.Key.PadRight(40)) $durum"
}

Write-Host ""
Write-Host "  Toplam tespit edilen gereksiz dosya: " -NoNewline -ForegroundColor White
Write-Host (Format-Boyut -Bytes $toplamBoyut) -ForegroundColor Yellow

# ──────────────────────────────────────────────
# AŞAMA 3: İNTERAKTİF KULLANICI ONAYI
# ──────────────────────────────────────────────

Write-Header "ASAMA 3/4 — TARAMA OZETI & KULLANICI ONAYI"

Write-Host ""
Write-Host "  ┌─────────────────────────────────────────────────┐" -ForegroundColor White
Write-Host "  │              TARAMA SONUCLARI                   │" -ForegroundColor White
Write-Host "  ├─────────────────────────────────────────────────┤" -ForegroundColor White
Write-Host ("  │  Virus / Zararlı Yazılım      : {0,-18}│" -f "$tehditSayisi adet tehdit") -ForegroundColor $(if($tehditSayisi -gt 0){"Red"}else{"Green"})
Write-Host ("  │  Sistem Dosyası Sorunu (SFC)  : {0,-18}│" -f $(if($sfcSorun){"Sorun var, onarıldı"}else{"Temiz"})) -ForegroundColor $(if($sfcSorun){"Yellow"}else{"Green"})
Write-Host ("  │  Gereksiz Dosya Toplami       : {0,-18}│" -f (Format-Boyut -Bytes $toplamBoyut)) -ForegroundColor Yellow
Write-Host "  └─────────────────────────────────────────────────┘" -ForegroundColor White
Write-Host ""
Write-Host "  Log dosyası kaydediliyor: $logDosyasi" -ForegroundColor DarkGray
Write-Host ""

$onay = Read-Host "  Bilgisayar hizlandirilsin ve tespit edilen sorunlar giderilsin mi? (E/H)"

if ($onay -notmatch "^[EeYy]") {
    Write-Host ""
    Write-Host "  İşlem iptal edildi. Sistem degistirilmedi." -ForegroundColor Cyan
    Stop-Transcript | Out-Null
    Read-Host "`n  Cikmak icin Enter'a basin"
    exit 0
}

# ──────────────────────────────────────────────
# AŞAMA 4: TEMİZLİK VE İMHA
# ──────────────────────────────────────────────

Write-Header "ASAMA 4/4 — TEMIZLIK & OPTIMIZASYON"

$temizlenenBoyut = 0L

# --- 4A: Defender Karantina / Temizleme ---
if ($tehditSayisi -gt 0) {
    Write-Adim "Tespit edilen tehditler karantinaya aliниyor..."
    Start-Process -FilePath $defenderYol `
        -ArgumentList "-RemoveDefinitions -DynamicSignatures" `
        -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
    # Tum karantina edilmis tehditleri temizle
    Start-Process -FilePath $defenderYol `
        -ArgumentList "-RemoveDefinitions -All" `
        -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
    Write-Bilgi "Defender karantina islemi tamamlandi."
}

# --- 4B: Klasor Temizlikleri ---
function Remove-SafeContent {
    param(
        [string]$Yol,
        [string]$Etiket,
        [string]$Filtre = "*",
        [switch]$SadeceLog,
        [switch]$SadeceDosya  # Alt klasorleri koru, sadece dosyalari sil
    )

    if (-not (Test-Path $Yol)) {
        Write-Bilgi "$Etiket — Konum bulunamadi, atlaniyor."
        return 0L
    }

    Write-Adim "$Etiket temizleniyor..."

    $silinen = 0L
    try {
        if ($SadeceDosya) {
            $dosyalar = Get-ChildItem -Path $Yol -Filter $Filtre -Force -File `
                -ErrorAction SilentlyContinue
        } else {
            $dosyalar = Get-ChildItem -Path $Yol -Filter $Filtre -Force `
                -ErrorAction SilentlyContinue
        }

        foreach ($ogre in $dosyalar) {
            try {
                $boyut = if ($ogre.PSIsContainer) {
                    (Get-ChildItem $ogre.FullName -Recurse -Force -File `
                        -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                } else {
                    $ogre.Length
                }
                $boyut = if ($null -eq $boyut) { 0L } else { [long]$boyut }

                Remove-Item -Path $ogre.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $silinen += $boyut
            } catch { <# Kilitli dosyalar sessizce atla #> }
        }
    } catch { <# Erisim hatasi sessizce atla #> }

    Write-Bilgi "Temizlendi: $(Format-Boyut -Bytes $silinen)"
    return $silinen
}

# Sistem Temp
$temizlenenBoyut += Remove-SafeContent `
    -Yol $env:SystemRoot\Temp -Etiket "Sistem Temp Klasoru" -SadeceDosya

# Kullanici Temp
$temizlenenBoyut += Remove-SafeContent `
    -Yol $env:TEMP -Etiket "Kullanici Temp Klasoru" -SadeceDosya

# Kullanici Yerel Temp
$temizlenenBoyut += Remove-SafeContent `
    -Yol "$env:LOCALAPPDATA\Temp" -Etiket "LocalAppData Temp" -SadeceDosya

# Prefetch (Windows yeniden olusturur)
$temizlenenBoyut += Remove-SafeContent `
    -Yol $env:SystemRoot\Prefetch -Etiket "Prefetch Dosyalari" `
    -Filtre "*.pf" -SadeceDosya

# Windows Update Download klasoru
Write-Adim "Windows Update onbellegi temizleniyor..."
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
$wuBoyut = Get-KlasorBoyutu -Yol "$env:SystemRoot\SoftwareDistribution\Download"
Remove-Item -Path "$env:SystemRoot\SoftwareDistribution\Download\*" `
    -Recurse -Force -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
$temizlenenBoyut += [long]$wuBoyut
Write-Bilgi "Temizlendi: $(Format-Boyut -Bytes $wuBoyut)"

# Windows Hata Raporlari
$temizlenenBoyut += Remove-SafeContent `
    -Yol "$env:LOCALAPPDATA\Microsoft\Windows\WER" `
    -Etiket "Windows Hata Raporlari"

# Cokme Dokuleri (MiniDump)
$temizlenenBoyut += Remove-SafeContent `
    -Yol $env:SystemRoot\Minidump -Etiket "MiniDump Cokme Dokuleri" `
    -Filtre "*.dmp" -SadeceDosya

# Bellek dokumu
$memDmp = "$env:SystemRoot\memory.dmp"
if (Test-Path $memDmp) {
    Write-Adim "Bellek dokumu (memory.dmp) siliniyor..."
    $dmpBoyut = (Get-Item $memDmp).Length
    Remove-Item $memDmp -Force -ErrorAction SilentlyContinue
    $temizlenenBoyut += [long]$dmpBoyut
    Write-Bilgi "Temizlendi: $(Format-Boyut -Bytes $dmpBoyut)"
}

# Thumbnail onbellegi (thumbcache_*.db)
Write-Adim "Thumbnail onbellegi temizleniyor..."
$thumbYol = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
$thumbBoyut = 0L
if (Test-Path $thumbYol) {
    Get-ChildItem -Path $thumbYol -Filter "thumbcache_*.db" -Force `
        -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $thumbBoyut += $_.Length
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        } catch { }
    }
}
$temizlenenBoyut += [long]$thumbBoyut
Write-Bilgi "Temizlendi: $(Format-Boyut -Bytes $thumbBoyut)"

# DNS Onbellegi Temizle (performans icin)
Write-Adim "DNS onbellegi temizleniyor..."
ipconfig /flushdns | Out-Null
Write-Bilgi "DNS onbellegi temizlendi."

# Recycle Bin temizle
Write-Adim "Geri Donusum Kutusu bosaltiliyor..."
try {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Bilgi "Geri Donusum Kutusu bosaltildi."
} catch { Write-Bilgi "Geri Donusum Kutusu atildi (zaten bos)." }

# DISM ile Windows goruntu onarimi (kullanici onayladiysa)
Write-Adim "DISM sistem goruntu onarimi calistiriliyor..."
$dismOnarim = Start-Process -FilePath "dism.exe" `
    -ArgumentList "/Online /Cleanup-Image /RestoreHealth" `
    -WindowStyle Hidden -PassThru -Wait
Write-Bilgi "DISM onarim cikis kodu: $($dismOnarim.ExitCode)"

# ──────────────────────────────────────────────
# SONUC RAPORU
# ──────────────────────────────────────────────

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║         SİSTEM BAŞARIYLA OPTİMİZE EDİLDİ!           ║" -ForegroundColor Green
Write-Host "  ╠══════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host ("  ║  Temizlenen Toplam Alan : {0,-31}║" -f (Format-Boyut -Bytes $temizlenenBoyut)) -ForegroundColor White
Write-Host ("  ║  Tehdit Sayisi          : {0,-31}║" -f "$tehditSayisi adet") -ForegroundColor White
Write-Host ("  ║  Islem Tarihi           : {0,-31}║" -f (Get-Date -Format "dd.MM.yyyy HH:mm")) -ForegroundColor White
Write-Host ("  ║  Log Dosyasi            : {0,-31}║" -f "(Temp klasorunde kayitli)") -ForegroundColor White
Write-Host "  ╚══════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  NOT: En iyi sonuc icin sistemi yeniden baslatmaniz onerilir." -ForegroundColor Yellow
Write-Host ""

Stop-Transcript | Out-Null

$yenidenBaslat = Read-Host "  Sistemi simdi yeniden baslatmak ister misiniz? (E/H)"
if ($yenidenBaslat -match "^[EeYy]") {
    Write-Host "  Sistem 10 saniye icinde yeniden baslatilacak..." -ForegroundColor Cyan
    shutdown /r /t 10 /c "Sistem Bakim Scripti - Optimizasyon tamamlandi"
} else {
    Write-Host "  Yeniden baslama atlandi. Her seyin iyi gitmesini dileriz!" -ForegroundColor Cyan
}

Read-Host "`n  Cikmak icin Enter'a basin"
