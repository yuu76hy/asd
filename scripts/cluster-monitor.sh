#!/bin/bash

echo "启动集群监控 (按Ctrl+C退出)..."
echo ""

watch -n 5 '
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           Docker Swarm 集群状态监控                        ║"
echo "║           时间: $(date +"%Y-%m-%d %H:%M:%S")                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📊 节点状态:"
echo "─────────────────────────────────────────────────────────────"
docker node ls --format "table {{.Hostname}}\t{{.Status}}\t{{.Availability}}\t{{.ManagerStatus}}" 2>/dev/null || echo "无法获取节点状态"
echo ""
echo "📦 服务状态:"
echo "─────────────────────────────────────────────────────────────"
docker service ls 2>/dev/null || echo "无运行服务"
echo ""
echo "💾 GlusterFS状态:"
echo "─────────────────────────────────────────────────────────────"
sudo gluster volume status workflow-data 2>/dev/null | grep -E "Brick|Status|Online" || echo "GlusterFS未配置"
echo ""
echo "🌐 Tailscale状态:"
echo "─────────────────────────────────────────────────────────────"
tailscale status 2>/dev/null | head -10 || echo "Tailscale未启动"
echo ""
'
