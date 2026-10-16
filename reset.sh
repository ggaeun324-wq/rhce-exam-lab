#!/bin/bash
# rhce-reset : 특정 문제(들)를 "처음 상태"로 되돌려 다시 풀 수 있게 한다.
#   - control 노드에 만들어진 해당 문제 플레이북/산출물 삭제
#   - 관리 노드(node1~5)에 적용된 결과 상태 원복
# 사용법:
#   rhce-reset 17          # 17번만 초기화
#   rhce-reset 7 8 12      # 여러 문제 초기화
#   rhce-reset all         # 전체 초기화(주의: 1번 인벤토리까지 삭제)
AB=/home/greg/ansible
NODES="node1 node2 node3 node4 node5"
DEV="node1"; TEST="node2"; PROD="node3 node4"; BAL="node5"; WEB="node3 node4"
G="\e[32m"; R="\e[31m"; Y="\e[33m"; C="\e[36m"; N="\e[0m"

if [ $# -eq 0 ]; then
  echo -e "${Y}사용법:${N} rhce-reset <문제번호...>   예) rhce-reset 17   |   rhce-reset 7 8   |   rhce-reset all"
  exit 1
fi
if [ "$1" = "all" ]; then
  WANT="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17"
else
  WANT="$*"
fi
# 7A/7B 는 7 로 통합 처리
WANT=$(echo " $WANT " | sed 's/7A/7/g; s/7B/7/g')

sel(){ case " $WANT " in *" $1 "*) return 0;; esac; return 1; }
# 원격 root 실행 헬퍼 (greg + sudo)
r(){ ssh -o ConnectTimeout=5 greg@"$1" "sudo bash -lc '$2'" >/dev/null 2>&1; }
done_msg(){ echo -e "  ${G}[초기화]${N} $1"; }
# 플레이북 파일 삭제 헬퍼: 확장자 없는 basename 을 주면 .yml/.yaml 양쪽을 지운다.
rmpb(){ for b in "$@"; do rm -f "$AB/$b.yml" "$AB/$b.yaml"; done; }

echo "========================================================"
echo -e " ${C}RHCE 초기화${N} - 대상 문제: $(echo $WANT | tr -s ' ')"
echo "========================================================"

# Q1 인벤토리/ansible.cfg  (주의: 모든 문제 토대)
if sel 1; then
  rm -f "$AB/inventory" "$AB/ansible.cfg" "$AB/hosts" "$AB/inventory.ini" "$AB/hosts.ini" 2>/dev/null
  done_msg "Q1: inventory / ansible.cfg 삭제 (다시 만들어야 다른 문제도 동작)"
fi

# Q2 yum repo
if sel 2; then
  rmpb yum_repo yumrepo repo
  for n in $NODES; do r "$n" 'rm -f /etc/yum.repos.d/*EX294* /etc/yum.repos.d/EX294*.repo'; done
  done_msg "Q2: yum_repo.yml + 전 노드 EX294 repo 삭제"
fi

# Q3 collection
if sel 3; then
  rm -rf "$AB/mycollections" "$AB/mycollection"
  rm -f "$AB/requirements.yml" "$AB/requirement.yml" "$AB/collections.yml"
  done_msg "Q3: mycollections + requirements.yml(설치용) 삭제"
fi

# Q4 packages
if sel 4; then
  rmpb packages package
  for n in $DEV $TEST $PROD; do
    r "$n" 'dnf remove -y php mariadb mariadb-server >/dev/null 2>&1; dnf group remove -y "RPM Development Tools" "Development Tools" >/dev/null 2>&1; true'
  done
  done_msg "Q4: packages.yml + dev/test/prod php·mariadb·Dev Tools 제거"
fi

# Q5 timesync
if sel 5; then
  rmpb timesync
  for n in $NODES; do r "$n" "sed -i '/time.bora.net/d' /etc/chrony.conf; systemctl restart chronyd 2>/dev/null; true"; done
  done_msg "Q5: timesync.yml + 전 노드 chrony time.bora.net 라인 제거"
fi

# Q6 selinux (노드 상태 없음)
if sel 6; then
  rmpb selinux
  done_msg "Q6: selinux.yml 삭제"
fi

# Q7 roles 설치+사용 (balancer/phpinfo)
if sel 7; then
  rm -rf "$AB/roles/balancer" "$AB/roles/phpinfo"
  rm -f "$AB/roles/requirements.yml" "$AB/roles/requirement.yml"
  rmpb roles role
  for n in $WEB $BAL; do
    r "$n" 'systemctl stop httpd haproxy 2>/dev/null; systemctl disable httpd haproxy 2>/dev/null; rm -rf /var/www/html/* /etc/haproxy/haproxy.cfg 2>/dev/null; true'
  done
  done_msg "Q7: roles/balancer·phpinfo + requirements.yml + roles.yml, web/balancer 서비스 원복"
