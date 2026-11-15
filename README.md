# xFile Infrastructure & GitOps CI/CD Pipeline

Hệ thống quản lý Hạ tầng (Infrastructure as Code) và Tự động hóa Triển khai (GitOps CI/CD) cho ứng dụng **xFile** — Nền tảng chia sẻ tệp tin trực tuyến chuẩn doanh nghiệp.

---

## 📑 Mục lục
1. [Kiến trúc Tổng thể (Architecture)](#1-kiến-trúc-tổng-thể-architecture)
2. [Sơ đồ Định tuyến & Tên miền (Domain Mapping)](#2-sơ-đồ-định-tuyến--tên-miền-domain-mapping)
3. [Tích hợp Cloud Database (Neon PostgreSQL)](#3-tích-hợp-cloud-database-neon-postgresql)
4. [Cấu hình Cloudflare & Traefik v3](#4-cấu-hình-cloudflare--traefik-v3)
5. [Cài đặt GitHub Self-Hosted Runner trên VPS](#5-cài-đặt-github-self-hosted-runner-trên-vps)
6. [Quy trình CI/CD Đa Repo](#6-quy-trình-cicd-đa-repo)
7. [Triển khai cuốn chiếu & Quy trình Rollback](#7-triển-khai-cuốn-chiếu--quy-trình-rollback)
8. [Observability & Giám sát Hệ thống](#8-observability--giám-sát-hệ-thống)
9. [Checklist Bảo mật VPS (Hardening)](#9-checklist-bảo-mật-vps-hardening)

---

## 1. Kiến trúc Tổng thể (Architecture)

```
                       [ Cloudflare Proxy & CDN ]
                                   │
                    ┌──────────────┴──────────────┐
                    │ HTTPS:443                   │ HTTP:80 (Auto Redirect)
                    ▼                             ▼
             ┌───────────────────────────────────────────┐
             │         Traefik v3 Reverse Proxy          │
             │   (Auto Let's Encrypt / Cloudflare SSL)   │
             └──────┬──────────────────────┬─────────────┘
                    │                      │
        ┌───────────┴──────────┐   ┌───────┴──────────────┐
        ▼                      ▼   ▼                      ▼
  xFile Frontend       xFile Backend API          Uptime Kuma Status
(Next.js Standalone)   (NestJS 12 + Prisma 7)   (status-xFile.julylun.io.vn)
    :3000                  :3000                      :3001
        │                      │
        │                      └───► [ Neon Cloud PostgreSQL ]
        │                            (External SSL Database)
        │
   [ Observability Stack (PLG) ]
   - Prometheus (Metrics)
   - Loki & Promtail (Logs)
   - Grafana (Dashboards)
   - cAdvisor & Node Exporter
```

---

## 2. Sơ đồ Định tuyến & Tên miền (Domain Mapping)

| Dịch vụ | Tên miền (Domain) | Container | Cổng nội bộ | Xác thực SSL / Proxy |
| :--- | :--- | :--- | :--- | :--- |
| **Frontend Web** | `xFile.julylun.io.vn` | `xfile-frontend` | `3000` | Cloudflare Proxy + Traefik TLS |
| **Backend API** | `api-xFile.julylun.io.vn` | `xfile-backend` | `3000` | Cloudflare Proxy + Traefik TLS |
| **Status Monitor** | `status-xFile.julylun.io.vn` | `xfile-uptime-kuma`| `3001` | Cloudflare Proxy + Traefik TLS |
| **Grafana Dashboards** | `grafana-xFile.julylun.io.vn` | `xfile-grafana` | `3000` | Cloudflare Proxy + Traefik TLS |

> **Lưu ý**: Traefik đã được thiết lập quy tắc hỗ trợ cả chữ hoa và chữ thường (`xFile.julylun.io.vn` và `xfile.julylun.io.vn`).

---

## 3. Tích hợp Cloud Database (Neon PostgreSQL)

Dự án sử dụng cơ sở dữ liệu trên mây (Cloud Database) như **Neon PostgreSQL** hoặc dịch vụ tương thích:
- **Không khởi chạy PostgreSQL cục bộ** trong `docker-compose.yml` nhằm tối ưu tài nguyên VPS (RAM/CPU) và phân tách trách nhiệm lưu trữ.
- Biến môi trường `DATABASE_URL` được truyền trực tiếp từ `.env` vào container `xfile-backend`.
- Định dạng chuỗi kết nối:
  ```env
  DATABASE_URL="postgresql://<USER>:<PASSWORD>@<HOST>/<DBNAME>?sslmode=require"
  ```

---

## 4. Cấu hình Cloudflare & Traefik v3

### 4.1. Cấu hình trên Dashboard Cloudflare
1. **DNS Records**: Trỏ bản ghi A (hoặc CNAME) về địa chỉ IP công cộng của VPS:
   - `A` `xfile` -> `<IP_VPS>` (Bật Proxied - Đám mây cam)
   - `A` `api-xfile` -> `<IP_VPS>` (Bật Proxied)
   - `A` `status-xfile` -> `<IP_VPS>` (Bật Proxied)
2. **SSL/TLS Encryption Mode**:
   - Chọn **Full** hoặc **Full (strict)**.
   - Bật **Always Use HTTPS** trong tab *Edge Certificates*.
   - Traefik v3 tự động cập nhật và chứng thực Let's Encrypt qua cổng 80/443 hoặc sử dụng Cloudflare Origin CA.
3. **Real Client IP Forwarding**:
   - Traefik được cấu hình danh sách CIDR IP đáng tin cậy của Cloudflare trong `traefik/traefik.yml` để giữ nguyên IP thật của người dùng từ header `CF-Connecting-IP`.

---

## 5. Cài đặt GitHub Self-Hosted Runner trên VPS

Quy trình Continuous Deployment (CD) sử dụng **GitHub Self-Hosted Runner** chạy trực tiếp trên VPS cá nhân của bạn (`runs-on: self-hosted`), giúp runner giao tiếp nội bộ với Docker daemon mà không cần mở port SSH ra Internet.

### Các bước cài đặt:
1. Đăng nhập vào VPS qua SSH:
   ```bash
   ssh user@your-vps-ip
   ```
2. Sao chép repo hạ tầng về VPS (nếu chưa có):
   ```bash
   git clone https://github.com/Julylun/cloud-computing-xFile-infra.git ~/cloud-computing-xFile-infra
   cd ~/cloud-computing-xFile-infra
   ```
3. Lấy Runner Token từ GitHub:
   - Truy cập: `https://github.com/Julylun/cloud-computing-xFile-infra/settings/actions/runners/new`
   - Copy token đăng ký (chuỗi ký tự dạng `Axxxxxxxxxxxx`).
4. Chạy script tự động cài đặt runner:
   ```bash
   chmod +x ./scripts/*.sh
   ./scripts/setup-runner.sh <TOKEN_VUA_COPY> vps-runner
   ```
5. Kiểm tra runner đã ở trạng thái **Idle / Green** trên GitHub Settings.

---

## 6. Quy trình CI/CD Đa Repo

### 6.1. Reusable CI Workflow (`reusable-ci.yml`)
Cả 2 repo `cloud-computing-xFile-backend` và `cloud-computing-xFile-frontend` đều tái sử dụng workflow chuẩn tại repo hạ tầng:
1. **Lint & Syntax Check**: Chạy Oxlint (Backend) / ESLint (Frontend).
2. **Automated Testing**: Chạy Vitest (Backend) / Build test (Frontend).
3. **Build Multi-stage Docker**: Đóng gói qua Docker BuildKit với GitHub Actions Cache (`type=gha`).
4. **Quét bảo mật Trivy**: Phát hiện các lỗ hổng CVE mức độ HIGH & CRITICAL trong image.
5. **Push GHCR**: Đẩy image lên GitHub Container Registry với 2 tags:
   - `sha-<commit>` (ví dụ: `sha-7f2a1b9`)
   - `latest` (khi merge vào nhánh `main`).
6. **Trigger CD**: Bắn sự kiện `repository_dispatch` (event: `deploy-service`) sang repo `cloud-computing-xFile-infra`.

> **Bảo mật**: Các Action đều được ghim cố định bằng **Commit SHA đầy đủ** theo chuẩn DevSecOps doanh nghiệp.

### 6.2. Cấu hình Secret `INFRA_DISPATCH_TOKEN`
Tại repo `cloud-computing-xFile-backend` và `cloud-computing-xFile-frontend`:
- Vào `Settings -> Secrets and variables -> Actions`.
- Thêm secret `INFRA_DISPATCH_TOKEN`: Chứa Personal Access Token (PAT) có quyền `repo` hoặc `actions:write` trên repo `cloud-computing-xFile-infra`.

---

## 7. Triển khai cuốn chiếu & Quy trình Rollback

### 7.1. Tự động hóa triển khai (Auto CD)
Khi có sự kiện `repository_dispatch` từ CI, workflow `deploy.yml` trên VPS runner sẽ thực thi:
```bash
./scripts/deploy.sh backend sha-xxxx
# hoặc
./scripts/deploy.sh frontend sha-xxxx
```
- Lệnh chạy: `docker compose up -d --no-deps <service>`.
- Hệ thống thực hiện kiểm tra `healthcheck` trong tối đa 60 giây.
- Nếu container đạt trạng thái `healthy`, Traefik tự động chuyển tiếp lưu lượng truy cập tới container mới.

### 7.2. Tự động Rollback khi gặp sự cố
Nếu healthcheck thất bại (hoặc container crash / trả về lỗi):
- `deploy.sh` tự động kích hoạt `scripts/rollback.sh <service> <previous-tag>` để khôi phục phiên bản trước đó ngay lập tức mà không cần can thiệp thủ công.
- Thời gian phục hồi dưới **10 giây**.

### 7.3. Rollback thủ công qua GitHub Actions
1. Vào tab **Actions** tại repo `cloud-computing-xFile-infra`.
2. Chọn workflow **Continuous Deployment (CD)** -> Bấm **Run workflow**.
3. Chọn:
   - Service: `backend` hoặc `frontend`
   - Tag: SHA tag muốn quay lại (ví dụ: `sha-abc1234`)
   - Action: `rollback`

---

## 8. Observability & Giám sát Hệ thống

Khởi động cụm giám sát tài nguyên và nhật ký:
```bash
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```

Các thành phần bao gồm:
- **Uptime Kuma** (`https://status-xFile.julylun.io.vn`): Theo dõi tính sẵn sàng 24/7 của API và Frontend, tự động cảnh báo hết hạn SSL.
- **Prometheus** (Port 9090): Thu thập số liệu từ cAdvisor, Node Exporter và Traefik.
- **Loki & Promtail**: Tự động gom và lập chỉ mục nhật ký từ toàn bộ Docker container.
- **Grafana** (`https://grafana-xFile.julylun.io.vn`): Giao diện trực quan hóa toàn bộ metrics và logs với Datasources được nạp tự động qua file cấu hình provisioning.

---

## 9. Checklist Bảo mật VPS (Hardening)

Thực thi script làm sạch và thắt chặt bảo mật VPS:
```bash
sudo ./scripts/hardening.sh
```

Nội dung bảo mật thực hiện:
1. **Firewall (UFW)**: Chỉ mở cổng `22` (SSH), `80` (HTTP), `443` (HTTPS). Mọi kết nối đến Database hoặc Monitoring đều chạy nội bộ qua Docker Network.
2. **SSH Hardening**: Tắt đăng nhập mật khẩu (`PasswordAuthentication no`) và cấm root SSH bằng mật khẩu (`PermitRootLogin prohibit-password`).
3. **Fail2ban**: Giám sát và tự động chặn các địa chỉ IP có dấu hiệu dò quét mật khẩu SSH.
4. **Traefik ACME Security**: Cấp quyền `chmod 600` cho `traefik/acme.json` ngăn chặn lộ khóa riêng tư của chứng chỉ SSL.
5. **Unattended Upgrades**: Kích hoạt tự động cập nhật bản vá bảo mật hệ điều hành Ubuntu/Debian.
