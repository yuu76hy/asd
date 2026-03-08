#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "用法: sudo bash setup-node.sh <节点编号>"
    echo "示例: sudo bash setup-node.sh 1  # 配置docker1节点"
    exit 1
fi

NODE_NUM=$1
NODE_NAME="docker${NODE_NUM}"

if [ -z "$TS_AUTH_KEY" ]; then
    echo "错误: 请设置环境变量 TS_AUTH_KEY"
    echo "示例: export TS_AUTH_KEY=tskey-auth-xxxxx-xxxxx"
    exit 1
fi

echo "========================================"
echo "🔧 开始配置 $NODE_NAME..."
echo "========================================"

echo "1️⃣ 设置系统主机名..."
sudo hostnamectl set-hostname "$NODE_NAME"
echo "127.0.0.1 $NODE_NAME" | sudo tee -a /etc/hosts

echo "2️⃣ 安装Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    newgrp docker 2>/dev/null || true
fi
echo "Docker版本: $(docker --version)"

echo "3️⃣ 安装Tailscale..."
if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi
sudo tailscale up --authkey "$TS_AUTH_KEY" --hostname "$NODE_NAME" --accept-dns=false
TS_IP=$(tailscale ip | grep "100.64" | head -1)
echo "Tailscale IP: $TS_IP"

echo "4️⃣ 安装GlusterFS..."
sudo apt-get update -qq
sudo apt-get install -y -qq glusterfs-server glusterfs-client
sudo systemctl enable --now glusterd

echo "5️⃣ 创建GlusterFS数据目录..."
sudo mkdir -p /gluster/data

echo "========================================"
echo "✅ $NODE_NAME 配置完成！"
echo "========================================"
echo "📌 Tailscale IP: $TS_IP"
echo "📌 主机名: $NODE_NAME"
echo ""
echo "下一步操作:"
if [ "$NODE_NUM" -eq 1 ]; then
    echo "  → 在此节点执行 init-swarm.sh 初始化集群"
else
    echo "  → 等待docker1初始化完成后，执行加入集群命令"
fi
echo "========================================"
