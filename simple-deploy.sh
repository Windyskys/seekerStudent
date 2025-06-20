#!/bin/bash

echo "🚀 SeekerAI简单部署脚本"
echo "======================="
echo ""
echo "此脚本将："
echo "  ✅ 使用systemd直接管理Node.js服务"
echo "  ✅ 配置Nginx反向代理"
echo "  ✅ 不使用PM2等复杂管理工具"
echo "  ✅ 简单易维护"
echo ""

# 确认操作
read -p "确定要开始部署吗？(y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ 部署已取消"
    exit 1
fi

echo "🚀 开始简单部署..."
echo "=================="

# 配置变量
PROJECT_DIR="/var/www/seekerStudent"
SERVICE_NAME="seeker-ai"
SERVICE_USER="seekeruser"

# 日志函数
log_info() {
    echo "[$(date '+%H:%M:%S')] [INFO] $1"
}

log_success() {
    echo "[$(date '+%H:%M:%S')] [SUCCESS] $1"
}

log_error() {
    echo "[$(date '+%H:%M:%S')] [ERROR] $1"
}

# 检查运行权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用sudo运行此脚本"
    exit 1
fi

# 1. 更新系统包
log_info "更新系统包..."
apt update -y
log_success "系统包更新完成"

# 2. 安装必要软件
log_info "安装必要软件..."
apt install -y curl wget software-properties-common gnupg2

# 安装Node.js 18
if ! command -v node &> /dev/null; then
    log_info "安装Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    log_success "Node.js安装完成"
else
    log_info "Node.js已安装，版本：$(node --version)"
fi

# 安装Nginx
if ! command -v nginx &> /dev/null; then
    log_info "安装Nginx..."
    apt install -y nginx
    log_success "Nginx安装完成"
else
    log_info "Nginx已安装"
fi

# 3. 创建服务用户
log_info "创建服务用户..."
if ! id -u $SERVICE_USER > /dev/null 2>&1; then
    useradd -r -s /bin/bash -d /home/$SERVICE_USER -m $SERVICE_USER
    log_success "用户 $SERVICE_USER 创建完成"
else
    log_info "用户 $SERVICE_USER 已存在"
fi

# 4. 创建项目目录
log_info "创建项目目录..."
rm -rf $PROJECT_DIR
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# 5. 复制项目文件
log_info "复制项目文件..."
CURRENT_DIR=$(pwd)
if [ -f "$CURRENT_DIR/server.js" ] && [ -f "$CURRENT_DIR/package.json" ]; then
    SOURCE_DIR="$CURRENT_DIR"
elif [ -f "/root/seekerStudent/server.js" ]; then
    SOURCE_DIR="/root/seekerStudent"
else
    # 从Git仓库克隆
    log_info "从Git仓库获取项目代码..."
    git clone https://github.com/Windyskys/seekerStudent.git temp_clone
    SOURCE_DIR="$PWD/temp_clone"
fi

if [ -d "$SOURCE_DIR" ]; then
    rsync -av --exclude='.git' --exclude='node_modules' --exclude='.DS_Store' \
        "$SOURCE_DIR/" "$PROJECT_DIR/"
    
    # 清理临时目录
    if [ -d "$PROJECT_DIR/temp_clone" ]; then
        rm -rf "$PROJECT_DIR/temp_clone"
    fi
    
    log_success "项目文件复制完成"
else
    log_error "找不到项目源码"
    exit 1
fi

# 6. 创建环境变量文件
log_info "创建环境变量文件..."
cat > .env << 'EOF'
NODE_ENV=production
PORT=3000
QWEN_API_KEY=sk-0eaf3643806f4d4991eedd3dc7f5aa2e
DB_PATH=./database/seeker_ai.db
EOF
log_success "环境变量文件创建完成"

# 7. 创建必要目录
log_info "创建必要目录..."
mkdir -p database logs
touch database/seeker_ai.db
log_success "目录创建完成"

# 8. 安装依赖
log_info "安装项目依赖..."
npm install --production --unsafe-perm
log_success "依赖安装完成"

# 9. 设置文件权限
log_info "设置文件权限..."
chown -R $SERVICE_USER:$SERVICE_USER $PROJECT_DIR
chmod -R 755 $PROJECT_DIR
chmod 644 .env
log_success "文件权限设置完成"

