<#
wo-bot-app 代码质量控制脚本
用法: powershell -ExecutionPolicy Bypass -File scripts/quality_check.ps1

检查项:
  1) dart analyze    — 静态检查（要求 0 issues）
  2) dart format     — 代码格式合规（--set-exit-if-changed）
  3) flutter test    — 单元/组件测试全部通过

退出码: 0 = 通过, 1 = 未通过
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 本地环境：flutter.bat 损坏时直接用 dart-sdk 运行 flutter_tools.snapshot
$dart = 'D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe'
$flutterSnapshot = 'D:\Flutter\flutter\bin\cache\flutter_tools.snapshot'
if (-not (Test-Path $dart)) {
  # 标准 flutter 环境（CI 或正常安装）
  $dart = 'flutter'
  $flutterSnapshot = $null
}

# 清理 flutter 工具残留（本地环境避免卡在 git fetch）
Get-Process dart,git -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-Item 'D:\Flutter\flutter\bin\cache\lockfile' -Force -ErrorAction SilentlyContinue

$failed = $false

Write-Host "`n==> [1/3] dart analyze (静态检查)" -ForegroundColor Cyan
& $dart analyze lib test
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host "`n==> [2/3] dart format (格式合规)" -ForegroundColor Cyan
& $dart format --output=none --set-exit-if-changed lib test
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host "`n==> [3/3] flutter test (单元/组件测试)" -ForegroundColor Cyan
if ($flutterSnapshot) {
  & $dart $flutterSnapshot test
} else {
  & flutter test
}
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host ""
if ($failed) {
  Write-Host "❌ 质量控制未通过，请修复上述问题后重试。" -ForegroundColor Red
  exit 1
}
Write-Host "✅ 质量控制全部通过（analyze 0 issues / format 合规 / 测试全绿）" -ForegroundColor Green
exit 0
