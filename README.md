📚 Docker Swarm 高可用集群部署文档  
5台GitHub Codespaces合成永久稳定大服务器（含自动化节点轮换）

文档版本：v2.1  
最后更新：2026-03-08  
适用对象：DevOps工程师、后端开发者、技术负责人  
核心价值：将5个短命Codespaces拼成7×24小时在线、数据零丢失、自动续命的虚拟大服务器

📌 目录
核心设计思想  
系统架构详解  
环境准备清单  
五步部署指南  
自动化节点轮换系统  
验证与测试手册  
运维管理速查  
故障排查指南  
附录：完整脚本库  

🔑 核心设计思想

一句话说清
“不焊死硬件，只组合能力”：5台会“定时下班”的小机器，靠“智能调度+共享硬盘+自动交班”，对外表现成一台永远在线、数据不丢、自动续命的大服务器。

四大核心原则
原则   实现方式   用户价值
服务永续   Docker Swarm自动故障转移   节点掉线？10秒内服务恢复

数据零丢   GlusterFS双副本分布式存储   任意节点消失，数据完好无损

认知清晰   节点命名docker1~docker5   操作时秒知位置，绝不混淆

无人值守   5.5小时主动交班+API自动补位   你只管用，集群自己扛生死

🏗️ 系统架构详解

五层架构图
┌─────────────────────────────────────────────────────────────┐
│  用户访问层                                                  │
│  • 任意节点Tailscale IP:8080                                │
│  • MagicDNS: docker1:8080 / docker3:8080                    │
└───────────────────────┬─────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  调度层：Docker Swarm (3 Manager + 2 Worker)                │
│  • Routing Mesh：所有节点8080端口全局生效                   │
│  • 自动故障转移：节点掉线→10秒内容器迁移                    │
│  • Manager高可用：挂1个→秒选新Leader                        │
└───────────────────────┬─────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  存储层：GlusterFS分布式存储池                              │
│  • 5台硬盘合成1个逻辑卷                                     │
│  • replica 2：每份数据自动存2份                             │
│  • 容器挂载 /mnt/gluster → 数据全局一致                     │
└───────────────────────┬─────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  网络层：Tailscale虚拟局域网                                │
│  • 所有节点100.64.0.x内网互通                               │
│  • MagicDNS：docker1 → 100.64.0.1                           │
│  • 端到端加密，安全访问                                     │
└───────────────────────┬─────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  底层：5台GitHub Codespaces (2核16G × 5)                    │
│  • 角色：docker1/3/5=Manager, docker2/4=Worker              │
│  • 生命周期：6小时自动销毁（但服务不中断！）                │
└─────────────────────────────────────────────────────────────┘

节点角色分配表
节点名   Tailscale IP   角色   Swarm角色   GlusterFS角色   生命周期管理
docker1   100.64.0.1   Manager   Leader   Peer   5.5h主动交班

docker2   100.64.0.2   Worker   Worker   Peer   5.5h主动交班

docker3   100.64.0.3   Manager   Reachable   Peer   5.5h主动交班

docker4   100.64.0.4   Worker   Worker   Peer   5.5h主动交班

docker5   100.64.0.5   Manager   Reachable   Peer   5.5h主动交班

📋 环境准备清单

前置条件
[ ] GitHub账号（支持Codespaces）
[ ] Tailscale账号（免费版足够）
[ ] 仓库已启用Codespaces（Settings → Codespaces）
[ ] 本地电脑安装Tailscale（用于访问集群）

准备工作（10分钟）
生成GitHub Personal Access Token (PAT)
Settings → Developer settings → Personal access tokens → Generate new token
权限勾选：repo, workflow, codespace (Full control)
保存为: GH_PAT_2026

生成Tailscale可复用Auth Key
Tailscale Admin Console → Settings → Keys → Generate key
类型：Reusable, Expiry: 1 year
保存为: TS_AUTH_KEY=tskey-auth-xxxxx-xxxxx

在仓库创建密钥（Settings → Secrets and variables → Actions）
名称: GH_PAT → 值: 你的PAT
名称: TS_AUTH_KEY → 值: 你的Auth Key

🚀 五步部署指南

步骤1：创建5个Codespaces（5分钟）
进入你的GitHub仓库
点击 Code → Codespaces → New codespace
配置选择：4核8G或更高
重复创建 5个 Codespaces
重要：每个Codespace打开后，立即执行下一步命名

步骤2：节点命名与基础安装（每个Codespace执行）
!/bin/bash
文件: ~/setup-node.sh
用法: bash ~/setup-node.sh   # 1=Manager, 2=Worker...

NODE_NUM=1
NODE_NAME="docker{NODE_NUM}"
TS_AUTH_KEY="tskey-auth-xxxxx-xxxxx"  # 替换为你的Auth Key

