#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "用法: sudo bash setup-user.sh <节点编号>"
    echo "示例: sudo bash setup-user.sh 1"
    exit 1
fi

NODE_NUM=$1
NODE_NAME="docker${NODE_NUM}"

echo "========================================"
echo "👤 配置系统用户: $NODE_NAME"
echo "========================================"

# 设置主机名
sudo hostnamectl set-hostname "$NODE_NAME"
echo "127.0.0.1 $NODE_NAME" | sudo tee -a /etc/hosts

# 创建dockeradmin用户（可选）
if ! id "dockeradmin" &>/dev/null; then
    echo "创建 dockeradmin 用户..."
    sudo useradd -m -s /bin/bash dockeradmin
    echo "dockeradmin:dockeradmin123" | sudo chpasswd
    sudo usermod -aG docker,sudo dockeradmin
    echo "✅ 用户 dockeradmin 已创建"
    echo "   密码: dockeradmin123"
    echo "   ⚠️ 请登录后立即修改密码: passwd dockeradmin"
fi

# 配置SSH
echo "配置SSH服务..."
sudo apt-get update -qq
sudo apt-get install -y -qq openssh-server
sudo systemctl enable --now ssh

# 允许密码登录
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# 配置SSH密钥（如果提供）
if [ -n "$SSH_PUBLIC_KEY" ]; then
    echo "配置SSH公钥..."
    sudo mkdir -p /home/dockeradmin/.ssh
    echo "$SSH_PUBLIC_KEY" | sudo tee /home/dockeradmin/.ssh/authorized_keys
    sudo chown -R dockeradmin:dockeradmin /home/dockeradmin/.ssh
    sudo chmod 700 /home/dockeradmin/.ssh
    sudo chmod 600 /home/dockeradmin/.ssh/authorized_keys
    echo "✅ SSH公钥已配置"
fi

# 获取IP地址
TS_IP=$(tailscale ip 2>/dev/null | grep "100.64" | head -1 || echo "未连接Tailscale")

echo ""
echo "========================================"
echo "✅ 用户配置完成！"
echo "========================================"
echo "📌 主机名: $NODE_NAME"
echo "📌 Tailscale IP: $TS_IP"
echo ""
echo "SSH访问方式:"
echo "  ssh dockeradmin@$TS_IP"
echo "  密码: dockeradmin123"
echo ""
echo "⚠️ 安全提示: 请登录后立即修改密码"
echo "   命令: passwd dockeradmin"
echo "========================================"
