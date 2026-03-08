#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "用法: sudo bash setup-node.sh <节点编号>"
    echo "示例: sudo bash setup-node.sh 1  # 配置docker1节点"
    exit 1
fi

NODE_NUM=$1
NODE_NAME="docker${NODE_NUM}"

# 从环境变量或使用默认值
CLUSTER_USER=${CLUSTER_USER:-root}
CLUSTER_PASSWORD=${CLUSTER_PASSWORD:-root123456}
TS_AUTH_KEY=${TS_AUTH_KEY:-}
SSH_PUBLIC_KEY=${SSH_PUBLIC_KEY:-}

echo "========================================"
echo "🔧 开始配置 $NODE_NAME..."
echo "========================================"
echo "用户: $CLUSTER_USER"
echo "密码: $CLUSTER_PASSWORD"
echo "========================================"

# 1. 设置系统主机名
echo "1️⃣ 设置系统主机名..."
sudo hostnamectl set-hostname "$NODE_NAME"
echo "127.0.0.1 $NODE_NAME" | sudo tee -a /etc/hosts

# 2. 配置root用户密码
echo "2️⃣ 配置root用户密码..."
echo "root:$CLUSTER_PASSWORD" | sudo chpasswd
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sudo sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
echo "✅ root用户密码已设置"

# 3. 配置SSH服务
echo "3️⃣ 配置SSH服务..."
sudo apt-get update -qq
sudo apt-get install -y -qq openssh-server
sudo systemctl enable --now ssh

sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# 配置SSH公钥
if [ -n "$SSH_PUBLIC_KEY" ]; then
    echo "配置SSH公钥..."
    sudo mkdir -p /root/.ssh
    echo "$SSH_PUBLIC_KEY" | sudo tee /root/.ssh/authorized_keys
    sudo chmod 700 /root/.ssh
    sudo chmod 600 /root/.ssh/authorized_keys
    echo "✅ SSH公钥已配置"
fi

# 4. 安装Docker
echo "4️⃣ 安装Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
fi
echo "Docker版本: $(docker --version)"

# 5. 安装Tailscale
echo "5️⃣ 安装Tailscale..."
if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

if [ -n "$TS_AUTH_KEY" ]; then
    sudo tailscale up --authkey "$TS_AUTH_KEY" --hostname "$NODE_NAME" --accept-dns=false
    TS_IP=$(tailscale ip | grep "100.64" | head -1)
    echo "Tailscale IP: $TS_IP"
else
    echo "⚠️ 未设置TS_AUTH_KEY，请手动连接Tailscale"
fi

# 6. 安装GlusterFS
echo "6️⃣ 安装GlusterFS..."
sudo apt-get install -y -qq glusterfs-server glusterfs-client
sudo systemctl enable --now glusterd

# 7. 创建GlusterFS数据目录
echo "7️⃣ 创建GlusterFS数据目录..."
sudo mkdir -p /gluster/data

# 8. 创建挂载点
echo "8️⃣ 创建挂载点..."
sudo mkdir -p /mnt/gluster

echo "========================================"
echo "✅ $NODE_NAME 配置完成！"
echo "========================================"
echo "📌 主机名: $NODE_NAME"
echo "📌 用户名: root"
echo "📌 密码: $CLUSTER_PASSWORD"
if [ -n "$TS_IP" ]; then
    echo "📌 Tailscale IP: $TS_IP"
    echo ""
    echo "SSH访问: ssh root@$TS_IP"
fi
echo ""
echo "下一步操作:"
if [ "$NODE_NUM" -eq 1 ]; then
    echo "  → 在此节点执行 init-swarm.sh 初始化集群"
else
    echo "  → 等待docker1初始化完成后，执行加入集群命令"
fi
echo "========================================"