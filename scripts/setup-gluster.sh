#!/bin/bash
set -e

echo "========================================"
echo "💾 配置GlusterFS分布式存储"
echo "========================================"

VOLUME_NAME="workflow-data"
MOUNT_POINT="/mnt/gluster"

echo "1️⃣ 探测所有节点..."
for i in 2 3 4 5; do
    echo "   探测 docker$i (100.64.0.$i)..."
    sudo gluster peer probe "100.64.0.$i" || echo "   ⚠️ docker$i 可能尚未准备好"
done

echo "2️⃣ 验证peer状态..."
sudo gluster peer status

echo "3️⃣ 创建分布式复制卷 (replica 2)..."
if sudo gluster volume info "$VOLUME_NAME" 2>/dev/null; then
    echo "   卷 $VOLUME_NAME 已存在，跳过创建"
else
    sudo gluster volume create "$VOLUME_NAME" \
        replica 2 \
        transport tcp \
        100.64.0.1:/gluster/data \
        100.64.0.2:/gluster/data \
        100.64.0.3:/gluster/data \
        100.64.0.4:/gluster/data \
        100.64.0.5:/gluster/data
    
    echo "4️⃣ 启动卷..."
    sudo gluster volume start "$VOLUME_NAME"
fi

echo "5️⃣ 验证卷状态..."
sudo gluster volume info "$VOLUME_NAME"
sudo gluster volume status "$VOLUME_NAME"

echo "========================================"
echo "✅ GlusterFS配置完成！"
echo "========================================"
echo ""
echo "📌 在每个节点执行以下命令挂载存储:"
echo ""
echo "sudo mkdir -p $MOUNT_POINT"
echo "sudo mount -t glusterfs 100.64.0.1:/$VOLUME_NAME $MOUNT_POINT"
echo "echo '100.64.0.1:/$VOLUME_NAME $MOUNT_POINT glusterfs defaults,_netdev 0 0' | sudo tee -a /etc/fstab"
echo ""
echo "========================================"
