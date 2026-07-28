<#
.SYNOPSIS
    KlioAI ekranlarini bagli Android cihazdan yakalar (UI review icin).

.DESCRIPTION
    Telefonda uygulamayi gezerken her ekranda Enter'a basarsin, script o anki
    ekrani PNG olarak kaydeder. Isteige bagli kisa bir etiket yazarsan dosya
    adina eklenir; boylece inceleyen taraf hangi ekranin ne oldugunu bilir.

    Ciktilar varsayilan olarak repo icindeki ui-review/<zaman-damgasi>/ altina
    yazilir. Bu klasor .gitignore'da - ekran goruntuleri commit EDILMEZ.

.PARAMETER OutputDir
    Ciktilarin yazilacagi klasor. Bos birakilirsa ui-review/<timestamp> kullanilir.

.PARAMETER Interval
    Enter beklemek yerine belirli araliklarla otomatik yakalar. Elini
    klavyeye goturmeden gezmek istersen kullan (fazladan kare uretir).

.PARAMETER IntervalSeconds
    -Interval modunda kareler arasi saniye. Varsayilan 3.

.PARAMETER MaxWidth
    Kaydedilen PNG'nin maksimum genisligi (piksel). Varsayilan 540 - inceleme
    icin fazlasiyla yeterli ve dosyalar ~10x kucuk olur. 0 = kucultme yok.

.EXAMPLE
    pwsh -File scripts/capture-app-screens.ps1
    Enter'a bas -> ekran yakalanir. Etiket sor, bos gecebilirsin. q + Enter = cikis.

.EXAMPLE
    pwsh -File scripts/capture-app-screens.ps1 -Interval -IntervalSeconds 4
    4 saniyede bir otomatik yakalar. Ctrl+C ile durdurursun.
#>
param(
    [string]$OutputDir = "",
    [string]$AdbPath = "",
    [switch]$Interval,
    [int]$IntervalSeconds = 3,
    [int]$MaxWidth = 540,
    [int]$MaxShots = 300
)

$ErrorActionPreference = "Stop"

function Resolve-Adb {
    param([string]$Explicit)

    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "adb bulunamadi: $Explicit" }
        return $Explicit
    }

    $onPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:ANDROID_HOME\platform-tools\adb.exe",
        "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }

    throw "adb bulunamadi. -AdbPath ile tam yolu ver."
}

function Get-ConnectedDevice {
    param([string]$Adb)

    $lines = & $Adb devices 2>$null
    $devices = @()
    foreach ($line in $lines) {
        if ($line -match '^(\S+)\s+device$') { $devices += $Matches[1] }
    }

    if ($devices.Count -eq 0) {
        throw "Bagli cihaz yok. USB'yi tak, telefonda 'USB hata ayiklama' iznini onayla."
    }
    if ($devices.Count -gt 1) {
        Write-Host "Birden fazla cihaz bagli, ilki kullanilacak: $($devices[0])" -ForegroundColor Yellow
    }
    return $devices[0]
}

# adb exec-out ham PNG byte'lari verir; PowerShell'in pipeline'i metne cevirmesin
# diye cmd /c ile dogrudan dosyaya yonlendiriyoruz (Windows'ta en guvenli yol).
function Save-Screenshot {
    param([string]$Adb, [string]$Serial, [string]$Path)

    $cmd = "`"$Adb`" -s $Serial exec-out screencap -p > `"$Path`""
    cmd.exe /c $cmd | Out-Null

    if (-not (Test-Path $Path)) { return $false }
    if ((Get-Item $Path).Length -lt 1024) {
        Remove-Item $Path -Force -ErrorAction SilentlyContinue
        return $false
    }
    return $true
}

