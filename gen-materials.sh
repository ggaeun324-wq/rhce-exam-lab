#!/bin/bash
# materials 서버 콘텐츠 생성 (빌드 타임 실행)
# 3개 덤프가 wget/ansible-galaxy/ansible-vault 로 참조하는 파일들을 만든다.
set -x
M=/srv/materials
mkdir -p "$M" /tmp/coll

# --- RPM GPG key (Rocky). EX294 repo gpgcheck=1 통과용 ---
if [ -f /etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9 ]; then
  cp /etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-9 "$M/RPM-GPG-KEY-redhat-release"
else
  curl -fsSL -o "$M/RPM-GPG-KEY-redhat-release" https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9 || true
fi

# --- collection tarballs (덤프가 wget 하는 정확한 파일명으로 생성) ---
for c in ansible.posix:1.5.1 community.general:5.4.0 community.general:5.5.0; do
  ansible-galaxy collection download "$c" -p /tmp/coll --no-deps || echo "WARN: download failed $c"
done
find /tmp/coll -name '*.tar.gz' -exec cp -f {} "$M/" \; 2>/dev/null || true

# ansible.posix.firewalld 패치: 이 랩의 컨테이너 커널(WSL2)은 bridge netfilter 미지원이라
# 관리노드에서 firewalld 데몬이 뜨지 않는다. 응시자가 이 tarball 을 mycollections 에 설치하면
# role 내 firewalld(immediate) task 가 hard-fail 하므로, 서빙 tarball 자체를 패치해 배포한다.
# (immediate -> permanent 강등, 데몬 없으면 필터링도 없어 서비스는 열린 상태 = allow 와 동일)
if [ -f /tmp/fwpatch2.py ] && [ -f "$M/ansible-posix-1.5.1.tar.gz" ]; then
  python3 /tmp/fwpatch2.py --tarball "$M/ansible-posix-1.5.1.tar.gz" || echo "WARN: firewalld tarball patch failed"
fi
# redhat.rhel_system_roles 는 Red Hat 전용 컬렉션(공개 Galaxy 부재)이다.
# 과거엔 fedora.linux_system_roles 를 이름만 바꿔 서빙했으나, 그 경우 role 내부가
# 여전히 fedora.linux_system_roles.* FQCN 을 호출해 timesync/selinux 실행 시 실패하고,
# 최신 fedora 콘텐츠는 ansible-core 2.14 와 호환되지 않는다.
# 따라서 실제 시험과 동일하게 rhel-system-roles RPM 이 제공하는 "진짜" redhat.rhel_system_roles
# 컬렉션을 설치한 뒤, 그 디렉토리를 덤프가 기대하는 파일명/버전으로 재패키징해 서빙한다.
dnf -y install rhel-system-roles >/dev/null 2>&1 || echo "WARN: rhel-system-roles rpm install failed"
SRDIR=/usr/share/ansible/collections/ansible_collections/redhat/rhel_system_roles

# redhat.rhel_system_roles 컬렉션 디렉토리를 지정 버전으로 재패키징하는 헬퍼.
repack_sr() {
  local ver="$1" out="$2"
  [ -d "$SRDIR" ] || return 1
  local work; work=$(mktemp -d); cp -a "$SRDIR" "$work/c"
  python3 - "$work/c" "$ver" <<'PY'
import json, sys
d_dir, ver = sys.argv[1:3]
mf = d_dir + "/MANIFEST.json"
d = json.load(open(mf))
ci = d["collection_info"]
ci["namespace"] = "redhat"; ci["name"] = "rhel_system_roles"
ci["version"] = ver; ci["dependencies"] = {}; ci["requires_ansible"] = ">=2.14"
json.dump(d, open(mf, "w"), indent=4)
PY
  ( cd "$work/c" && tar czf "$out" $(ls -A) )
  rm -rf "$work"
}

if [ -d "$SRDIR" ]; then
  repack_sr 1.15.1 "$M/redhat-rhel_system_roles-1.15.1.tar.gz" || echo "WARN: repack 1.15.1 failed"
  repack_sr 1.19.3 "$M/redhat-rhel_system_roles-1.19.3.tar.gz" || echo "WARN: repack 1.19.3 failed"
else
  echo "WARN: $SRDIR 없음 — fedora 대체본으로 폴백"
  ansible-galaxy collection download fedora.linux_system_roles -p /tmp/lsr --no-deps || true
  LSR=$(find /tmp/lsr -name 'fedora-linux_system_roles-*.tar.gz' | head -1)
  [ -n "$LSR" ] && { cp -f "$LSR" "$M/redhat-rhel_system_roles-1.15.1.tar.gz"; cp -f "$LSR" "$M/redhat-rhel_system_roles-1.19.3.tar.gz"; cp -f "$LSR" "$M/$(basename "$LSR")"; }
fi

# (참고) fedora.linux_system_roles 원본도 함께 제공 — 필요 시 사용
ansible-galaxy collection download fedora.linux_system_roles -p /tmp/lsr2 --no-deps >/dev/null 2>&1 || true
LSR2=$(find /tmp/lsr2 -name 'fedora-linux_system_roles-*.tar.gz' 2>/dev/null | head -1)
[ -n "$LSR2" ] && cp -f "$LSR2" "$M/$(basename "$LSR2")"

