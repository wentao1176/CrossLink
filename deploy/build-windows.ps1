param(
    [ValidateSet('qa','production')][string]$Channel = 'production',
    [string]$BuildRoot,
    [string]$FlutterRoot,
    [string]$IsccPath,
    [switch]$PackageInstaller
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (!$BuildRoot) { $BuildRoot = Join-Path $projectRoot '.build' }
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
$buildDirectory = (Resolve-Path -LiteralPath $BuildRoot).Path
if (!$FlutterRoot) { $FlutterRoot = Join-Path $buildDirectory 'toolchain\flutter' }
$flutter = Join-Path $FlutterRoot 'bin\flutter.bat'
if (!(Test-Path -LiteralPath $flutter)) { throw 'Pinned Flutter SDK is required.' }
$sdkCommit = & git -C $FlutterRoot rev-parse HEAD
if ($LASTEXITCODE -or $sdkCommit -ne '5fc346839b5d0eef006ed8404392afb4dfae428d') { throw 'Pinned Flutter SDK commit mismatch.' }
$config = Join-Path $projectRoot "config\client-build-$Channel.json"
if (!(Test-Path -LiteralPath $config)) { throw 'Internal platform build configuration is missing.' }
$platform = Get-Content -Raw -LiteralPath $config | ConvertFrom-Json
if (([Uri]$platform.CROSSLINK_API_URL).Scheme -ne 'https' -or $platform.CROSSLINK_BUILD_CHANNEL -ne $Channel) { throw 'Build channel and HTTPS configuration must match.' }
$source = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'source.json') | ConvertFrom-Json
$versionText = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'client\pubspec.yaml')
if ($versionText -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$') { throw 'Invalid application version.' }
$version = $Matches[1]
$artifacts = Join-Path $buildDirectory "artifacts\$version\$Channel"
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
foreach ($cache in @('pub','test','tmp','nuget','nuget-http')) { New-Item -ItemType Directory -Force -Path (Join-Path $buildDirectory "cache\$cache") | Out-Null }
$env:PUB_CACHE = Join-Path $buildDirectory 'cache\pub'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$env:CROSSLINK_TEST_TMP = Join-Path $buildDirectory 'cache\test'
$env:NUGET_PACKAGES = Join-Path $buildDirectory 'cache\nuget'
$env:NUGET_HTTP_CACHE_PATH = Join-Path $buildDirectory 'cache\nuget-http'
$env:TEMP = Join-Path $buildDirectory 'cache\tmp'
$env:TMP = $env:TEMP
$env:CROSSLINK_BUILD_CHANNEL = $Channel
$env:CI = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:PATH = (Join-Path $FlutterRoot 'bin') + ';' + $env:PATH
Push-Location (Join-Path $projectRoot 'client')
try {
    & $flutter --no-version-check pub get --enforce-lockfile
    if ($LASTEXITCODE) { throw 'Locked dependencies failed.' }
    & $flutter --no-version-check analyze --no-pub
    if ($LASTEXITCODE) { throw 'Analysis failed.' }
    & $flutter --no-version-check test --no-pub
    if ($LASTEXITCODE) { throw 'Windows-host tests failed.' }
    & $flutter --no-version-check build windows --release --no-pub "--dart-define-from-file=$config"
    if ($LASTEXITCODE) { throw 'Windows build failed.' }
    $releaseDir = Join-Path $projectRoot 'client\build\windows\x64\runner\Release'
    if (!(Test-Path -LiteralPath (Join-Path $releaseDir 'crosslink.exe'))) { throw 'Release executable is missing.' }
    $suffix = if ($Channel -eq 'qa') { '-qa' } else { '' }
    $package = Join-Path $artifacts "CrossLink-$version-windows-x64$suffix.zip"
    Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $package -Force
    if ($PackageInstaller) {
        if (!$IsccPath -or !(Test-Path -LiteralPath $IsccPath)) { throw 'Inno Setup compiler is required for the installer; ZIP is ready.' }
        & $IsccPath "/DAppVersion=$version" "/DChannel=$Channel" "/DReleaseDir=$releaseDir" "/DOutputDir=$artifacts" (Join-Path $PSScriptRoot 'windows-installer.iss')
        if ($LASTEXITCODE) { throw 'Installer packaging failed; ZIP is ready.' }
    }
    $manifest = [ordered]@{version=$version;channel=$Channel;source_commit=$source.source_commit;flutter_commit=$sdkCommit;configuration_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $config).Hash.ToLowerInvariant();files=@()}
    foreach ($file in (Get-ChildItem -LiteralPath $artifacts -File | Where-Object Extension -in '.zip','.exe')) {
        $manifest.files += @{name=$file.Name;bytes=$file.Length;sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()}
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $artifacts 'windows-manifest.json') -Encoding utf8
    Write-Output "Windows $version $Channel artifacts ready: $artifacts"
} finally { Pop-Location }
