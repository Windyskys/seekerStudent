#!/bin/bash

# SeekerAI智能学习平台 - Ubuntu服务器部署脚本
# 适用于全新的Ubuntu服务器环境

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 配置变量
PROJECT_NAME="seekerStudent"
PROJECT_DIR="/var/www/$PROJECT_NAME"
SERVICE_NAME="seeker-ai"
DOMAIN_NAME=""  # 可选：如果有域名就填写
NODE_VERSION="18"  # Node.js版本

echo "=========================================="
echo "  SeekerAI智能学习平台 Ubuntu部署脚本"
echo "=========================================="
echo ""

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root权限运行此脚本: sudo $0"
    exit 1
fi

# 1. 系统信息检查
log_info "检查系统信息..."
echo "操作系统: $(lsb_release -d | cut -f2)"
echo "内核版本: $(uname -r)"
echo "架构: $(uname -m)"
echo ""

# 2. 更新系统包
log_info "更新系统包..."
apt update -y
apt upgrade -y

# 3. 安装基础依赖
log_info "安装基础依赖..."
apt install -y curl wget git unzip software-properties-common ufw nginx

# 4. 安装Node.js
log_info "安装Node.js $NODE_VERSION..."
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
apt install -y nodejs

# 验证安装
NODE_VERSION_INSTALLED=$(node --version)
NPM_VERSION_INSTALLED=$(npm --version)
log_success "Node.js 安装成功: $NODE_VERSION_INSTALLED"
log_success "npm 安装成功: $NPM_VERSION_INSTALLED"

# 5. 安装PM2（进程管理器）
log_info "安装PM2进程管理器..."
npm install -g pm2

# 6. 创建项目目录
log_info "创建项目目录..."
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# 7. 获取项目代码（假设从当前目录复制，实际部署时可能从Git获取）
log_info "部署项目文件..."
echo "请将项目文件上传到 $PROJECT_DIR 目录"
echo "或者从Git仓库克隆："
echo "  git clone <your-repo-url> ."
echo ""
read -p "项目文件是否已准备好？(y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_warning "请先准备项目文件，然后重新运行脚本"
    exit 1
fi

# 8. 安装项目依赖
log_info "安装项目依赖..."
if [ -f "package.json" ]; then
    npm install --production
    log_success "依赖安装完成"
else
    log_error "未找到package.json文件，请确保项目文件已正确上传"
    exit 1
fi

# 9. 配置环境变量
log_info "配置环境变量..."
if [ ! -f ".env" ]; then
    log_info "创建环境配置文件..."
    cat > .env << EOL
# 阿里百炼API配置（Qwen-Plus模型）
QWEN_API_KEY=sk-0eaf3643806f4d4991eedd3dc7f5aa2e
DASHSCOPE_BASE_URL=https://dashscope.aliyuncs.com/api/v1

# 服务器配置
PORT=3000
NODE_ENV=production

# 数据库配置
DB_PATH=./database/seeker_ai.db
EOL
    
    log_warning "请编辑 $PROJECT_DIR/.env 文件，添加您的QWEN_API_KEY"
    echo "获取API密钥: https://dashscope.aliyun.com/"
    echo ""
    read -p "是否现在编辑环境变量？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        nano .env
    fi
fi

# 10. 创建数据库目录
log_info "创建数据库目录..."
mkdir -p database
chown -R www-data:www-data database
chmod 755 database

# 11. 设置文件权限
log_info "设置文件权限..."
chown -R www-data:www-data $PROJECT_DIR
chmod -R 755 $PROJECT_DIR
chmod 644 $PROJECT_DIR/.env

# 12. 配置PM2
log_info "配置PM2进程管理..."
cat > ecosystem.config.js << EOL
module.exports = {
  apps: [{
    name: '$SERVICE_NAME',
    script: 'server.js',
    instances: 'max',
    exec_mode: 'cluster',
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true
  }]
};
EOL

# 创建日志目录
mkdir -p logs
chown -R www-data:www-data logs

# 13. 配置防火墙
log_info "配置防火墙..."
ufw --force enable
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 3000/tcp
log_success "防火墙配置完成"

