#!/bin/bash
# rhce-reset-all : 시험 환경을 "완전히 처음 상태"로 되돌린다. (새 시험 시작)
#   - control 작업 디렉토리(/home/greg/ansible) 전체 삭제 후 빈 디렉토리로 재생성
#     (내가 만든 모든 플레이북/인벤토리/롤/vault + vim 스왑파일(.swp) 등 잔여물 포함)
#   - 관리 노드(node1~5)에 적용된 17문제 결과 상태를 전부 원복
# 사용법:  rhce-reset-all   (확인 프롬프트) |  rhce-reset-all -y  (묻지 않고 실행)
AB=/home/greg/ansible
G="\e[32m"; R="\e[31m"; Y="\e[33m"; C="\e[36m"; N="\e[0m"

YES=0
[ "$1" = "-y" ] || [ "$1" = "--yes" ] && YES=1

echo -e "${Y}⚠  완전 초기화${N} — 다음을 모두 되돌립니다:"
echo "   • $AB 안의 모든 파일 삭제 (플레이북/인벤토리/롤/vault/스왑파일 전부)"
echo "   • node1~5 의 17문제 결과 상태 원복 (repo/패키지/cron/사용자/issue/webdev 등)"
if [ "$YES" != 1 ]; then
  printf "정말 진행할까요? 되돌릴 수 없습니다. [yes/N]: "
  read ans
  case "$ans" in yes|YES|y|Y) ;; *) echo "취소했습니다."; exit 0;; esac
fi

echo "========================================================"
echo -e " ${C}RHCE 완전 초기화 시작${N} - $(date '+%F %T')"
echo "========================================================"

# 1) 모든 노드 상태 원복 (rhce-reset all 재사용)
if command -v rhce-reset >/dev/null 2>&1; then
  rhce-reset all | sed 's/^/  /'
else
  echo -e "  ${R}[경고]${N} rhce-reset 을 찾을 수 없어 노드 상태 원복을 건너뜁니다."
fi

# 2) control 작업 디렉토리 통째로 비우기 (숨김파일·스왑파일 포함)
if [ -d "$AB" ]; then
  find "$AB" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
  echo -e "  ${G}[초기화]${N} $AB 안의 모든 파일/디렉토리 삭제 (스왑파일 포함)"
else
  mkdir -p "$AB"
  echo -e "  ${G}[초기화]${N} $AB 디렉토리 새로 생성"
fi
chown greg:greg "$AB" 2>/dev/null

# 3) 홈 디렉토리에 남은 vim 스왑/임시 잔여물도 정리
find /home/greg -maxdepth 3 -name '.*.sw[a-p]' -delete 2>/dev/null

echo "========================================================"
echo -e " ${G}완전 초기화 완료.${N}  이제 Q1(인벤토리+ansible.cfg)부터 새로 시작하세요."
echo -e " 채점: ${C}rhce-grade${N}   |   특정 문제 초기화: ${C}rhce-reset <번호>${N}"
echo "========================================================"