function Resize-Screenshot {
    param([string]$Path, [int]$TargetWidth)

    if ($TargetWidth -le 0) { return }

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $source = [System.Drawing.Image]::FromFile($Path)
        try {
            if ($source.Width -le $TargetWidth) { return }

            $ratio = $TargetWidth / $source.Width
            $targetHeight = [int][Math]::Round($source.Height * $ratio)
            $resized = New-Object System.Drawing.Bitmap $TargetWidth, $targetHeight
            $graphics = [System.Drawing.Graphics]::FromImage($resized)
            $graphics.InterpolationMode =
                [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($source, 0, 0, $TargetWidth, $targetHeight)
            $graphics.Dispose()

            $temp = "$Path.tmp"
            $resized.Save($temp, [System.Drawing.Imaging.ImageFormat]::Png)
            $resized.Dispose()
            $source.Dispose()
            $source = $null

            Move-Item $temp $Path -Force
        } finally {
            if ($source) { $source.Dispose() }
        }
    } catch {
        # Kucultme basarisiz olursa tam boy PNG kalir - inceleme yine yapilir.
        Write-Host "  (kucultme atlandi: $($_.Exception.Message))" -ForegroundColor DarkGray
    }
}

function Format-Label {
    param([string]$Raw)

    $clean = ($Raw -replace '[^\w\s-]', '').Trim() -replace '\s+', '-'
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    return $clean.ToLowerInvariant()
}

$adb = Resolve-Adb -Explicit $AdbPath
$serial = Get-ConnectedDevice -Adb $adb
$model = (& $adb -s $serial shell getprop ro.product.model 2>$null).Trim()

if (-not $OutputDir) {
    $stamp = Get-Date -Format "yyyy-MM-dd_HHmm"
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $OutputDir = Join-Path $repoRoot "ui-review/$stamp"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host ""
Write-Host "KlioAI ekran yakalama" -ForegroundColor Cyan
Write-Host "  cihaz  : $model ($serial)"
Write-Host "  klasor : $OutputDir"
Write-Host "  genislik: $(if ($MaxWidth -gt 0) { "${MaxWidth}px" } else { 'tam boy' })"
Write-Host ""

$index = 0

if ($Interval) {
    Write-Host "Otomatik mod: $IntervalSeconds saniyede bir yakalanacak." -ForegroundColor Yellow
    Write-Host "Telefonda uygulamayi gez. Durdurmak icin Ctrl+C." -ForegroundColor Yellow
    Write-Host ""

    while ($index -lt $MaxShots) {
        Start-Sleep -Seconds $IntervalSeconds
        $index++
        $name = "{0:D2}.png" -f $index
        $path = Join-Path $OutputDir $name

        if (Save-Screenshot -Adb $adb -Serial $serial -Path $path) {
            Resize-Screenshot -Path $path -TargetWidth $MaxWidth
            Write-Host "  [$index] $name" -ForegroundColor Green
        } else {
            $index--
            Write-Host "  yakalama basarisiz, tekrar deneniyor..." -ForegroundColor Red
        }
    }
} else {
    Write-Host "Telefonda incelemek istedigin ekrana gel, sonra buraya Enter." -ForegroundColor Yellow
    Write-Host "Cikmak icin: q + Enter" -ForegroundColor Yellow
    Write-Host ""

    while ($index -lt $MaxShots) {
        $answer = Read-Host "Enter = yakala (veya kisa etiket: 'onboarding-dil-secimi')"
        if ($answer -eq 'q') { break }

        $index++
        $label = Format-Label -Raw $answer
        $name = if ($label) { "{0:D2}_{1}.png" -f $index, $label } else { "{0:D2}.png" -f $index }
        $path = Join-Path $OutputDir $name

        if (Save-Screenshot -Adb $adb -Serial $serial -Path $path) {
            Resize-Screenshot -Path $path -TargetWidth $MaxWidth
            $sizeKb = [int]((Get-Item $path).Length / 1KB)
            Write-Host "  kaydedildi: $name (${sizeKb}KB)" -ForegroundColor Green
        } else {
            $index--
            Write-Host "  yakalanamadi - telefon ekrani acik mi?" -ForegroundColor Red
        }
    }
}

$count = (Get-ChildItem $OutputDir -Filter *.png -ErrorAction SilentlyContinue).Count
Write-Host ""
Write-Host "Bitti. $count ekran kaydedildi:" -ForegroundColor Cyan
Write-Host "  $OutputDir"
Write-Host ""
Write-Host "Simdi Claude'a soyle: 'ui-review/<klasor> icindeki ekranlari incele'" -ForegroundColor Cyan
