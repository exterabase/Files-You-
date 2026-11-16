# Подготовка проекта к сборке под Windows. Запускать из PowerShell:
#   powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

function Need($cmd, $hint) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Не найден '$cmd'. $hint" }
}
function Run($block) {
    & $block
    if ($LASTEXITCODE -ne 0) { throw "Команда завершилась с кодом $LASTEXITCODE" }
}

Need flutter 'Установите Flutter SDK и добавьте flutter\bin в PATH.'
Need cargo   'Установите Rust через rustup (https://rustup.rs).'
Need rustup  'Установите Rust через rustup (https://rustup.rs).'

foreach ($f in 'assets\fonts\Disket-Mono-Regular.ttf', 'assets\fonts\Disket-Mono-Bold.ttf', 'assets\icon.png') {
    if (-not (Test-Path $f)) { throw "Нет файла $f (см. README, раздел «Шрифт и иконка»)." }
}

# 1. Платформа Android
if (-not (Test-Path android)) {
    Run { flutter create --platforms=android --org com.filesyou --project-name files_you . }
}

# 2. Манифест: доступ ко всем файлам, интернет, http, название
$m = 'android\app\src\main\AndroidManifest.xml'
$x = [IO.File]::ReadAllText((Resolve-Path $m))
if ($x -notmatch 'MANAGE_EXTERNAL_STORAGE') {
    $perm = '<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>' + "`n    " +
            '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>' + "`n    " +
            '<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>' + "`n    " +
            '<uses-permission android:name="android.permission.INTERNET"/>' + "`n    "
    $x = $x.Replace('<application', $perm + '<application android:usesCleartextTraffic="true"')
    $x = [regex]::Replace($x, 'android:label="[^"]*"', 'android:label="Files You"', 1)
    [IO.File]::WriteAllText((Resolve-Path $m), $x, (New-Object Text.UTF8Encoding $false))
}

# 3. Поиск NDK
if (-not $env:ANDROID_NDK_HOME) {
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
    $ndk = Get-ChildItem "$sdk\ndk" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $ndk) { throw "NDK не найден в $sdk\ndk. Установите его в Android Studio: SDK Manager -> SDK Tools -> NDK (Side by side)." }
    $env:ANDROID_NDK_HOME = $ndk.FullName
}
Write-Host "NDK: $env:ANDROID_NDK_HOME"

# 4. Rust-библиотека
Run { rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android }
if (-not (Get-Command cargo-ndk -ErrorAction SilentlyContinue)) { Run { cargo install cargo-ndk } }
Push-Location rust
try { Run { cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o ..\android\app\src\main\jniLibs build --release } }
finally { Pop-Location }

# 5. Зависимости Flutter и иконка приложения
Run { flutter pub get }
Run { dart run flutter_launcher_icons }

Write-Host "`nГотово. Соберите APK: flutter build apk --release"
