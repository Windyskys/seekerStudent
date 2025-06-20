#!/bin/bash

echo "🧹 SeekerAI完全清理和重新部署脚本"
echo "========================================"
echo ""
echo "⚠️  警告：此脚本将完全清理现有部署！"
echo "⚠️  包括：PM2进程、项目文件、Nginx配置、数据库等"
echo ""

# 确认操作
read -p "确定要继续吗？这将删除所有现有数据！(输入 'YES' 确认): " -r
if [[ $REPLY != "YES" ]]; then
    echo "❌ 操作已取消"
    exit 1
fi

echo ""
echo "🚀 开始清理和重新部署..."
echo "========================================"

# 配置变量
PROJECT_DIR="/var/www/seekerStudent"
SERVICE_NAME="seeker-ai"
BACKUP_DIR="/tmp/seeker-backup-$(date +%Y%m%d_%H%M%S)"

# 记录脚本执行日志
exec > >(tee -a /tmp/clean-redeploy.log)
exec 2>&1

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
}

# 1. 备份重要数据
log_info "备份重要数据到 $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

if [ -d "$PROJECT_DIR" ]; then
    if [ -f "$PROJECT_DIR/.env" ]; then
        cp "$PROJECT_DIR/.env" "$BACKUP_DIR/" || log_warning "无法备份.env文件"
    fi
    if [ -d "$PROJECT_DIR/database" ]; then
        cp -r "$PROJECT_DIR/database" "$BACKUP_DIR/" || log_warning "无法备份数据库"
    fi
    if [ -d "$PROJECT_DIR/logs" ]; then
        cp -r "$PROJECT_DIR/logs" "$BACKUP_DIR/" || log_warning "无法备份日志"
    fi
    log_success "数据备份完成"
else
    log_warning "项目目录不存在，跳过备份"
fi

# 2. 停止所有PM2进程
log_info "停止所有PM2进程..."
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 stop all 2>/dev/null || true
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 delete all 2>/dev/null || true
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 kill 2>/dev/null || true

# 停止root用户的PM2进程
pm2 stop all 2>/dev/null || true
pm2 delete all 2>/dev/null || true
pm2 kill 2>/dev/null || true

# 强制杀死Node.js进程
pkill -f "node.*server.js" 2>/dev/null || true
pkill -f "PM2" 2>/dev/null || true

log_success "PM2进程已停止"

# 3. 停止Nginx
log_info "停止Nginx服务..."
systemctl stop nginx 2>/dev/null || true
log_success "Nginx已停止"

# 4. 清理项目目录
log_info "清理项目目录..."
if [ -d "$PROJECT_DIR" ]; then
    rm -rf "$PROJECT_DIR"
    log_success "项目目录已清理"
else
    log_info "项目目录不存在，跳过清理"
fi

# 5. 清理Nginx配置
log_info "清理Nginx配置..."
rm -f /etc/nginx/sites-enabled/$SERVICE_NAME 2>/dev/null || true
rm -f /etc/nginx/sites-available/$SERVICE_NAME 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
log_success "Nginx配置已清理"

# 6. 清理systemd服务
log_info "清理systemd服务..."
systemctl stop $SERVICE_NAME 2>/dev/null || true
systemctl disable $SERVICE_NAME 2>/dev/null || true
rm -f /etc/systemd/system/$SERVICE_NAME.service 2>/dev/null || true
systemctl daemon-reload
log_success "systemd服务已清理"

# 7. 清理PM2系统服务
log_info "清理PM2系统服务..."
systemctl stop pm2-www-data 2>/dev/null || true
systemctl disable pm2-www-data 2>/dev/null || true
rm -f /etc/systemd/system/pm2-www-data.service 2>/dev/null || true
systemctl daemon-reload
log_success "PM2系统服务已清理"

# 8. 清理用户目录
log_info "清理用户目录..."
rm -rf /home/www-data/.pm2 2>/dev/null || true
log_success "用户目录已清理"

# 9. 清理管理脚本
log_info "清理管理脚本..."
rm -f /usr/local/bin/seeker-ai-manage 2>/dev/null || true
log_success "管理脚本已清理"

echo ""
echo "🧹 清理完成！"
echo "========================================"
echo ""

# 10. 开始重新部署
log_info "开始重新部署..."
echo ""

# 检查当前目录是否有项目文件
CURRENT_DIR=$(pwd)
if [ -f "$CURRENT_DIR/server.js" ] && [ -f "$CURRENT_DIR/package.json" ]; then
    SOURCE_DIR="$CURRENT_DIR"
    log_info "使用当前目录作为源码: $SOURCE_DIR"
elif [ -f "/root/seekerStudent/server.js" ]; then
    SOURCE_DIR="/root/seekerStudent"
    log_info "使用root目录作为源码: $SOURCE_DIR"
else
    log_error "找不到项目源码目录！"
    echo "请确保在包含server.js和package.json的目录中运行此脚本"
    exit 1
fi

# 创建项目目录
log_info "创建项目目录..."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# 复制项目文件
log_info "复制项目文件..."
rsync -av --exclude='.git' --exclude='node_modules' --exclude='.DS_Store' \
    "$SOURCE_DIR/" "$PROJECT_DIR/"
log_success "项目文件复制完成"

