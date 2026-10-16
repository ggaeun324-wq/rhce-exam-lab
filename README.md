# RHCE Exam Lab (EX294 / RHEL 9) — 웹 시험환경

실제 EX294(RHEL 9) 시험 흐름과 동일하게 만든 로컬 Docker 랩입니다.
**당신은 control node 콘솔 하나에 admin으로 앉고**, 거기서 SSH/Ansible로 관리노드를 다룹니다.
(실제 시험은 관리노드 root 콘솔을 주지 않습니다. 필요시 "디버그 콘솔"로만 열 수 있게 해뒀습니다.)

## 구성 (덤프 토폴로지 그대로)
| 역할     | Hostname | IP             | FQDN                       | 비고 |
|---------|----------|----------------|----------------------------|------|
| Control | ctrl     | 192.168.59.130 | ctrl.example.com           | **메인 콘솔(admin 자동 로그인), ansible-core 사전 설치** |
| Managed | node1~5  | .131~.135      | node{N}.example.com        | SSH로 접속 |
| Repo    | repo     | 192.168.59.100 | rhgls.domain1.example.com  | 패키지 repo 서버 |

- 베이스: Rocky Linux 9(RHEL 9 클론) · systemd · sshd · ttyd(웹 터미널)
- **패키지는 rhgls repo 서버에서만** 받습니다(인터넷 repo 비활성). 없는 패키지는 실제로 실패 → 시험과 동일.
- rhgls는 내부적으로 Rocky 미러를 **캐싱 프록시**(사전 미러링 불필요, 첫 설치 시 인터넷 필요).
- FQDN/짧은 이름은 DNS로 이미 해석(실제 시험처럼 사전 구성).

## 계정
- control 콘솔: **admin 자동 로그인**(sudo NOPASSWD)
- 관리노드 admin 비밀번호: `admin` (ssh-copy-id 실습용)
- root 비밀번호: `redhat`

## 사용법
1. **Docker Desktop 실행**
2. PowerShell:
   ```powershell
   cd C:\Users\k7979\rhce-exam-lab
   ./scripts/start.ps1      # 최초엔 이미지 빌드로 수 분
   ```
3. 브라우저 → **http://localhost:8080** (control node 콘솔이 바로 뜸)
4. 상단 **✅ 시작 체크리스트** 대로 초기 셋업 → 문제 풀이

### 관리
```powershell
./scripts/stop.ps1     # 중지 (진행상황 유지)
./scripts/start.ps1    # 재시작
./scripts/reset.ps1    # 완전 초기화 (새 시험, fresh 상태)
```

## 시험 시작 시 해야 하는 것 (실제 EX294 초기 셋업)
control node에서 admin으로:
1. `ssh-keygen`
2. `ssh-copy-id admin@node1..5` (비번 admin)
3. inventory 작성 (그룹 구성)
4. `ansible.cfg` 작성 (inventory/remote_user/become)
5. `ansible all -m ping` 으로 확인
6. 이후 플레이북 작성/실행 — 패키지는 rhgls에서 설치

> 포털의 "✅ 시작 체크리스트" 패널에 그대로 복사할 수 있는 명령이 있습니다.

## 덤프 문제
`questions/` 폴더에 파일을 넣으면 포털 **📝 문제** 패널에 목록으로 뜹니다.

## 포트
- 8080 포털 · 7701 control(메인) · 7702~7706 node1~5(디버그) · 7700 repo(디버그) · 8081 repo http

## 주의
- 실제 시험 UI는 비공개라 100% 동일하지는 않습니다. 동작(콘솔 모델·repo·초기 셋업·ansible)을 최대한 동일하게 맞췄습니다.
- 덤프의 `rhgls`/`192.168.59.x`/node1~5는 공식 시험이 아니라 학습용 토폴로지입니다.
- 첫 패키지 설치 시 rhgls가 미러에서 받아오므로 인터넷이 필요합니다(이후 캐시).
- systemd 컨테이너라 privileged로 실행됩니다(로컬 학습용).
