#!/bin/bash
# 노드별 baseline 상태 구성 (systemd oneshot 으로 부팅 시 실행).
#
# dev 노드(node1): 실제 EX294 시험처럼 httpd 가 미리 설치+구동되어 있어야 한다.
#   Q12(webcontent) 요구사항은 "dev 노드의 /webdev 를 브라우징하면 'Development' 가
#   출력되어야 한다" 인데, 문제 지문은 httpd 설치/기동을 요구하지 않는다(표준 정답 관례).
#   즉 응시자 플레이북은 디렉터리/권한(2775)/심볼릭링크/index.html/SELinux 컨텍스트만
#   구성하고, 웹서버는 이미 떠 있다고 전제한다. 따라서 dev 노드는 httpd 를 baseline 으로 켠다.
set +e
H=$(hostname -s)

if [ "$H" = "node1" ]; then
    # 이미지에 httpd 가 없으면 설치 시도(빌드시 설치되지만 안전차원)
    command -v httpd >/dev/null 2>&1 || dnf -y install httpd >/dev/null 2>&1
    systemctl enable --now httpd >/dev/null 2>&1
fi
