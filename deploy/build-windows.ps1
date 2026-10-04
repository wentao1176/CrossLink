$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runtimeDir = Join-Path $projectRoot '.tools\windows'
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
$env:PUB_CACHE = Join-Path $projectRoot '.tools\pub-cache'
$config = Join-Path $projectRoot 'config\client-build.json'
if (!(Test-Path -LiteralPath $config)) { throw 'Platform build configuration is missing.' }
$service = (Get-Content -Raw -LiteralPath $config | ConvertFrom-Json).CROSSLINK_API_URL
if (([Uri]$service).Scheme -ne 'https') { throw 'Native platform builds require HTTPS.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (!(Test-Path -LiteralPath $vswhere)) { throw 'Windows Visual Studio C++ tools are required.' }
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Windows Visual Studio C++ tools are required.' }
$flutter = Join-Path $runtimeDir 'flutter\bin\flutter.bat'
if (!(Test-Path -LiteralPath $flutter)) {
    if (!(Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git for Windows is required to bootstrap Flutter.' }
    & git clone --depth 1 --branch 3.47.6 https://github.com/flutter/flutter.git (Join-Path $runtimeDir 'flutter')
    if ($LASTEXITCODE) { throw 'Official Flutter checkout failed.' }
}
$sdkCommit = & git -C (Join-Path $runtimeDir 'flutter') rev-parse HEAD
if ($sdkCommit -ne '5fc346839b5d0eef006ed8404392afb4dfae428d') { throw 'Pinned Flutter SDK commit mismatch.' }
$env:PATH = (Split-Path $flutter) + ';' + $env:PATH
Push-Location (Join-Path $projectRoot 'client')
try {
    & $flutter config --enable-windows-desktop
    if ($LASTEXITCODE) { throw 'Flutter setup failed.' }
    & $flutter pub get
    if ($LASTEXITCODE) { throw 'Dependencies failed.' }
    & $flutter analyze
    if ($LASTEXITCODE) { throw 'Analysis failed.' }
    & $flutter test
    if ($LASTEXITCODE) { throw 'Tests failed.' }
    & $flutter build windows --release "--dart-define-from-file=$config"
    if ($LASTEXITCODE) { throw 'Windows build failed.' }
    $releaseDir = Join-Path $projectRoot 'client\build\windows\x64\runner\Release'
    $artifacts = Join-Path $projectRoot 'artifacts'
    New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
    $package = Join-Path $artifacts 'CrossLink-0.2.0-windows-x64.zip'
    Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $package -Force
    Get-FileHash -Algorithm SHA256 -LiteralPath $package
} finally { Pop-Location }