fi

# Q8 apache role
if sel 8; then
  rm -rf "$AB/roles/apache"
  rmpb newrole
  for n in $WEB; do
    r "$n" 'systemctl stop httpd 2>/dev/null; systemctl disable httpd 2>/dev/null; rm -f /var/www/html/index.html 2>/dev/null; true'
  done
  done_msg "Q8: roles/apache + newrole.yml, web 노드 httpd/index.html 원복"
fi

# Q9 LVM  (WSL2 공유커널: 노드마다 고유 backing 경로로 research VG 재구축 → fact 손상 방지)
if sel 9; then
  rmpb lv
  # 각 노드가 자기 고유 경로(/var/lib/research-<host>.img)로 research VG 를 재구축한다.
  # setup-research-vg.sh 가 손상/잡음(Retrying metadata scan) VG 를 감지해 재생성하고,
  # devices 파일을 자기 PV 만 담게 하여 ansible 하드웨어 fact 수집이 깨지지 않게 한다.
  for nd in $NODES; do
    r "$nd" 'lvremove -fy research/data 2>/dev/null; dmsetup remove research-data 2>/dev/null; rm -rf /dev/research; rm -f /etc/lvm/cache/.cache; bash /usr/local/bin/setup-research-vg.sh 2>/dev/null; true'
  done
  done_msg "Q9: lv.yml 삭제 + research/data LV 제거 + 전 노드 research VG 정상화(고유 경로 재구축)"
fi

# Q10 hosts template
if sel 10; then
  rmpb hosts
  rm -f "$AB/hosts.j2"
  for n in $DEV; do r "$n" 'rm -f /etc/myhosts'; done
  done_msg "Q10: hosts.yml·hosts.j2 + dev /etc/myhosts 삭제"
fi

# Q11 /etc/issue
if sel 11; then
  rmpb issue
  for n in $NODES; do r "$n" "printf '\\\\S\\nKernel \\\\r on an \\\\m\\n' > /etc/issue"; done
  done_msg "Q11: issue.yml + 전 노드 /etc/issue 기본값 복원"
fi

# Q12 webcontent
if sel 12; then
  rmpb webcontent webcontents
  for n in $DEV; do r "$n" 'rm -rf /webdev /var/www/html/webdev 2>/dev/null; true'; done
  # dev 노드는 실제 시험처럼 httpd 가 baseline 으로 떠 있어야 브라우징 요건이 검증된다.
  for n in $DEV; do r "$n" 'systemctl enable --now httpd 2>/dev/null; true'; done
  done_msg "Q12: webcontent.yml + dev /webdev·심볼릭링크 삭제 (dev httpd baseline 유지)"
fi

# Q13 hwreport
if sel 13; then
  rmpb hwreport
  rm -f "$AB/hwreport.txt"
  for n in $NODES; do r "$n" 'rm -f /root/hwreport.txt'; done
  done_msg "Q13: hwreport.yml·hwreport.txt + 전 노드 /root/hwreport.txt 삭제"
fi

# Q14 vault locker
if sel 14; then
  rm -f "$AB/locker.yml" "$AB/locker.yaml" "$AB/secret.txt"
  done_msg "Q14: locker.yml·secret.txt 삭제"
fi

# Q15 users
if sel 15; then
  rmpb users user
  rm -f "$AB/user_list.yml" "$AB/user_list.yaml"
  for n in $DEV $TEST; do
    r "$n" 'for u in $(getent group devops 2>/dev/null | awk -F: "{print \$4}" | tr "," " "); do userdel -r "$u" 2>/dev/null; done; groupdel devops 2>/dev/null; true'
  done
  for n in $PROD; do
    r "$n" 'for u in $(getent group opsmgr 2>/dev/null | awk -F: "{print \$4}" | tr "," " "); do userdel -r "$u" 2>/dev/null; done; groupdel opsmgr 2>/dev/null; true'
  done
  done_msg "Q15: users.yml + devops/opsmgr 그룹·소속 사용자 삭제"
fi

# Q16 salaries rekey
if sel 16; then
  rm -f "$AB/salaries.yml" "$AB/salaries.yaml"
  done_msg "Q16: salaries.yml 삭제 (다시 wget 후 rekey)"
fi

# Q17 cron
if sel 17; then
  rmpb cron
  r "$TEST" 'crontab -r -u natasha 2>/dev/null; true'
  done_msg "Q17: cron.yml + node2 natasha crontab 삭제"
fi

echo "========================================================"
echo -e " ${G}초기화 완료.${N}  다시 풀고 'rhce-grade <번호>' 로 확인하세요."
echo "========================================================"
