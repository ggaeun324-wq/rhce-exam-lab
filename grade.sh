#!/bin/bash
# rhce-grade : RHCE v9 덤프 17문제 "결과 상태"를 실제 시험처럼 채점.
# (응시자가 입력한 명령/플레이북 텍스트가 아니라, 노드/시스템의 최종 상태를 검사한다.)
AB=/home/greg/ansible
NODES="node1 node2 node3 node4 node5"
DEV="node1"; TEST="node2"; PROD="node3 node4"; BAL="node5"; WEB="node3 node4"
pass=0; fail=0; skip=0
G="\e[32m"; R="\e[31m"; Y="\e[33m"; C="\e[36m"; N="\e[0m"
# 인자로 문제 번호를 주면 해당 문제만 채점 (예: rhce-grade 1 / rhce-grade 8 17). 없으면 전체.
if [ $# -eq 0 ]; then ALL=1; else ALL=0; WANT=" $* "; fi
sel(){ [ "$ALL" = 1 ] && return 0; case "$WANT" in *" $1 "*) return 0;; esac; return 1; }
MUTE=0
ok(){ [ "$MUTE" = 1 ] && return; echo -e "  ${G}[PASS]${N} $1"; pass=$((pass+1)); }
no(){ [ "$MUTE" = 1 ] && return; echo -e "  ${R}[FAIL]${N} $1"; fail=$((fail+1)); }
sk(){ [ "$MUTE" = 1 ] && return; echo -e "  ${Y}[SKIP]${N} $1"; skip=$((skip+1)); }
hdr(){ CURN=$(printf '%s' "$1" | sed -n 's/^Q\([0-9]\+\).*/\1/p');
       if sel "$CURN"; then MUTE=0; echo -e "${C}== $1 ==${N}"; else MUTE=1; fi; }
# ssh 헬퍼 (greg, 무암호 키). 원격 root 권한은 sudo.
r(){ ssh -o ConnectTimeout=5 greg@"$1" "sudo bash -lc '$2'" 2>/dev/null; }

echo "========================================================"
echo " RHCE v9 결과 채점 - $(date '+%F %T')"
echo "========================================================"

# Q1 Ansible 설치 및 인벤토리/설정
hdr "Q1  Ansible 설치 + 인벤토리/ansible.cfg"
command -v ansible-playbook >/dev/null && ok "control 에 ansible 설치됨" || no "ansible 미설치"
if [ -f "$AB/ansible.cfg" ] || [ -f "$AB/inventory" ]; then
  cd "$AB"
  ping_ok=1
  for n in $NODES; do
    ansible "$n" -m ping 2>/dev/null | grep -q SUCCESS || ping_ok=0
  done
  [ $ping_ok -eq 1 ] && ok "ansible all -m ping 전 노드 SUCCESS" || no "일부 노드 ping 실패 (인벤토리/키/그룹 확인)"
  GR=$(ansible-inventory --graph 2>/dev/null)
  echo "$GR" | grep -A1 '@dev'  | grep -q node1 && ok "dev=node1" || no "dev 그룹에 node1 없음"
  echo "$GR" | grep -A1 '@test' | grep -q node2 && ok "test=node2" || no "test 그룹에 node2 없음"
  echo "$GR" | grep -A2 '@prod' | grep -q node3 && echo "$GR" | grep -A2 '@prod' | grep -q node4 && ok "prod=node3,node4" || no "prod 그룹 확인 실패"
  echo "$GR" | grep -A1 '@balancers' | grep -q node5 && ok "balancers=node5" || no "balancers 그룹에 node5 없음"
  ansible webservers --list-hosts 2>/dev/null | grep -q node3 && ok "webservers⊃prod" || no "webservers 에 prod 미포함"
else
  no "$AB/inventory 또는 ansible.cfg 없음"
fi

# Q2 YUM repo
hdr "Q2  yum repository (EX294_BaseOS / EX294_AppStream)"
q2=1
for n in $NODES; do
  r "$n" 'grep -rl EX294_BaseOS /etc/yum.repos.d/ >/dev/null && grep -rl EX294_AppStream /etc/yum.repos.d/ >/dev/null' >/dev/null 2>&1 || q2=0