echo "🔧 开始配置 NODE_NAME..."

设置系统主机名
sudo hostnamectl set-hostname NODE_NAME
echo "127.0.0.1 NODE_NAME" | sudo tee -a /etc/hosts

安装Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker USER
newgrp docker 2>/dev/null || true

安装Tailscale（带命名）
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey TS_AUTH_KEY --hostname NODE_NAME --accept-dns=false

安装GlusterFS
sudo apt-get update
sudo apt-get install -y glusterfs-server glusterfs-client
sudo systemctl enable --now glusterd

创建GlusterFS数据目录
sudo mkdir -p /gluster/data

echo "✅ NODE_NAME 配置完成！"
echo "📌 Tailscale IP: (tailscale ip | head -1)"
echo "💡 下一步：在docker1执行Swarm初始化"

执行：
chmod +x ~/setup-node.sh
bash ~/setup-node.sh 1  # docker1节点
bash ~/setup-node.sh 2  # docker2节点（依此类推）

步骤3：初始化Swarm集群（仅在docker1执行）
初始化Manager
docker swarm init --advertise-addr (tailscale ip | grep "100.64" | head -1)

保存Manager和Worker加入令牌
docker swarm join-token manager -q > /tmp/manager-token.txt
docker swarm join-token worker -q > /tmp/worker-token.txt

查看令牌（复制到其他节点）
cat /tmp/manager-token.txt  # 用于docker3/docker5
cat /tmp/worker-token.txt   # 用于docker2/docker4

步骤4：加入Swarm集群（其他节点执行）
docker3和docker5（Manager）执行：
docker swarm join --token (cat /tmp/manager-token.txt) 100.64.0.1:2377

docker2和docker4（Worker）执行：
docker swarm join --token (cat /tmp/worker-token.txt) 100.64.0.1:2377

步骤5：配置GlusterFS存储池（仅在docker1执行）
探测所有节点
sudo gluster peer probe 100.64.0.2
sudo gluster peer probe 100.64.0.3
sudo gluster peer probe 100.64.0.4
sudo gluster peer probe 100.64.0.5

验证peer状态（应显示5个Connected）
sudo gluster peer status

创建复制卷（replica 2 = 双副本）
sudo gluster volume create workflow-data \
  replica 2 \
  transport tcp \
  100.64.0.1:/gluster/data \
  100.64.0.2:/gluster/data \
  100.64.0.3:/gluster/data \
  100.64.0.4:/gluster/data \
  100.64.0.5:/gluster/data

启动卷
sudo gluster volume start workflow-data

在所有节点挂载（在每个节点执行）
sudo mkdir -p /mnt/gluster
sudo mount -t glusterfs 100.64.0.1:/workflow-data /mnt/gluster
echo "100.64.0.1:/workflow-data /mnt/gluster glusterfs defaults,_netdev 0 0" | \
  sudo tee -a /etc/fstab

🤖 自动化节点轮换系统

设计原理
[节点启动] → 后台运行lifecycle-manager.sh
     ↓
[倒计时5.5小时] → 设置drain + 任务迁移
     ↓
[调用GitHub API] → 创建新Codespace
     ↓
[新节点自动入职] → 命名dockerX + 加入集群
     ↓
[旧节点6小时] → GitHub自动销毁（无感知）

实现步骤

创建生命周期管理脚本（放入仓库）
文件：.devcontainer/lifecycle-manager.sh
!/bin/bash
节点生命周期管理器 - 自动5.5小时交班
set -e

NODE_NAME=(hostname)
START_TIME=(date +%s)
LIFETIME=19800  # 5.5小时 = 19800秒
GH_PAT=(docker secret inspect --format '{{.Spec.Data}}' github_pat 2>/dev/null | base64 -d || echo "")

echo "🚀 [NODE_NAME] 生命周期管理器启动 | 交班时间: (date -d @((START_TIME + LIFETIME)) '+%H:%M:%S')"
echo "NODE_NAME lifecycle started at (date)" >> /tmp/node-lifecycle.log

