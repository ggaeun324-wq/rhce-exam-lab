# RHCE Exam Lab - 시작 스크립트
# 사용법: 우클릭 > PowerShell로 실행  또는  ./scripts/start.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host "== RHCE Exam Lab 시작 ==" -ForegroundColor Cyan

# 1) Docker 데몬 확인
docker ps *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] Docker 데몬에 연결할 수 없습니다. Docker Desktop을 먼저 실행하세요." -ForegroundColor Red
    exit 1
}

# 2) 베이스/노드 이미지 빌드
Write-Host "[1/3] 베이스 + 노드 이미지 빌드..." -ForegroundColor Yellow
docker build -t rhce-lab-base:latest -f Dockerfile.base .
if ($LASTEXITCODE -ne 0) { Write-Host "베이스 빌드 실패" -ForegroundColor Red; exit 1 }
docker build -t rhce-lab-node:latest -f Dockerfile.node .
if ($LASTEXITCODE -ne 0) { Write-Host "노드 빌드 실패" -ForegroundColor Red; exit 1 }

# 3) 전체 스택 기동 (ctrl/repo/portal 빌드 포함)
Write-Host "[2/3] 컨테이너 빌드 및 기동..." -ForegroundColor Yellow
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { Write-Host "compose up 실패" -ForegroundColor Red; exit 1 }

Write-Host "[3/3] 완료!" -ForegroundColor Green
Write-Host ""
Write-Host "  시험 포털 :  http://localhost:8080" -ForegroundColor Cyan
Write-Host "  시작 화면 =  외부 터미널(foundation). 여기서  ssh admin@control  로 접속."
Write-Host "  control node에서 문제를 풀고,  rhce-grade  로 채점하세요."
Write-Host "  관리노드(node1~5)는 control node에서 SSH로 접속(무암호, 사전배포)."
Write-Host ""
Write-Host "  중지  : ./scripts/stop.ps1"
Write-Host "  초기화: ./scripts/reset.ps1   (모든 진행상황 삭제 후 새 시험)"
