# RHCE Exam Lab - 초기화 (컨테이너 삭제 후 새 시험 상태로)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Write-Host "모든 컨테이너를 삭제하고 초기 상태로 되돌립니다." -ForegroundColor Yellow
docker compose down -v
Write-Host "초기화 완료. 새로 시작하려면 ./scripts/start.ps1 실행" -ForegroundColor Green
