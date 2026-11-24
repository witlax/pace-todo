# Windows 桌面端打包（需在 Windows 上执行）
#
# 用法：powershell -ExecutionPolicy Bypass -File scripts\build_windows.ps1
# 产物：dist\tasks-<版本>-windows-x64.zip
# 前提：已安装 Visual Studio 2022 的「使用 C++ 的桌面开发」与 Flutter Windows 支持。

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'app'
$dist = Join-Path $root 'dist'

Push-Location $app
try {
    $version = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value
    $semver = ($version -split '\+')[0]
    Write-Host "构建版本：$version"

    flutter pub get
    flutter build windows --release

    $out = Join-Path $app 'build\windows\x64\runner\Release'
    if (-not (Test-Path $out)) {
        throw "没有找到构建产物：$out（确认已启用 Windows 桌面支持）"
    }

    if (-not (Test-Path $dist)) { New-Item -ItemType Directory -Path $dist | Out-Null }
    $zip = Join-Path $dist "tasks-$semver-windows-x64.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $out '*') -DestinationPath $zip -CompressionLevel Optimal

    $size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Host "完成：$zip（$size MB）"
    Write-Host "解压后运行 tasks.exe。首次启动会在同目录生成数据文件。"
}
finally {
    Pop-Location
}