# 恢复备份的数据
log_info "恢复备份数据..."
if [ -f "$BACKUP_DIR/.env" ]; then
    cp "$BACKUP_DIR/.env" "$PROJECT_DIR/"
    log_success "环境变量文件已恢复"
else
    # 创建默认环境变量文件
    log_info "创建默认环境变量文件..."
    cat > .env << 'EOF'
NODE_ENV=production
PORT=3000
QWEN_API_KEY=sk-0eaf3643806f4d4991eedd3dc7f5aa2e
DB_PATH=./database/seeker_ai.db
EOF
    log_success "默认环境变量文件已创建"
fi

if [ -d "$BACKUP_DIR/database" ]; then
    cp -r "$BACKUP_DIR/database" "$PROJECT_DIR/"
    log_success "数据库已恢复"
fi

# 创建必要目录
mkdir -p database logs
log_success "必要目录已创建"

# 11. 安装依赖
log_info "安装项目依赖..."
npm install --production
log_success "依赖安装完成"

# 12. 创建PM2配置
log_info "创建PM2配置..."
cat > ecosystem.config.js << 'EOF'
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
log_success "PM2配置已创建"

# 13. 设置文件权限
log_info "设置文件权限..."
chown -R www-data:www-data "$PROJECT_DIR"
chmod -R 755 "$PROJECT_DIR"
chmod 644 "$PROJECT_DIR/.env"
log_success "文件权限设置完成"

# 14. 配置Nginx
log_info "配置Nginx..."
cat > /etc/nginx/sites-available/$SERVICE_NAME << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 86400;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://localhost:3000;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

ln -sf /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/
log_success "Nginx配置完成"

# 15. 确保www-data用户环境
log_info "配置www-data用户环境..."
if [ ! -d "/home/www-data" ]; then
    mkdir -p /home/www-data
    chown www-data:www-data /home/www-data
fi

mkdir -p /home/www-data/.pm2
chown -R www-data:www-data /home/www-data/.pm2
chmod -R 755 /home/www-data/.pm2
log_success "www-data用户环境配置完成"

# 16. 启动服务
log_info "启动服务..."

# 启动PM2
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 start ecosystem.config.js
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 save
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 startup

# 启动Nginx
nginx -t
if [ $? -eq 0 ]; then
    systemctl start nginx
    systemctl enable nginx
    log_success "Nginx启动成功"
else
    log_error "Nginx配置验证失败"
fi

# 17. 重新创建管理脚本
log_info "创建管理脚本..."
cat > /usr/local/bin/seeker-ai-manage << 'EOF'
#!/bin/bash

PROJECT_DIR="/var/www/seekerStudent"
SERVICE_NAME="seeker-ai"

case "$1" in
    start)
        echo "启动SeekerAI服务..."
        cd $PROJECT_DIR
        sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 start ecosystem.config.js
        systemctl start nginx
        ;;
    stop)
        echo "停止SeekerAI服务..."
        sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 stop $SERVICE_NAME
        ;;
    restart)
        echo "重启SeekerAI服务..."
        cd $PROJECT_DIR
        sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 restart $SERVICE_NAME
        systemctl restart nginx
        ;;
    status)
        echo "SeekerAI服务状态:"
        sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 list
        echo ""
        echo "Nginx状态:"
        systemctl status nginx --no-pager -l
        ;;
    logs)
        echo "查看应用日志:"
        sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 logs $SERVICE_NAME
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|logs}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/seeker-ai-manage
log_success "管理脚本创建完成"

# 18. 健康检查
log_info "执行健康检查..."
sleep 5

# 检查PM2状态
PM2_STATUS=$(sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 list | grep $SERVICE_NAME || echo "")
if [[ $PM2_STATUS == *"online"* ]]; then
    log_success "PM2服务运行正常"
else
    log_warning "PM2服务可能有问题"
fi

# 检查端口监听
if netstat -tulpn | grep -q ":3000"; then
    log_success "应用正在监听3000端口"
else
    log_warning "应用未正常启动"
fi

# 检查Nginx状态
if systemctl is-active --quiet nginx; then
    log_success "Nginx服务运行正常"
else
    log_warning "Nginx服务异常"
fi

# 测试API
log_info "测试API接口..."
sleep 2
API_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health)
if [ "$API_TEST" = "200" ]; then
    log_success "API健康检查通过"
else
    log_warning "API健康检查失败 (HTTP $API_TEST)"
fi

echo ""
echo "🎉 重新部署完成！"
echo "========================================"
echo ""
echo "📊 部署信息:"
echo "   项目目录: $PROJECT_DIR"
echo "   备份目录: $BACKUP_DIR"
echo "   服务器IP: $(curl -s ifconfig.me 2>/dev/null || echo '获取失败')"
echo ""
echo "🌐 访问地址:"
echo "   HTTP: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP')"
echo "   直接: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'):3000"
echo ""
echo "🔧 管理命令:"
echo "   查看状态: seeker-ai-manage status"
echo "   重启服务: seeker-ai-manage restart"
echo "   查看日志: seeker-ai-manage logs"
echo ""
echo "📝 日志文件: /tmp/clean-redeploy.log"
echo ""

# 显示最终状态
echo "📋 最终状态检查:"
echo "=================="
echo "PM2状态:"
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 list

echo ""
echo "健康检查:"
curl -s http://localhost:3000/health | head -5

echo ""
echo "✅ 如果上述显示正常，说明部署成功！" 