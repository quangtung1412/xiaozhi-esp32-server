#!/bin/bash
# =============================================================
# setup.sh — Cài đặt xiaozhi-esp32-server (Full Stack) trên Ubuntu
# Chạy từ thư mục gốc của project (xiaozhi-esp32-server/)
# Cách dùng: bash deploy/setup.sh
# =============================================================

set -e

# Màu sắc output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Kiểm tra chạy từ đúng thư mục
if [ ! -f "Dockerfile-server" ]; then
    error "Hãy chạy script này từ thư mục gốc của project: bash deploy/setup.sh"
fi

SERVER_IP=$(hostname -I | awk '{print $1}')
info "IP server: ${SERVER_IP}"

# =============================================================
# BƯỚC 1: Cài Docker
# =============================================================
install_docker() {
    if command -v docker &> /dev/null; then
        info "Docker đã được cài sẵn: $(docker --version)"
        return
    fi

    info "Đang cài Docker..."
    sudo apt-get update -y
    sudo apt-get install -y ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo usermod -aG docker "$USER"
    info "Docker cài xong. Lưu ý: Cần logout/login lại để dùng docker không cần sudo."
    info "Hoặc chạy: newgrp docker"
}

# =============================================================
# BƯỚC 2: Build Docker images từ source
# =============================================================
build_images() {
    info "=== Bắt đầu build Docker images từ source ==="

    # Bật BuildKit để dùng cache mount (tăng tốc npm + maven)
    export DOCKER_BUILDKIT=1

    # ---- server image ----
    # Dockerfile-server dùng base image từ ghcr.io (pull tự động, không cần build lại)
    # => Chỉ build lại khi code Python thay đổi (~5 giây)
    info "[1/2] Build server image (Python app — chỉ copy files, rất nhanh)..."
    docker build -t xiaozhi-esp32-server:server_latest -f ./Dockerfile-server .

    # ---- web image ----
    # Lần đầu: ~10 phút (npm install + mvn download)
    # Lần sau: ~1-2 phút nhờ BuildKit cache mount
    info "[2/2] Build web image (Vue + Java — lần đầu chậm, lần sau dùng cache)..."
    docker build -t xiaozhi-esp32-server:web_latest -f ./Dockerfile-web .

    info "=== Build xong! ==="
    docker images | grep xiaozhi-esp32-server
}

# =============================================================
# Rebuild nhanh chỉ server (dùng sau khi sửa code Python)
# =============================================================
rebuild_server_only() {
    info "Rebuild server image (nhanh ~5 giây)..."
    export DOCKER_BUILDKIT=1
    docker build -t xiaozhi-esp32-server:server_latest -f ./Dockerfile-server .
    cd deploy
    docker compose -f docker-compose_all.yml restart xiaozhi-esp32-server
    cd ..
    info "Restart xong!"
}

# =============================================================
# BƯỚC 3: Tải model SenseVoiceSmall
# =============================================================
download_model() {
    MODEL_PATH="deploy/models/SenseVoiceSmall/model.pt"

    if [ -f "$MODEL_PATH" ]; then
        info "Model đã tồn tại tại: $MODEL_PATH"
        return
    fi

    info "Đang tải model SenseVoiceSmall (~300MB)..."
    wget -q --show-progress \
        -O "$MODEL_PATH" \
        "https://modelscope.cn/models/iic/SenseVoiceSmall/resolve/master/model.pt"

    if [ -f "$MODEL_PATH" ]; then
        info "Tải model thành công!"
    else
        error "Tải model thất bại. Hãy tải thủ công và đặt vào: $MODEL_PATH"
    fi
}

# =============================================================
# BƯỚC 4: Cập nhật IP trong config
# =============================================================
update_config() {
    CONFIG_FILE="deploy/data/.config.yaml"

    if grep -q "REPLACE_WITH_YOUR_SERVER_SECRET" "$CONFIG_FILE" 2>/dev/null; then
        warn "Chưa điền server.secret vào $CONFIG_FILE"
        warn "Hãy điền sau khi đăng ký tài khoản trên Web Dashboard."
    fi

    # Tự động thay IP nếu vẫn là placeholder
    if grep -q "<YOUR_SERVER_IP>" "$CONFIG_FILE" 2>/dev/null; then
        sed -i "s|<YOUR_SERVER_IP>|${SERVER_IP}|g" "$CONFIG_FILE"
        info "Đã cập nhật IP server trong config: ${SERVER_IP}"
    fi
}

# =============================================================
# BƯỚC 5: Khởi động containers
# =============================================================
start_services() {
    info "Khởi động services..."
    cd deploy

    docker compose -f docker-compose_all.yml up -d

    cd ..

    info "=== Các containers đang chạy: ==="
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# =============================================================
# MAIN
# =============================================================
main() {
    echo ""
    echo "======================================================"
    echo "  xiaozhi-esp32-server — Full Stack Setup"
    echo "======================================================"
    echo ""

    install_docker
    echo ""
    build_images
    echo ""
    download_model
    echo ""
    update_config
    echo ""
    start_services

    echo ""
    echo "======================================================"
    info "Deploy xong! Các bước tiếp theo:"
    echo ""
    echo "  1. Mở trình duyệt: http://${SERVER_IP}:8002"
    echo "     => Đăng ký tài khoản đầu tiên (sẽ là Admin)"
    echo ""
    echo "  2. Vào menu [参数管理] => tìm [server.secret] => copy giá trị"
    echo ""
    echo "  3. Điền secret vào file: deploy/data/.config.yaml"
    echo "     nano deploy/data/.config.yaml"
    echo ""
    echo "  4. Restart server:"
    echo "     cd deploy && docker compose -f docker-compose_all.yml restart xiaozhi-esp32-server"
    echo ""
    echo "  5. Xem log server:"
    echo "     docker logs -f xiaozhi-esp32-server"
    echo ""
    echo "  Địa chỉ kết nối ESP32:"
    echo "     WebSocket : ws://${SERVER_IP}:8000/xiaozhi/v1/"
    echo "     OTA       : http://${SERVER_IP}:8003/xiaozhi/ota/"
    echo "======================================================"
}

main
