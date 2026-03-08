# 🐳 Docker Swarm 高可用集群部署

> 2节点集群方案（GitHub Codespaces免费版限制）

| 项目 | 信息 |
|------|------|
| 文档版本 | v2.3 |
| 最后更新 | 2026-03-09 |
| 适用对象 | DevOps工程师、后端开发者、技术负责人 |
| 核心价值 | 使用2个Codespaces构建高可用集群 |

---

## 📌 目录

- [核心设计思想](#-核心设计思想)
- [系统架构详解](#-系统架构详解)
- [环境准备清单](#-环境准备清单)
- [快速部署指南](#-快速部署指南)
- [验证与测试手册](#-验证与测试手册)
- [运维管理速查](#-运维管理速查)

---

## 🔑 核心设计思想

### 一句话说清

> "小而精": 由于GitHub Codespaces免费版限制，n

### 核心原则

| 原则 | 实现方式 | 用户价值 |
|------|----------|----------|
| 服务永续 | Docker Swarm自动故障转移 | 节点掉线？10秒内服务恢复 |
| 数据零丢 | GlusterFS双副本分布式存储 | 节点消失，数据完好无损 |
| 认知清晰 | 节点命名docker1~docker2 | 操作时秒知位置 |

---

## 🏗️ 系统架构详解

### 架构图

```
┌─────────────────────────────────────────────────────────────┐
│  用户访问层                                              │
│  • 任意节点Tailscale IP:8080                        │
│  • MagicDNS: docker1:8080 / docker2:8080                │
└───────────────────────┬─────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  调度层：Docker Swarm (2节点)                          │
│  • docker1 = Manager (Leader)                           │
│  • docker2 = Worker                                    │
│  • Routing Mesh：所有节点8080端口全局生效           │
│  • 自动故障转移：节点掉线→10秒内容器迁移            │
└───────────────────────┬─────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  存储层：GlusterFS分布式存储池                          │
│  • 2台硬盘合成1个逻辑卷                               │
│  • replica 2：每份数据自动存2份                       │
│  • 容器挂载 /mnt/gluster → 数据全局一致             │
└───────────────────────┬─────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  网络层：Tailscale虚拟局域网                              │
│  • 所有节点100.64.0.x内网互通                     │
│  • MagicDNS：docker1 → 100.64.0.1                   │
│  • 端到端加密，安全访问                               │
└───────────────────────┬─────────────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  底层：2台GitHub Codespaces (4核16G × 2)              │
│  • 角色：docker1=Manager, docker2=Worker               │
│  • 生命周期：6小时自动销毁（但服务不中断！）            │
└─────────────────────────────────────────────────────────────┘
```

### 节点角色分配表

| 节点名 | Tailscale IP | 角色 | Swarm角色 | GlusterFS角色 |
|--------|--------------|------|-----------|---------------|
| docker1 | 100.64.0.1 | Manager | Leader | Peer |
| docker2 | 100.64.0.2 | Worker | Worker | Peer |

---

## 📋 环境准备清单

### 前置条件

- [x] GitHub账号（支持Codespaces）
- [x] Tailscale账号（免费版足够）
- [x] 仓库已启用Codespaces
- [x] 本地电脑安装Tailscale（用于访问集群）

### 准备工作

#### 1. 生成GitHub Personal Access Token (PAT)

```
Settings → Developer settings → Personal access tokens → Generate new token
权限勾选：repo, workflow, codespace
```

#### 2. 生成Tailscale可复用Auth Key

```
Tailscale Admin Console → Settings → Keys → Generate key
类型：Reusable, Expiry: 1 year
```

---

## 🚀 快速部署指南

### 步骤1：创建2个Codespaces

1. 点击 `Code → Codespaces → New codespace`
2. 选择 `4核16G` 配置
3. 创建2个，分别命名为 docker1 和 docker2

### 步骤2：在docker1执行初始化

```bash
# 设置环境变量
export TS_AUTH_KEY="tskey-auth-kUZjSi5yXA11CNTRL-axBMdddsfr1RLyofEJJ5r1FtAoVVXuC9e"
export CLUSTER_PASSWORD="root123456"

# 执行节点设置
sudo bash scripts/setup-node.sh 1

# 初始化 Swarm
sudo bash scripts/init-swarm.sh

# 配置 GlusterFS
sudo bash scripts/setup-gluster.sh
```

### 步骤3：在docker2加入集群

```bash
# 设置环境变量
export TS_AUTH_KEY="tskey-auth-kUZjSi5yXA11CNTRL-axBMdddsfr1RLyofEJJ5r1FtAoVVXuC9e"

# 执行节点设置
sudo bash scripts/setup-node.sh 2

# 加入Swarm（使用docker1显示的worker token）
docker swarm join --token <worker-token> 100.64.0.1:2377

# 挂载GlusterFS
sudo mkdir -p /mnt/gluster
sudo mount -t glusterfs 100.64.0.1:/workflow-data /mnt/gluster
```

---

## ✅ 验证与测试手册

### 基础验证清单

#### 验证Swarm集群状态

```bash
docker node ls
```
期望：2个节点，1个Manager (Leader), 1个Worker, 全部Ready

#### 验证GlusterFS状态

```bash
sudo gluster peer status      # 应显示Connected
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
docker service create --name test-nginx --publish 8080:80 --replicas 2 nginx

# 测试访问
curl http://docker1:8080
curl http://docker2:8080
```

### 高可用测试

```bash
# 在docker2执行：停止Docker服务
sudo systemctl stop docker

# 在docker1观察（10秒内）
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
| 扩容服务 | `docker service scale myapp=3` | 增加副本数 |
| 节点维护 | `docker node update --availability drain docker2` | 优雅下线节点 |

---

## 🔐 用户凭据

| 项目 | 值 |
|------|------|
| 用户名 | `root` |
| 密码 | `root123456` |
| Tailscale Key | `tskey-auth-kUZjSi5yXA11CNTRL-axBMdddsfr1RLyofEJJ5r1FtAoVVXuC9e` |

---

## 📌 注意事项

- Codespaces 生命周期为 6 小时
- 确保本地已安装 Tailscale 以便访问集群
- 默认密码仅用于初始部署，请及时修改