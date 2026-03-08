# 🐳 Docker Swarm 高可用集群部署

> 5台GitHub Codespaces合成永久稳定大服务器（含自动化节点轮换）

| 项目 | 信息 |
|------|------|
| 文档版本 | v2.2 |
| 最后更新 | 2026-03-08 |
| 适用对象 | DevOps工程师、后端开发者、技术负责人 |
| 核心价值 | 将5个短命Codespaces拼成7×24小时在线、数据零丢失、自动续命的虚拟大服务器 |

---

## 📌 目录

- [核心设计思想](#-核心设计思想)
- [系统架构详解](#-系统架构详解)
- [环境准备清单](#-环境准备清单)
- [快速部署指南](#-快速部署指南)
- [自动化节点轮换系统](#-自动化节点轮换系统)
- [验证与测试手册](#-验证与测试手册)
- [运维管理速查](#-运维管理速查)
- [故障排查指南](#-故障排查指南)

---

## 🔑 核心设计思想

### 一句话说清

> "不焊死硬件，只组合能力"：5台会"定时下班"的小机器，靠"智能调度+共享硬盘+自动交班"，对外表现成一台永远在线、数据不丢、自动续命的大服务器。

### 四大核心原则

| 原则 | 实现方式 | 用户价值 |
|------|----------|----------|
| 服务永续 | Docker Swarm自动故障转移 | 节点掉线？10秒内服务恢复 |
| 数据零丢 | GlusterFS双副本分布式存储 | 任意节点消失，数据完好无损 |
| 认知清晰 | 节点命名docker1~docker5 | 操作时秒知位置，绝不混淆 |
| 无人值守 | 5.5小时主动交班+API自动补位 | 你只管用，集群自己扛生死 |

---

## 🏗️ 系统架构详解

### 五层架构图

```
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
```

### 节点角色分配表

| 节点名 | Tailscale IP | 角色 | Swarm角色 | GlusterFS角色 | 生命周期管理 |
|--------|--------------|------|-----------|---------------|--------------|
| docker1 | 100.64.0.1 | Manager | Leader | Peer | 5.5h主动交班 |
| docker2 | 100.64.0.2 | Worker | Worker | Peer | 5.5h主动交班 |
| docker3 | 100.64.0.3 | Manager | Reachable | Peer | 5.5h主动交班 |
| docker4 | 100.64.0.4 | Worker | Worker | Peer | 5.5h主动交班 |
| docker5 | 100.64.0.5 | Manager | Reachable | Peer | 5.5h主动交班 |

---

## 📋 环境准备清单

### 前置条件

- [ ] GitHub账号（支持Codespaces）
- [ ] Tailscale账号（免费版足够）
- [ ] 仓库已启用Codespaces（Settings → Codespaces）
- [ ] 本地电脑安装Tailscale（用于访问集群）

### 准备工作（10分钟）

#### 1. 生成GitHub Personal Access Token (PAT)

```
Settings → Developer settings → Personal access tokens → Generate new token
权限勾选：repo, workflow, codespace (Full control)
保存为: GH_PAT_2026
```

#### 2. 生成Tailscale可复用Auth Key

```
Tailscale Admin Console → Settings → Keys → Generate key
类型：Reusable, Expiry: 1 year
保存为: TS_AUTH_KEY=tskey-auth-xxxxx-xxxxx
```

#### 3. 在仓库创建密钥

进入 `Settings → Secrets and variables → Actions`，添加：

| 名称 | 值 |
|------|------|
| `GH_PAT` | 你的PAT |
| `TS_AUTH_KEY` | 你的Tailscale Auth Key |

---

## 🚀 快速部署指南

### 方式一：使用Codespaces自动部署（推荐）

1. 点击仓库的 `Code → Codespaces → New codespace`
2. Codespaces会自动执行 `postCreateCommand` 完成基础配置
3. 重复创建5个Codespaces，分别命名为 docker1~docker5

### 方式二：手动部署

#### 步骤1：创建5个Codespaces

```
进入你的GitHub仓库
点击 Code → Codespaces → New codespace
配置选择：4核8G或更高
重复创建 5个 Codespaces
```

#### 步骤2：在每个Codespace执行节点设置

```bash
# 下载并执行设置脚本
wget https://raw.githubusercontent.com/yuu76hy/asd/main/scripts/setup-node.sh
chmod +x setup-node.sh

# docker1节点执行
sudo bash setup-node.sh 1

# docker2节点执行
sudo bash setup-node.sh 2

# 依此类推...
```

#### 步骤3：初始化Swarm集群（仅在docker1执行）

```bash
# 下载并执行初始化脚本
wget https://raw.githubusercontent.com/yuu76hy/asd/main/scripts/init-swarm.sh
chmod +x init-swarm.sh
sudo bash init-swarm.sh
```

#### 步骤4：其他节点加入集群

```bash
# docker3/docker5 (Manager) 执行
JOIN_TOKEN=$(ssh docker@100.64.0.1 "docker swarm join-token manager -q")
docker swarm join --token $JOIN_TOKEN 100.64.0.1:2377

# docker2/docker4 (Worker) 执行
JOIN_TOKEN=$(ssh docker@100.64.0.1 "docker swarm join-token worker -q")
docker swarm join --token $JOIN_TOKEN 100.64.0.1:2377
```

#### 步骤5：配置GlusterFS存储池

```bash
# 仅在docker1执行
wget https://raw.githubusercontent.com/yuu76hy/asd/main/scripts/setup-gluster.sh
chmod +x setup-gluster.sh
sudo bash setup-gluster.sh
```

---

## 🤖 自动化节点轮换系统

### 设计原理

```
[节点启动] → 后台运行lifecycle-manager.sh
     ↓
[倒计时5.5小时] → 设置drain + 任务迁移
     ↓
[调用GitHub API] → 创建新Codespace
     ↓
[新节点自动入职] → 命名dockerX + 加入集群
     ↓
[旧节点6小时] → GitHub自动销毁（无感知）
```

### 自动入职流程

新节点启动后，GitHub Actions会自动：

1. 检测当前集群节点数
2. 分配下一个可用编号
3. 安装Docker、Tailscale、GlusterFS
4. 加入Swarm集群
5. 挂载GlusterFS存储

---

## ✅ 验证与测试手册

### 基础验证清单

#### 验证Swarm集群状态

```bash
docker node ls
```
期望：5个节点，3个Manager（含Leader），2个Worker，全部Ready

#### 验证GlusterFS状态

```bash
sudo gluster peer status      # 5个节点应全部Connected
sudo gluster volume info      # workflow-data应为Started
```

#### 验证共享存储

```bash
# 在docker1执行
echo "test-$(hostname)" | sudo tee /mnt/gluster/$(hostname).txt

# 在docker2执行
cat /mnt/gluster/docker1.txt  # 应看到内容
```

#### 验证Routing Mesh

```bash
# 部署测试服务
docker service create --name test-nginx --publish 8080:80 --replicas 3 nginx

# 测试访问
curl http://docker1:8080
curl http://docker2:8080
curl http://docker3:8080
```

### 高可用测试

```bash
# 在docker2执行：停止Docker服务
sudo systemctl stop docker

# 在Manager节点观察（10秒内）
watch docker service ps test-nginx

# 验证服务持续可用
curl http://docker1:8080
```

---

## 🛠️ 运维管理速查

### 日常操作命令

| 场景 | 命令 | 说明 |
|------|------|------|
| 查看集群状态 | `docker node ls` | 所有节点健康状态 |
| 查看服务状态 | `docker service ls` | 服务副本数、端口 |
| 查看任务分布 | `docker service ps <service>` | 容器在哪些节点 |
| 滚动更新服务 | `docker service update --image new-image myapp` | 零停机更新 |
| 扩容服务 | `docker service scale myapp=5` | 增加副本数 |
| 节点维护 | `docker node update --availability drain docker2` | 优雅下线节点 |
| 恢复节点 | `docker node update --availability active docker2` | 重新加入调度 |

### 监控看板

```bash
# 运行集群监控脚本
wget https://raw.githubusercontent.com/yuu76hy/asd/main/scripts/cluster-monitor.sh
chmod +x cluster-monitor.sh
./cluster-monitor.sh
```

---

## 🚨 故障排查指南

### 问题1：节点无法加入Swarm

```bash
# 检查网络连通性
ping 100.64.0.1

# 重新获取token
docker swarm join-token worker
```

### 问题2：GlusterFS挂载失败

```bash
# 检查卷状态
sudo gluster volume status workflow-data

# 重新挂载
sudo umount /mnt/gluster 2>/dev/null || true
sudo mount -t glusterfs 100.64.0.1:/workflow-data /mnt/gluster
```

### 问题3：服务无法访问

```bash
# 检查端口
docker service inspect test-nginx --format '{{.Endpoint.Spec.Ports}}'

# 检查Tailscale
tailscale status
```

### 问题4：新节点未自动加入

```bash
# 检查GitHub Actions日志
仓库 → Actions → Auto Join New Codespace

# 手动触发测试
gh workflow run auto-join.yml
```

---

## 📁 项目结构

```
asd/
├── .devcontainer/
│   ├── devcontainer.json      # Codespaces配置
│   └── lifecycle-manager.sh   # 生命周期管理脚本
├── .github/
│   └── workflows/
│       └── auto-join.yml      # 自动入职工作流
├── scripts/
│   ├── setup-node.sh         # 节点设置脚本
│   ├── init-swarm.sh         # Swarm初始化脚本
│   ├── setup-gluster.sh      # GlusterFS配置脚本
│   └── cluster-monitor.sh    # 集群监控脚本
├── docker-compose.yml        # 服务部署模板
├── .env.example              # 环境变量示例
└── README.md                 # 本文档
```

---

## 💡 最后的话

> "你不再管理5台机器，你管理的是一个永不停机的服务。"

这个架构的核心价值在于：让短命资源变成长期能力。GitHub Codespaces的6小时限制不再是障碍，而是可以被优雅处理的设计约束。

---

## 📄 License

MIT License
