# 编译 java/dualnet/*.java 为 dualnet/tools/label.dex
# 用法: powershell -ExecutionPolicy Bypass -File build/build-dex.ps1
param(
    [string]$AndroidJar = $env:ANDROID_JAR,
    [string]$D8 = $env:D8
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

if (-not $AndroidJar -or -not $D8) {
    $sdk = $env:ANDROID_SDK_ROOT
    if (-not $sdk) { $sdk = $env:ANDROID_HOME }
    if (-not $sdk) { $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
    if (-not (Test-Path $sdk)) { throw "找不到 Android SDK，请设置 ANDROID_SDK_ROOT 或 ANDROID_JAR / D8" }

    if (-not $AndroidJar) {
        $platform = Get-ChildItem (Join-Path $sdk "platforms") -Directory |
                    Sort-Object { [int]($_.Name -replace '\D', '') } -Descending |
                    Select-Object -First 1
        $AndroidJar = Join-Path $platform.FullName "android.jar"
    }
    if (-not $D8) {
        $bt = Get-ChildItem (Join-Path $sdk "build-tools") -Directory |
              Sort-Object { [version]($_.Name) } -Descending |
              Select-Object -First 1
        $D8 = Join-Path $bt.FullName "d8.bat"
    }
}

$Classes = Join-Path $Root "build\classes"
$DexOut  = Join-Path $Root "build\dexout"
Remove-Item $Classes, $DexOut -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Classes, $DexOut | Out-Null

Write-Host "android.jar: $AndroidJar"
Write-Host "d8:          $D8"

$sources = Get-ChildItem (Join-Path $Root "java\dualnet\*.java") | ForEach-Object { $_.FullName }
& javac -nowarn -source 8 -target 8 -bootclasspath $AndroidJar -d $Classes @sources
if ($LASTEXITCODE -ne 0) { throw "javac 失败" }

$classFiles = Get-ChildItem $Classes -Recurse -Filter *.class | ForEach-Object { $_.FullName }
& $D8 --lib $AndroidJar --min-api 26 --output $DexOut @classFiles
if ($LASTEXITCODE -ne 0) { throw "d8 失败" }

$target = Join-Path $Root "dualnet\tools\label.dex"
Copy-Item (Join-Path $DexOut "classes.dex") $target -Force
Write-Host "生成: $target ($((Get-Item $target).Length) 字节)"
