# RHCE Exam Lab - 중지 (진행상황 유지)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Write-Host "컨테이너 중지 중... (데이터/진행상황은 유지)" -ForegroundColor Yellow
docker compose stop
Write-Host "중지 완료. 다시 시작: docker compose start  또는  ./scripts/start.ps1" -ForegroundColor Green
