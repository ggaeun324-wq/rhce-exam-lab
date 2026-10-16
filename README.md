1. 사전 준비

* Windows 10/11
* Docker Desktop
* Git
* PowerShell

2. 실습 환경 다운로드

PowerShell을 실행한 뒤 아래 명령어를 입력합니다.

git clone https://github.com/ggaeun324-wq/rhce-exam-lab.git
cd rhce-exam-lab

3. RHCE 실습 환경 실행

Docker Desktop이 실행 중인지 확인한 후 다음 명령어를 입력합니다.

.\scripts\start.ps1

최초 실행 시 Docker 이미지 빌드로 시간이 소요될 수 있습니다.

4. 실습 환경 접속

브라우저에서 아래 주소로 접속합니다.

http://localhost:8080

Control Node의 웹 콘솔에서 RHCE 실습을 시작할 수 있습니다.

5. 실습 환경 관리

# 실습 환경 중지
.\scripts\stop.ps1
# 실습 환경 재시작
.\scripts\start.ps1
# 실습 환경 초기화
.\scripts\reset.ps1

주의: 초기화 시 기존 실습 진행 상황이 삭제될 수 있습니다. 본 프로젝트는 로컬의 격리된 학습 환경에서만 사용하세요.