# 14. 配置Nginx反向代理
log_info "配置Nginx反向代理..."
cat > /etc/nginx/sites-available/$SERVICE_NAME << EOL
server {
    listen 80;
    server_name ${DOMAIN_NAME:-localhost};

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }

    # 静态文件缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://localhost:3000;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOL

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

# 15. 启动服务
log_info "启动应用服务..."

# 以www-data用户身份启动PM2
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 start ecosystem.config.js
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 save
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 startup

# 重启Nginx
systemctl restart nginx
systemctl enable nginx

# 16. 创建系统服务（备用方案）
log_info "创建系统服务..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOL
[Unit]
Description=SeekerAI Learning Platform
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable $SERVICE_NAME

# 17. 健康检查
log_info "执行健康检查..."
sleep 5

# 检查PM2状态
PM2_STATUS=$(sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 list | grep $SERVICE_NAME || echo "")
if [[ $PM2_STATUS == *"online"* ]]; then
    log_success "PM2服务运行正常"
else
    log_warning "PM2服务可能有问题，尝试使用systemd服务"
    systemctl start $SERVICE_NAME
fi

# 检查端口监听
if netstat -tulpn | grep -q ":3000"; then
    log_success "应用正在监听3000端口"
else
    log_error "应用未正常启动，请检查日志"
fi

# 检查Nginx状态
if systemctl is-active --quiet nginx; then
    log_success "Nginx服务运行正常"
else
    log_error "Nginx服务异常"
fi

# 18. 安装SSL证书（可选）
echo ""
read -p "是否要安装Let's Encrypt SSL证书？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] && [ ! -z "$DOMAIN_NAME" ]; then
    log_info "安装Certbot..."
    apt install -y certbot python3-certbot-nginx
    
    log_info "获取SSL证书..."
    certbot --nginx -d $DOMAIN_NAME --non-interactive --agree-tos --email admin@$DOMAIN_NAME
    
    # 设置自动续期
    crontab -l | { cat; echo "0 12 * * * /usr/bin/certbot renew --quiet"; } | crontab -
    log_success "SSL证书安装完成"
fi

# 19. 创建维护脚本
log_info "创建维护脚本..."
cat > /usr/local/bin/seeker-ai-manage << 'EOL'
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
    update)
        echo "更新应用..."
        cd $PROJECT_DIR
        git pull
        npm install --production
        sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 restart $SERVICE_NAME
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status|logs|update}"
        exit 1
        ;;
esac
EOL

chmod +x /usr/local/bin/seeker-ai-manage

# 20. 部署完成
echo ""
echo "=========================================="
log_success "部署完成！"
echo "=========================================="
echo ""
echo "🌐 应用访问地址:"
echo "   HTTP:  http://$(curl -s ifconfig.me):80"
echo "   直接:  http://$(curl -s ifconfig.me):3000"
if [ ! -z "$DOMAIN_NAME" ]; then
    echo "   域名:  http://$DOMAIN_NAME"
fi
echo ""
echo "📁 项目目录: $PROJECT_DIR"
echo "📝 配置文件: $PROJECT_DIR/.env"
echo "📊 日志目录: $PROJECT_DIR/logs"
echo ""
echo "🔧 管理命令:"
echo "   启动服务: seeker-ai-manage start"
echo "   停止服务: seeker-ai-manage stop"
echo "   重启服务: seeker-ai-manage restart"
echo "   查看状态: seeker-ai-manage status"
echo "   查看日志: seeker-ai-manage logs"
echo "   更新应用: seeker-ai-manage update"
echo ""
echo "⚠️  重要提醒:"
echo "1. 请编辑 $PROJECT_DIR/.env 文件，配置您的QWEN_API_KEY"
echo "2. 默认端口3000已开放，可通过Nginx代理访问80端口"
echo "3. 建议配置域名并启用SSL证书"
echo "4. 定期备份数据库文件: $PROJECT_DIR/database/seeker_ai.db"
echo ""
echo "🎉 开始使用您的AI学习平台吧！" 