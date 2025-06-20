#!/bin/bash

echo "🔄 快速更新SeekerAI部署..."
echo "=================================="

PROJECT_DIR="/var/www/seekerStudent"

# 检查项目目录是否存在
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ 项目目录不存在: $PROJECT_DIR"
    exit 1
fi

echo "📁 进入项目目录: $PROJECT_DIR"
cd "$PROJECT_DIR"

echo "⬇️  拉取最新代码..."
sudo git pull origin master

echo "🔧 更新PM2配置..."
sudo tee ecosystem.config.js > /dev/null << 'EOF'
module.exports = {
  apps: [{
    name: 'seeker-ai',
    script: 'server.js',
    instances: 1,
    exec_mode: 'fork',
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true,
    restart_delay: 4000,
    max_restarts: 10,
    min_uptime: '10s'
  }]
};
EOF

echo "🔑 设置文件权限..."
sudo chown -R www-data:www-data "$PROJECT_DIR"

echo "🔄 重启PM2服务..."
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 delete seeker-ai 2>/dev/null || true
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 start ecosystem.config.js
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 save

echo "⏳ 等待服务启动..."
sleep 3

echo "🧪 测试服务..."
echo "健康检查:"
curl -s http://localhost:3000/health | jq . 2>/dev/null || curl -s http://localhost:3000/health

echo ""
echo "API状态:"
curl -s http://localhost:3000/api/status | jq . 2>/dev/null || curl -s http://localhost:3000/api/status

echo ""
echo "PM2状态:"
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 list

echo ""
echo "✅ 更新完成！"
echo "🌐 访问地址: http://$(curl -s ifconfig.me 2>/dev/null)" 