# --- role tarball: balancer (haproxy.tar) ---
R=/tmp/balancer
mkdir -p "$R/tasks" "$R/templates" "$R/handlers" "$R/meta" "$R/defaults"
cat > "$R/meta/main.yml" <<'EOF'
galaxy_info:
  role_name: balancer
  author: rhce-lab
  description: HAProxy load balancer for webservers group
  license: MIT
  min_ansible_version: "2.9"
dependencies: []
EOF
cat > "$R/defaults/main.yml" <<'EOF'
---
balancer_backend_group: webservers
EOF
cat > "$R/tasks/main.yml" <<'EOF'
---
- name: Install haproxy
  ansible.builtin.dnf:
    name: haproxy
    state: present
- name: Deploy haproxy config
  ansible.builtin.template:
    src: haproxy.cfg.j2
    dest: /etc/haproxy/haproxy.cfg
  notify: restart haproxy
- name: Enable and start haproxy
  ansible.builtin.service:
    name: haproxy
    state: started
    enabled: true
- name: Open http in firewall
  ansible.posix.firewalld:
    service: http
    permanent: true
    immediate: true
    state: enabled
  ignore_errors: true
EOF
cat > "$R/handlers/main.yml" <<'EOF'
---
- name: restart haproxy
  ansible.builtin.service:
    name: haproxy
    state: restarted
EOF
cat > "$R/templates/haproxy.cfg.j2" <<'EOF'
global
    daemon
    maxconn 256
defaults
    mode http
    timeout connect 5s
    timeout client 30s
    timeout server 30s
frontend main
    bind *:80
    default_backend app
backend app
    balance roundrobin
{% for h in groups[balancer_backend_group] | default([]) %}
    server {{ h }} {{ hostvars[h]['ansible_default_ipv4']['address'] | default(h) }}:80 check
{% endfor %}
EOF
tar cf "$M/haproxy.tar" -C "$R" .

# --- role tarball: phpinfo (phpinfo.tar) ---
P=/tmp/phpinfo
mkdir -p "$P/tasks" "$P/meta"
cat > "$P/meta/main.yml" <<'EOF'
galaxy_info:
  role_name: phpinfo
  author: rhce-lab
  description: Deploy hello.php on webservers
  license: MIT
  min_ansible_version: "2.9"
dependencies: []
EOF
cat > "$P/tasks/main.yml" <<'EOF'
---
- name: Install httpd and php
  ansible.builtin.dnf:
    name:
      - httpd
      - php
    state: present
- name: Deploy hello.php
  ansible.builtin.copy:
    dest: /var/www/html/hello.php
    content: "<?php echo \"Hello PHP World from \" . php_uname('n') . \"\\n\"; ?>\n"
- name: Enable and start httpd
  ansible.builtin.service:
    name: httpd
    state: started
    enabled: true
- name: Open http in firewall
  ansible.posix.firewalld:
    service: http
    permanent: true
    immediate: true
    state: enabled
  ignore_errors: true
EOF
tar cf "$M/phpinfo.tar" -C "$P" .

# --- hosts.j2 (Q10 템플릿) ---
cat > "$M/hosts.j2" <<'EOF'
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

{% for host in groups['all'] %}
{{ hostvars[host]['ansible_facts']['fqdn'] }} {{ hostvars[host]['ansible_facts']['default_ipv4']['address'] }} {{ hostvars[host]['ansible_facts']['hostname'] }}
{% endfor %}
EOF

# --- hwreport 템플릿 (Q13) ---
cat > "$M/hwreport.empty" <<'EOF'
HOST=
MEMORY=
BIOS=
DISK_SIZE_VDA=
DISK_SIZE_VDB=
EOF
cp "$M/hwreport.empty" "$M/hwreport.txt"

# --- user_list.yml / user_list2.yml (Q15) ---
cat > "$M/user_list.yml" <<'EOF'
---
users:
  - name: bob
    job: developer
    password_expire_max: 10
    uid: 3000
  - name: sally
    job: manager
    password_expire_max: 20
    uid: 3001
  - name: fred
    job: developer
    password_expire_max: 30
    uid: 3002
EOF
cat > "$M/user_list2.yml" <<'EOF'
---
users:
  - name: AliceJohnson
    job: manager
  - name: BobSmith
    job: developer
  - name: CarolWilliams
    job: manager
  - name: DavidBrown
    job: developer
EOF

# --- salaries.yml (Q16 rekey 대상, vault pw = insecure4sure) ---
echo 'insecure4sure' > /tmp/vp
cat > /tmp/sal_plain.yml <<'EOF'
---
salary_data:
  - { name: alice, salary: 100000 }
  - { name: bob, salary: 90000 }
EOF
ansible-vault encrypt --vault-password-file /tmp/vp --output "$M/salaries.yml" /tmp/sal_plain.yml
rm -f /tmp/vp /tmp/sal_plain.yml

# 권한
chmod -R a+rX "$M"
ls -al "$M"