while true; do
  ELAPSED=(( (date +%s) - START_TIME ))
  
  # 5.5小时触发交班
  if [ ELAPSED -ge LIFETIME ]; then
    echo "🔄 [NODE_NAME] 开始交班流程 (运行时长: ((ELAPSED/3600))h(((ELAPSED%3600)/60))m)"
    
    # 1. 优雅退出Swarm
    docker node update --availability drain NODE_NAME 2>/dev/null || true
    echo "⏳ 等待任务迁移 (60秒)..."
    sleep 60
    
    # 2. 确认无活跃任务
    TASKS=(docker node ps NODE_NAME --filter "desired-state=running" -q 2>/dev/null | wc -l)
    if [ "TASKS" -eq 0 ]; then
      echo "✅ 任务已全部迁移"
    else
      echo "⚠️ 仍有 TASKS 个任务，强制继续..."
    fi
    
    # 3. 调用GitHub API创建新节点
    if [ -n "GH_PAT" ]; then
      echo "📡 调用GitHub API创建替补节点..."
      RESPONSE=(curl -s -X POST \
        -H "Authorization: token GH_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        https://api.github.com/repos/GITHUB_REPOSITORY/codespaces \
        -d "{
          "ref": "main",
          "location": "WestUs",
          "machine": "basicLinux32gb",
          "display_name": "docker-replacement-(date +%Y%m%d%H%M)"
        }")
      
      if echo "RESPONSE" | grep -q "id"; then
        echo "✅ 新节点创建请求已发送 | 时间: (date)"
        echo "(date) | NODE_NAME → 触发创建新节点" >> /tmp/node-replacement.log
      else
        echo "❌ API调用失败: RESPONSE"
      fi
    else
      echo "⚠️ 未配置GH_PAT，跳过自动创建"
    fi
    
    echo "🔚 [NODE_NAME] 交班流程完成 | 旧节点将在30分钟后由GitHub自动销毁"
    exit 0
  fi
  
  sleep 30
done

配置自动部署（.devcontainer/devcontainer.json）
{
  "name": "Docker Swarm Node",
  "postCreateCommand": "chmod +x .devcontainer/lifecycle-manager.sh && nohup .devcontainer/lifecycle-manager.sh > /tmp/lifecycle.log 2>&1 &",
  "remoteUser": "root"
}

配置GitHub Actions自动入职（.github/workflows/auto-join.yml）
name: Auto Join New Codespace
on:
  workflow_dispatch:
  repository_dispatch:
    types: [codespace-created]

jobs:
  join-cluster:
    runs-on: ubuntu-latest
    steps:
      uses: actions/checkout@v4
      name: Setup new node
        run: |
          # 自动检测节点编号
          EXISTING=(curl -s -H "Authorization: token {{ secrets.GH_PAT }}" \
            "https://api.github.com/repos/{{ github.repository }}/codespaces" | \
            jq -r '.codespaces[].display_name' | grep "docker" | sort -V | tail -1)
          NEXT_NUM=(( {EXISTING##*docker} + 1 ))
          
          # 设置主机名
          echo "NEW_HOSTNAME=dockerNEXT_NUM" >> GITHUB_ENV
          
          # 安装基础环境（简化版，完整版见附录）
          curl -fsSL https://get.docker.com | sh
          curl -fsSL https://tailscale.com/install.sh | sh
          sudo tailscale up --authkey {{ secrets.TS_AUTH_KEY }} --hostname dockerNEXT_NUM
          
          # 加入Swarm（从Manager拉取token）
          MANAGER_IP=(tailscale ip | grep -E "100.64.0.(1|3|5)" | head -1)
          JOIN_TOKEN=(ssh docker@MANAGER_IP "docker swarm join-token worker -q")
          docker swarm join --token JOIN_TOKEN MANAGER_IP:2377
          
          # 挂载GlusterFS
          sudo mkdir -p /mnt/gluster
          sudo mount -t glusterfs MANAGER_IP:/workflow-data /mnt/gluster
        env:
          GITHUB_TOKEN: {{ secrets.GH_PAT }}

在Manager节点创建密钥（docker1执行）
创建GitHub PAT密钥（用于API调用）
echo "你的GH_PAT" | docker secret create github_pat -

✅ 验证与测试手册

基础验证清单
验证Swarm集群状态（在任意Manager执行）
docker node ls
期望：5个节点，3个Manager（含Leader），2个Worker，全部Ready

验证GlusterFS状态
sudo gluster peer status      # 5个节点应全部Connected
sudo gluster volume info      # workflow-data应为Started

验证共享存储
echo "test-(hostname)" | sudo tee /mnt/gluster/(hostname).txt
在其他节点执行：cat /mnt/gluster/docker1.txt → 应看到内容

验证Routing Mesh（部署测试服务）
docker service create --name test-nginx --publish 8080:80 --replicas 3 nginx
curl http://docker1:8080       # 应返回nginx欢迎页
curl http://docker2:8080       # 同样返回！
curl http://docker3:8080       # 三台都通！

高可用测试（模拟故障）
在docker2（Worker）执行：停止Docker服务
sudo systemctl stop docker

在Manager节点观察（10秒内）
watch docker service ps test-nginx
期望：docker2上的任务标记为Failed，新任务在docker4/docker5启动

验证服务持续可用
curl http://docker1:8080  # 依然返回nginx页面！

恢复docker2
sudo systemctl start docker
节点自动重新加入集群

节点轮换测试
在任意节点查看生命周期日志
tail -f /tmp/lifecycle.log

手动触发交班（测试用）
修改lifecycle-manager.sh中的LIFETIME=300（5分钟），重启脚本
pkill -f lifecycle-manager.sh
nohup .devcontainer/lifecycle-manager.sh > /tmp/lifecycle.log 2>&1 &

观察5分钟后：
节点设置为drain
GitHub Actions触发新Codespace创建
新节点自动命名并加入集群

🛠️ 运维管理速查

日常操作命令
场景   命令   说明
查看集群状态   docker node ls   所有节点健康状态

查看服务状态   docker service ls   服务副本数、端口

查看任务分布   docker service ps    容器在哪些节点

滚动更新服务   docker service update --image new-image myapp   零停机更新

扩容服务   docker service scale myapp=5   增加副本数

节点维护   docker node update --availability drain docker2   优雅下线节点

恢复节点   docker node update --availability active docker2   重新加入调度

监控看板（在docker1运行）
创建监控脚本 ~/cluster-monitor.sh
watch -n 5 '
echo "=== 集群状态 (date) ===" && 
docker node ls --format "table {{.Hostname}}t{{.Status}}t{{.Availability}}t{{.ManagerStatus}}" &&
echo -e "n=== 服务状态 ===" &&
docker service ls &&
echo -e "n=== GlusterFS状态 ===" &&
sudo gluster volume status workflow-data | grep -E "Brick|Status|Online"
'

运行：chmod +x ~/cluster-monitor.sh && bash ~/cluster-monitor.sh

🚨 故障排查指南

问题1：节点无法加入Swarm
检查：Manager IP是否可达？
ping 100.64.0.1

检查：防火墙是否拦截？
sudo ufw status  # Codespaces通常无防火墙

解决：重新获取token
在Manager执行：docker swarm join-token worker

问题2：GlusterFS挂载失败
检查：卷是否启动？
sudo gluster volume status workflow-data

检查：网络连通性
ping 100.64.0.1

重新挂载
sudo umount /mnt/gluster 2>/dev/null || true
sudo mount -t glusterfs 100.64.0.1:/workflow-data /mnt/gluster

问题3：服务无法通过8080访问
检查：端口是否发布？
docker service inspect test-nginx --format '{{.Endpoint.Spec.Ports}}'

检查：本地端口占用？
ss -tlnp | grep :8080

检查：Tailscale连接
tailscale status  # 确保所有节点Connected

问题4：新节点未自动加入
检查GitHub Actions日志
仓库 → Actions → Auto Join New Codespace → 查看日志

检查密钥是否配置
echo {{ secrets.GH_PAT }}  # 应在Actions中配置

手动触发测试
gh workflow run auto-join.yml -f node_number=6

📎 附录：完整脚本库

附录A：一键部署脚本（在每个Codespace执行）
👉 点击下载 setup-all.sh（仓库中提供完整版）

附录B：docker-compose.yml模板
version: '3.8'
services:
  your-app:
    image: your-registry/your-image:latest
    deploy:
      replicas: 3
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
      placement:
        constraints: [node.role == worker]
    ports:
      "8080:80"
    volumes:
      workflow-data:/app/data
    environment:
      NODE_ENV=production
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  workflow-data:
    driver: local
    driver_opts:
      type: none
      device: /mnt/gluster
      o: bind

附录C：Tailscale MagicDNS使用指南
从本地电脑访问集群（需安装Tailscale）
curl http://docker1:8080      # 访问docker1的8080
curl http://docker3:8080      # 访问docker3的8080
ssh docker@docker5            # SSH到docker5

查看所有节点
tailscale status

附录D：资源与参考
Docker Swarm官方文档
GlusterFS快速入门
Tailscale MagicDNS指南
GitHub Codespaces API

💡 最后的话

“你不再管理5台会消失的机器，而是驾驭一台永动的虚拟大服务器”  
本方案将：  
✅ 技术复杂度封装在自动化脚本中  
✅ 认知负担通过清晰命名彻底消除  
✅ 运维焦虑交给自动轮换系统承担  
你只需：  
1️⃣ 按文档部署一次  
2️⃣ 通过docker1:8080访问服务  
3️⃣ 专注你的业务开发  
集群自己会呼吸、会换岗、会续命。  
这就是现代基础设施该有的样子。 🌟

📄 文档维护：本文档随代码仓库同步更新  
💬 反馈建议：提交Issue或PR  
🌐 开源协议：MIT License  
✨ 祝你部署顺利，集群永动！