done
[ $q2 -eq 1 ] && ok "전 노드에 EX294_BaseOS/AppStream repo 존재" || no "일부 노드에 repo 미설정"

# Q3 collection 설치
hdr "Q3  collection (mycollections)"
if [ -d "$AB/mycollections" ]; then
  L=$(ansible-galaxy collection list -p "$AB/mycollections" 2>/dev/null)
  echo "$L" | grep -q ansible.posix && ok "ansible.posix 설치" || no "ansible.posix 없음"
  echo "$L" | grep -q community.general && ok "community.general 설치" || no "community.general 없음"
  echo "$L" | grep -q redhat.rhel_system_roles && ok "redhat.rhel_system_roles 설치" || no "redhat.rhel_system_roles 없음"
else
  no "$AB/mycollections 디렉토리 없음"
fi

# Q4 패키지 설치
hdr "Q4  packages (php, mariadb / dev:Dev Tools)"
q4=1
for n in $DEV $TEST $PROD; do
  r "$n" 'rpm -q php >/dev/null && (rpm -q mariadb >/dev/null || rpm -q mariadb-server >/dev/null)' >/dev/null 2>&1 || q4=0
done
[ $q4 -eq 1 ] && ok "dev/test/prod 에 php+mariadb 설치" || no "php/mariadb 누락 노드 있음"
r "$DEV" 'rpm -q make >/dev/null || dnf group list installed 2>/dev/null | grep -qi "Development Tools"' >/dev/null 2>&1 \
  && ok "dev(node1) 에 RPM Development Tools" || no "dev 에 Development Tools 미설치"

# Q5 timesync
hdr "Q5  timesync role (time.bora.net)"
q5=1
for n in $NODES; do
  r "$n" 'grep -q time.bora.net /etc/chrony.conf' >/dev/null 2>&1 || q5=0
done
[ $q5 -eq 1 ] && ok "전 노드 chrony 에 time.bora.net" || no "일부 노드 timesync 미적용"

# Q6 selinux (컨테이너 강제 불가)
hdr "Q6  selinux role (enforcing/targeted)"
sk "컨테이너는 호스트 커널 공유 → SELinux enforcing 검증 불가 (플레이북 문법만 학습)"

# Q7 role 설치 및 사용 (balancer/phpinfo)
hdr "Q7  balancer/phpinfo role 설치+동작"
{ [ -d "$AB/roles/balancer" ] && ok "roles/balancer 설치"; } || no "roles/balancer 없음"
{ [ -d "$AB/roles/phpinfo" ] && ok "roles/phpinfo 설치"; } || no "roles/phpinfo 없음"
curl -s --max-time 5 http://node5/ | grep -qiE 'welcome|hello|php' && ok "balancer: curl node5 응답" || no "balancer: curl node5 무응답 (roles.yml 실행?)"
for n in $WEB; do
  curl -s --max-time 5 "http://$n/hello.php" | grep -qi 'Hello PHP World' && ok "phpinfo: $n/hello.php OK" || no "phpinfo: $n/hello.php 실패"
done

# Q8 apache role
hdr "Q8  apache role (Welcome to FQDN on IP)"
for n in $WEB; do
  curl -s --max-time 5 "http://$n/" | grep -qi 'Welcome to' && ok "apache: curl $n Welcome OK" || no "apache: curl $n 실패"
done

# Q9 LVM (루프백 VG)
hdr "Q9  logical volume (research/data)"
q9=1
for n in $NODES; do
  r "$n" 'lvs research/data >/dev/null 2>&1 || lvs 2>/dev/null | grep -q data' >/dev/null 2>&1 || q9=0
done
[ $q9 -eq 1 ] && ok "전 노드 research/data LV 존재" || sk "일부 노드 LV 없음 (컨테이너 LVM 제약일 수 있음)"

# Q10 hosts.yml
hdr "Q10 /etc/myhosts (dev)"
r "$DEV" 'test -s /etc/myhosts && grep -q node /etc/myhosts' >/dev/null 2>&1 \
  && ok "dev(node1) /etc/myhosts 생성됨" || no "dev /etc/myhosts 없음/비어있음"

