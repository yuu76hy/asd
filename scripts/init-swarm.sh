#!/bin/bash
set -e

echo "========================================"
echo "🚀 初始化Docker Swarm集群"
echo "========================================"

TS_IP=$(tailscale ip | grep "100.64" | head -1)
if [ -z "$TS_IP" ]; then
    echo "错误: 未找到Tailscale IP，请确保Tailscale已启动"
    exit 1
fi

echo "检测到Tailscale IP: $TS_IP"

echo "1️⃣ 初始化Swarm..."
docker swarm init --advertise-addr "$TS_IP"

echo "2️⃣ 保存加入令牌..."
MANAGER_TOKEN=$(docker swarm join-token manager -q)
WORKER_TOKEN=$(docker swarm join-token worker -q)

echo "" > /tmp/swarm-tokens.txt
echo "=== Manager Token ===" >> /tmp/swarm-tokens.txt
echo "$MANAGER_TOKEN" >> /tmp/swarm-tokens.txt
echo "" >> /tmp/swarm-tokens.txt
echo "=== Worker Token ===" >> /tmp/swarm-tokens.txt
echo "$WORKER_TOKEN" >> /tmp/swarm-tokens.txt
echo "" >> /tmp/swarm-tokens.txt
echo "=== Join Commands ===" >> /tmp/swarm-tokens.txt
echo "# docker3/docker5 (Manager):" >> /tmp/swarm-tokens.txt
echo "docker swarm join --token $MANAGER_TOKEN $TS_IP:2377" >> /tmp/swarm-tokens.txt
echo "" >> /tmp/swarm-tokens.txt
echo "# docker2/docker4 (Worker):" >> /tmp/swarm-tokens.txt
echo "docker swarm join --token $WORKER_TOKEN $TS_IP:2377" >> /tmp/swarm-tokens.txt

echo "========================================"
echo "✅ Swarm初始化完成！"
echo "========================================"
echo ""
echo "📋 加入令牌已保存到 /tmp/swarm-tokens.txt"
echo ""
cat /tmp/swarm-tokens.txt
echo ""
echo "下一步: 在其他节点执行上述加入命令"
echo "========================================"