# 10. 创建systemd服务
log_info "创建systemd服务..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=SeekerAI Learning Platform
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME
log_success "systemd服务创建完成"

# 11. 配置防火墙
log_info "配置防火墙..."
ufw --force enable
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3000/tcp
log_success "防火墙配置完成"

# 12. 配置Nginx
log_info "配置Nginx..."
cat > /etc/nginx/sites-available/$SERVICE_NAME << 'EOF'
server {
    listen 80;
    server_name _;

    # 主要代理配置
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

    # 静态文件缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://localhost:3000;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # API路由
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# 启用站点
ln -sf /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 测试Nginx配置
nginx -t
if [ $? -eq 0 ]; then
    log_success "Nginx配置验证通过"
else
    log_error "Nginx配置验证失败"
    exit 1
fi

# 13. 启动服务
log_info "启动服务..."

# 启动应用
systemctl start $SERVICE_NAME
if systemctl is-active --quiet $SERVICE_NAME; then
    log_success "应用服务启动成功"
else
    log_error "应用服务启动失败"
    journalctl -u $SERVICE_NAME --no-pager -l
fi

# 启动Nginx
systemctl restart nginx
systemctl enable nginx
if systemctl is-active --quiet nginx; then
    log_success "Nginx服务启动成功"
else
    log_error "Nginx服务启动失败"
fi

# 14. 创建管理脚本
log_info "创建管理脚本..."
cat > /usr/local/bin/seeker-manage << EOF
#!/bin/bash

SERVICE_NAME="$SERVICE_NAME"
PROJECT_DIR="$PROJECT_DIR"

case "\$1" in
    start)
        echo "启动SeekerAI服务..."
        systemctl start \$SERVICE_NAME
        systemctl start nginx
        ;;
    stop)
        echo "停止SeekerAI服务..."
        systemctl stop \$SERVICE_NAME
        ;;
    restart)
        echo "重启SeekerAI服务..."
        systemctl restart \$SERVICE_NAME
        systemctl restart nginx
        ;;
    status)
        echo "SeekerAI服务状态:"
        systemctl status \$SERVICE_NAME --no-pager -l
        echo ""
        echo "Nginx状态:"
        systemctl status nginx --no-pager -l
        ;;
    logs)
        echo "查看应用日志:"
        journalctl -u \$SERVICE_NAME -f
        ;;
    update)
        echo "更新应用..."
        cd \$PROJECT_DIR
        git pull
        npm install --production
        systemctl restart \$SERVICE_NAME
        ;;
    *)
        echo "用法: \$0 {start|stop|restart|status|logs|update}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/seeker-manage
log_success "管理脚本创建完成"

# 15. 健康检查
log_info "执行健康检查..."
sleep 3

# 检查端口监听
if netstat -tulpn | grep -q ":3000"; then
    log_success "应用正在监听3000端口"
else
    log_error "应用未正常启动"
fi

# 检查API
API_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null)
if [ "$API_TEST" = "200" ]; then
    log_success "API健康检查通过"
else
    log_error "API健康检查失败 (HTTP $API_TEST)"
fi

echo ""
echo "🎉 简单部署完成！"
echo "=================="
echo ""
echo "📊 部署信息:"
echo "   项目目录: $PROJECT_DIR"
echo "   服务用户: $SERVICE_USER"
echo "   系统服务: $SERVICE_NAME"
echo "   服务器IP: $(curl -s ifconfig.me 2>/dev/null || echo '获取失败')"
echo ""
echo "🌐 访问地址:"
echo "   HTTP: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP')"
echo "   直接: http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'):3000"
echo ""
echo "🔧 管理命令:"
echo "   启动服务: seeker-manage start"
echo "   停止服务: seeker-manage stop"
echo "   重启服务: seeker-manage restart"
echo "   查看状态: seeker-manage status"
echo "   查看日志: seeker-manage logs"
echo "   更新应用: seeker-manage update"
echo ""
echo "📋 服务状态:"
systemctl status $SERVICE_NAME --no-pager -l | head -5
echo ""
echo "🌐 测试访问:"
curl -s http://localhost:3000/health | head -3 || echo "API连接失败"

echo ""
echo "✅ 部署完成！现在可以通过浏览器访问您的应用了！" 