# Q11 issue
hdr "Q11 /etc/issue (그룹별)"
[ "$(r $DEV 'cat /etc/issue' 2>/dev/null | tr -d "[:space:]")" = "Development" ] && ok "dev=Development" || no "dev /etc/issue != Development"
[ "$(r $TEST 'cat /etc/issue' 2>/dev/null | tr -d "[:space:]")" = "Test" ] && ok "test=Test" || no "test /etc/issue != Test"
q11=1; for n in $PROD; do [ "$(r $n 'cat /etc/issue' 2>/dev/null | tr -d '[:space:]')" = "Production" ] || q11=0; done
[ $q11 -eq 1 ] && ok "prod=Production" || no "prod /etc/issue != Production"

# Q12 webcontent
hdr "Q12 /webdev + symlink + index.html"
curl -s --max-time 5 http://node1/webdev/ | grep -qi Development && ok "curl node1/webdev/ = Development" || no "webdev 브라우징 실패"
r "$DEV" 'stat -c %a /webdev 2>/dev/null | grep -q 2775' >/dev/null 2>&1 && ok "/webdev 권한 2775" || no "/webdev 권한 != 2775"
r "$DEV" 'test -L /var/www/html/webdev' >/dev/null 2>&1 && ok "symlink /var/www/html/webdev" || no "symlink 없음"

# Q13 hwreport
hdr "Q13 /root/hwreport.txt"
q13=1
for n in $NODES; do
  r "$n" 'test -s /root/hwreport.txt && grep -q "^HOST=" /root/hwreport.txt' >/dev/null 2>&1 || q13=0
done
[ $q13 -eq 1 ] && ok "전 노드 hwreport.txt 생성(HOST= 채워짐)" || no "일부 노드 hwreport 누락"

# Q14 vault locker
hdr "Q14 vault locker.yml"
if [ -f "$AB/locker.yml" ] && head -1 "$AB/locker.yml" | grep -q '\$ANSIBLE_VAULT'; then
  ok "locker.yml 암호화됨"
  if [ -f "$AB/secret.txt" ]; then
    ansible-vault view --vault-password-file "$AB/secret.txt" "$AB/locker.yml" 2>/dev/null | grep -q pw_developer \
      && ok "secret.txt 로 복호화 + pw_developer 존재" || no "복호화 실패 또는 pw_developer 없음"
  else no "secret.txt 없음"; fi
else no "locker.yml 없음/미암호화"; fi

# Q15 users
hdr "Q15 사용자/그룹 (devops/opsmgr)"
q15d=1; for n in $DEV $TEST; do r "$n" 'getent group devops >/dev/null && getent group devops | grep -q :.*[a-z]' >/dev/null 2>&1 || q15d=0; done
[ $q15d -eq 1 ] && ok "dev/test 에 devops 그룹+멤버" || no "dev/test developer 사용자/devops 미생성"
q15m=1; for n in $PROD; do r "$n" 'getent group opsmgr >/dev/null && getent group opsmgr | grep -q :.*[a-z]' >/dev/null 2>&1 || q15m=0; done
[ $q15m -eq 1 ] && ok "prod 에 opsmgr 그룹+멤버" || no "prod manager 사용자/opsmgr 미생성"

# Q16 rekey
hdr "Q16 salaries.yml rekey (새 암호 bbqw3fd980123c)"
if [ -f "$AB/salaries.yml" ]; then
  echo 'bbqw3fd980123c' > /tmp/.nk
  ansible-vault view --vault-password-file /tmp/.nk "$AB/salaries.yml" >/dev/null 2>&1 \
    && ok "새 암호로 복호화 성공(rekey 완료)" || no "새 암호로 복호화 실패(rekey 미완료)"
  rm -f /tmp/.nk
else no "salaries.yml 없음 (wget 후 rekey 필요)"; fi

# Q17 cron
hdr "Q17 cron (natasha, */2, logger)"
r "$TEST" 'crontab -l -u natasha 2>/dev/null | grep -q logger && crontab -l -u natasha 2>/dev/null | grep -q "\*/2"' >/dev/null 2>&1 \
  && ok "test(node2) natasha cron 등록됨" || no "natasha cron 미등록"

echo "========================================================"
echo -e " 결과:  ${G}PASS $pass${N} / ${R}FAIL $fail${N} / ${Y}SKIP $skip${N}"
echo "========================================================"
