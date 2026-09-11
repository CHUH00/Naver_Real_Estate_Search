# Oracle Cloud 무료 서버로 배포하기 (Mac 안 켜놔도 됨)

Oracle Cloud의 **Always Free** 티어(ARM Ampere A1, 4 OCPU / 24GB RAM, 완전 무료·기간 제한 없음)에
백엔드를 올려서 24시간 상시 서비스되게 만드는 가이드입니다. Mac을 꺼도 앱은 계속 동작합니다.

---

## 1. Oracle Cloud 계정 만들기 (브라우저에서 직접)

1. https://www.oracle.com/cloud/free/ 접속 → **가입(Start for free)**
2. 이메일, 이름, 국가 입력 → 이메일 인증
3. 신용카드 등록 필요 (본인 확인용, **Always Free** 리소스는 절대 과금되지 않음. Free 한도를 넘는 유료 리소스를 "직접" 추가하지 않는 한 청구 없음)
4. 로그인 후 "홈 리전(Home Region)" 선택 — 한 번 정하면 못 바꾸니 **한국과 가까운 리전**(예: Japan Central (Osaka) 또는 South Korea Central (Chuncheon), 제공 여부는 가입 시점에 표시됨) 선택

> ⚠️ Oracle은 가끔 무료 ARM 인스턴스 용량이 리전별로 일시 부족(Out of host capacity)할 수 있습니다.
> 이 경우 몇 분~몇 시간 뒤 재시도하거나 다른 가용성 도메인(AD)으로 시도하면 대부분 해결됩니다.

## 2. VM 인스턴스 생성

콘솔 좌측 메뉴 → **Compute → Instances → Create Instance**

- **Name**: `naverland-server`
- **Image**: Ubuntu 22.04 (또는 24.04)
- **Shape**: `VM.Standard.A1.Flex` 선택 → OCPU 2, 메모리 12GB 정도로 설정 (Always Free 한도 내: 최대 4 OCPU/24GB까지 무료)
- **Networking**: 기본 VCN 그대로 사용, **Public IP 자동 할당** 체크 확인
- **SSH Keys**: "Save Private Key" 눌러서 `.key` 파일을 안전한 곳에 저장 (SSH 접속에 필요)
- **Create** 클릭 → 몇 분 후 상태가 "Running"으로 바뀌면 완료
- 인스턴스 상세 페이지에서 **Public IP Address** 복사해두기

## 3. 방화벽(보안 목록)에서 포트 열기

Oracle은 기본적으로 SSH(22)만 열려 있습니다. 우리는 백엔드를 **Cloudflare Tunnel로만** 노출할 것이므로
외부에 추가로 열어야 할 포트는 없습니다 (8080은 VM 내부 localhost에서만 씁니다). SSH만 되면 충분합니다.

## 4. SSH 접속

```bash
chmod 600 ~/Downloads/ssh-key-xxxx.key
ssh -i ~/Downloads/ssh-key-xxxx.key ubuntu@<Public-IP>
```

## 5. VM에 Docker + cloudflared 설치

VM 안에서 실행:

```bash
# Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker

# cloudflared (ARM64용)
curl -L -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
sudo dpkg -i cloudflared.deb
```

## 6. 코드 가져오기 + 이미지 빌드

```bash
sudo apt-get update && sudo apt-get install -y git
git clone <이 저장소의_git_주소> app
cd app
docker build -t naverland-backend:latest .
sudo mkdir -p /opt/naverland/data
```

> git 저장소 주소가 없다면(로컬 전용 프로젝트라면) Mac에서 아래처럼 압축해서 올려도 됩니다:
> ```bash
> # Mac에서
> cd /Users/choi/Desktop/study/GenI
> tar czf app.tar.gz --exclude='.git' --exclude='ios' --exclude='__pycache__' .
> scp -i ~/Downloads/ssh-key-xxxx.key app.tar.gz ubuntu@<Public-IP>:~
> # VM에서
> mkdir app && tar xzf app.tar.gz -C app && cd app
> docker build -t naverland-backend:latest .
> ```

## 7. 서비스로 등록해서 24시간 자동 실행

이 저장소의 `deploy/naverland-backend.service`, `deploy/cloudflared.service` 파일을 VM으로 복사:

```bash
# Mac에서
scp -i ~/Downloads/ssh-key-xxxx.key deploy/*.service ubuntu@<Public-IP>:~
```

VM에서:

```bash
sudo mv ~/naverland-backend.service ~/cloudflared.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now naverland-backend
sudo systemctl enable --now cloudflared
```

이제 VM을 재부팅해도 두 서비스가 자동으로 다시 켜집니다.

## 8. 발급된 주소 확인

```bash
sudo cat /var/log/cloudflared-url.log | grep trycloudflare
```

`https://xxxx.trycloudflare.com` 형태의 주소가 보이면, 이 주소를 아이폰 앱 **설정 탭 → 서버 주소**에 입력하면 됩니다.

## 9. 이후 업데이트할 때

코드를 수정했다면 VM에서:

```bash
cd ~/app
git pull   # 또는 다시 scp로 파일 갱신
docker build -t naverland-backend:latest .
sudo systemctl restart naverland-backend
```

`cloudflared`는 재시작하지 않는 한 URL이 유지됩니다 (백엔드만 재시작하면 주소는 그대로).
