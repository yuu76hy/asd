#!/bin/bash
set -e

NODE_NAME=$(hostname)
START_TIME=$(date +%s)
LIFETIME=19800
LOG_FILE="/tmp/node-lifecycle.log"
REPLACEMENT_LOG="/tmp/node-replacement.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========================================"
log "🚀 [$NODE_NAME] 生命周期管理器启动"
log "   交班时间: $(date -d @$((START_TIME + LIFETIME)) '+%H:%M:%S')"
log "   当前时间: $(date '+%H:%M:%S')"
log "========================================"

while true; do
    ELAPSED=$(( $(date +%s) - START_TIME ))
    REMAINING=$(( LIFETIME - ELAPSED ))
    
    if [ $((ELAPSED % 1800)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        HOURS=$((ELAPSED / 3600))
        MINS=$(((ELAPSED % 3600) / 60))
        log "⏰ [$NODE_NAME] 已运行 ${HOURS}h${MINS}m，剩余 $((REMAINING / 60)) 分钟"
    fi
    
    if [ $ELAPSED -ge $LIFETIME ]; then
        log "========================================"
        log "🔄 [$NODE_NAME] 开始交班流程"
        log "   运行时长: $((ELAPSED / 3600))h$(((ELAPSED % 3600) / 60))m"
        log "========================================"
        
        log "1️⃣ 设置节点为drain状态..."
        docker node update --availability drain "$NODE_NAME" 2>/dev/null || true
        
        log "2️⃣ 等待任务迁移 (60秒)..."
        sleep 60
        
        TASKS=$(docker node ps "$NODE_NAME" --filter "desired-state=running" -q 2>/dev/null | wc -l)
        if [ "$TASKS" -eq 0 ]; then
            log "✅ 任务已全部迁移"
        else
            log "⚠️ 仍有 $TASKS 个任务，强制继续..."
        fi
        
        GH_PAT=$(cat /run/secrets/github_pat 2>/dev/null || echo "")
        
        if [ -n "$GH_PAT" ] && [ -n "$GITHUB_REPOSITORY" ]; then
            log "3️⃣ 调用GitHub API创建替补节点..."
            
            RESPONSE=$(curl -s -X POST \
                -H "Authorization: token $GH_PAT" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/$GITHUB_REPOSITORY/codespaces" \
                -d "{
                    \"ref\": \"main\",
                    \"location\": \"WestUs\",
                    \"machine\": \"basicLinux32gb\",
                    \"display_name\": \"docker-replacement-$(date +%Y%m%d%H%M)\"
                }")
            
            if echo "$RESPONSE" | grep -q "id"; then
                log "✅ 新节点创建请求已发送"
                echo "$(date) | $NODE_NAME → 触发创建新节点" >> "$REPLACEMENT_LOG"
            else
                log "❌ API调用失败: $RESPONSE"
            fi
        else
            log "⚠️ 未配置GH_PAT或GITHUB_REPOSITORY，跳过自动创建"
        fi
        
        log "========================================"
        log "🔚 [$NODE_NAME] 交班流程完成"
        log "   旧节点将在30分钟后由GitHub自动销毁"
        log "========================================"
        
        exit 0
    fi
    
    sleep 30
done
