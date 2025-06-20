#!/bin/bash

# SeekerAI智能学习平台 - Ubuntu服务器重新部署脚本
# 适用于生产环境的完整重新部署

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
PROJECT_NAME="seekerStudent"
PROJECT_DIR="/var/www/seekerStudent"
SERVICE_NAME="seeker-ai"
NGINX_CONF="/etc/nginx/sites-available/seekerStudent"
USER="www-data"
PORT=3000
API_KEY="sk-0eaf3643806f4d4991eedd3dc7f5aa2e"

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

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 备份数据库
backup_database() {
    log_info "备份数据库..."
    
    if [ -f "$PROJECT_DIR/database/seeker_ai.db" ]; then
        BACKUP_DIR="$PROJECT_DIR/backup/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        cp "$PROJECT_DIR/database/seeker_ai.db" "$BACKUP_DIR/seeker_ai.db.backup"
        log_success "数据库已备份到: $BACKUP_DIR"
    else
        log_warning "未找到数据库文件，跳过备份"
    fi
}

# 停止现有服务
stop_services() {
    log_info "停止现有服务..."
    
    # 停止systemd服务
    if systemctl is-active --quiet $SERVICE_NAME; then
        systemctl stop $SERVICE_NAME
        log_success "已停止 $SERVICE_NAME 服务"
    fi
    
    # 停止nginx（如果运行中）
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx
        log_success "已重载nginx配置"
    fi
    
    # 确保端口未被占用
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        log_warning "端口 $PORT 仍被占用，尝试终止进程..."
        fuser -k $PORT/tcp || true
        sleep 2
    fi
}

# 更新系统依赖
update_system() {
    log_info "更新系统依赖..."
    
    apt update > /dev/null 2>&1
    
    # 安装必要的软件包
    PACKAGES="nodejs npm nginx curl git"
    for package in $PACKAGES; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "安装 $package..."
            apt install -y $package > /dev/null 2>&1
        fi
    done
    
    log_success "系统依赖更新完成"
}

# 创建项目目录和用户
setup_project() {
    log_info "设置项目环境..."
    
    # 创建项目目录
    mkdir -p $PROJECT_DIR
    mkdir -p $PROJECT_DIR/database
    mkdir -p $PROJECT_DIR/backup
    mkdir -p $PROJECT_DIR/logs
    
    # 设置用户权限
    chown -R $USER:$USER $PROJECT_DIR
    chmod -R 755 $PROJECT_DIR
    
    log_success "项目环境设置完成"
}

# 部署代码
deploy_code() {
    log_info "部署代码文件..."
    
    # 如果当前目录有项目文件，复制过去
    if [ -f "./server.js" ] && [ -f "./package.json" ]; then
        log_info "从当前目录复制文件..."
        
        # 复制所有必要文件
        rsync -av --exclude=node_modules --exclude=.git --exclude=backup \
              --exclude="*.log" --exclude="*.tmp" \
              ./ $PROJECT_DIR/
        
        # 保持数据库文件不被覆盖（如果存在备份）
        if [ -f "$PROJECT_DIR/backup/"*"/seeker_ai.db.backup" ]; then
            LATEST_BACKUP=$(ls -t $PROJECT_DIR/backup/*/seeker_ai.db.backup | head -1)
            if [ -f "$LATEST_BACKUP" ]; then
                cp "$LATEST_BACKUP" "$PROJECT_DIR/database/seeker_ai.db"
                log_success "已恢复数据库备份"
            fi
        fi
        
    else
        log_error "当前目录未找到项目文件"
        log_info "请确保在包含 server.js 和 package.json 的目录中运行此脚本"
        exit 1
    fi
    
    # 设置文件权限
    chown -R $USER:$USER $PROJECT_DIR
    chmod +x $PROJECT_DIR/*.sh 2>/dev/null || true
    
    log_success "代码部署完成"
}

# 安装Node.js依赖
install_dependencies() {
    log_info "安装Node.js依赖..."
    
    cd $PROJECT_DIR
    
    # 清理旧的node_modules
    rm -rf node_modules package-lock.json
    
    # 以正确用户身份安装依赖
    sudo -u $USER npm install --production > /dev/null 2>&1
    
    log_success "依赖安装完成"
}

# 配置环境变量
setup_environment() {
    log_info "配置环境变量..."
    
    # 创建环境变量文件
    cat > $PROJECT_DIR/.env << EOF
NODE_ENV=production
PORT=$PORT
QWEN_API_KEY=$API_KEY
DB_PATH=./database/seeker_ai.db
EOF
    
    chown $USER:$USER $PROJECT_DIR/.env
    chmod 600 $PROJECT_DIR/.env
    
    log_success "环境变量配置完成"
}

# 配置systemd服务
setup_service() {
    log_info "配置systemd服务..."
    
    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=SeekerAI智能学习平台
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PROJECT_DIR
Environment=NODE_ENV=production
Environment=PORT=$PORT
Environment=QWEN_API_KEY=$API_KEY
Environment=DB_PATH=./database/seeker_ai.db
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载systemd并启用服务
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    
    log_success "systemd服务配置完成"
}

# 配置Nginx
setup_nginx() {
    log_info "配置Nginx..."
    
    cat > $NGINX_CONF << EOF
server {
    listen 80;
    server_name _;
    
    # 静态文件服务
    location / {
        root $PROJECT_DIR;
        index index.html;
        try_files \$uri \$uri/ @node;
    }
    
    # API请求代理到Node.js
    location /api/ {
        proxy_pass http://localhost:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
        proxy_send_timeout 300;
    }
    
    # 健康检查
    location /health {
        proxy_pass http://localhost:$PORT;
        access_log off;
    }
    
    # Node.js fallback
    location @node {
        proxy_pass http://localhost:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # 安全设置
    location ~ /\.ht {
        deny all;
    }
    
    location ~ /\.git {
        deny all;
    }
    
    # 静态资源缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        root $PROJECT_DIR;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF
    
    # 启用站点
    ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # 测试nginx配置
    if nginx -t > /dev/null 2>&1; then
        log_success "Nginx配置有效"
    else
        log_error "Nginx配置无效"
        nginx -t
        exit 1
    fi
}

# 启动服务
start_services() {
    log_info "启动服务..."
    
    # 启动Node.js服务
    systemctl start $SERVICE_NAME
    
    # 等待服务启动
    sleep 5
    
    # 检查服务状态
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_success "SeekerAI服务启动成功"
    else
        log_error "SeekerAI服务启动失败"
        systemctl status $SERVICE_NAME
        exit 1
    fi
    
    # 重启nginx
    systemctl restart nginx
    
    if systemctl is-active --quiet nginx; then
        log_success "Nginx服务启动成功"
    else
        log_error "Nginx服务启动失败"
        systemctl status nginx
        exit 1
    fi
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    
    # 等待服务完全启动
    sleep 3
    
    # 检查端口监听
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        log_success "端口 $PORT 监听正常"
    else
        log_error "端口 $PORT 未监听"
        exit 1
    fi
    
    # 检查API健康
    for i in {1..5}; do
        if curl -s -f "http://localhost:$PORT/health" > /dev/null 2>&1; then
            log_success "API健康检查通过"
            break
        else
            if [ $i -eq 5 ]; then
                log_error "API健康检查失败"
                exit 1
            fi
            log_info "等待API启动... ($i/5)"
            sleep 2
        fi
    done
    
    # 检查Web访问
    if curl -s -f "http://localhost/health" > /dev/null 2>&1; then
        log_success "Web访问正常"
    else
        log_warning "Web访问可能有问题，请检查Nginx配置"
    fi
}

# 显示部署信息
show_info() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   SeekerAI 部署完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${BLUE}服务信息:${NC}"
    echo "  • 项目目录: $PROJECT_DIR"
    echo "  • 服务名称: $SERVICE_NAME"
    echo "  • 运行端口: $PORT"
    echo "  • 运行用户: $USER"
    echo ""
    echo -e "${BLUE}访问地址:${NC}"
    echo "  • 主页: http://$(hostname -I | awk '{print $1}')"
    echo "  • 综合评估: http://$(hostname -I | awk '{print $1}')/comprehensive-assessment.html"
    echo "  • 数据看板: http://$(hostname -I | awk '{print $1}')/dashboard.html"
    echo "  • API健康: http://$(hostname -I | awk '{print $1}')/health"
    echo ""
    echo -e "${BLUE}管理命令:${NC}"
    echo "  • 查看状态: systemctl status $SERVICE_NAME"
    echo "  • 重启服务: systemctl restart $SERVICE_NAME"
    echo "  • 查看日志: journalctl -u $SERVICE_NAME -f"
    echo "  • 停止服务: systemctl stop $SERVICE_NAME"
    echo ""
    echo -e "${BLUE}文件位置:${NC}"
    echo "  • 服务配置: /etc/systemd/system/$SERVICE_NAME.service"
    echo "  • Nginx配置: $NGINX_CONF"
    echo "  • 环境变量: $PROJECT_DIR/.env"
    echo "  • 数据库: $PROJECT_DIR/database/seeker_ai.db"
    echo "  • 日志: journalctl -u $SERVICE_NAME"
    echo ""
}

# 清理函数（出错时调用）
cleanup_on_error() {
    log_error "部署过程中出现错误，正在清理..."
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    systemctl daemon-reload
    exit 1
}

# 主函数
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   SeekerAI Ubuntu服务器重新部署${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # 设置错误处理
    trap cleanup_on_error ERR
    
    # 执行部署步骤
    check_root
    backup_database
    stop_services
    update_system
    setup_project
    deploy_code
    install_dependencies
    setup_environment
    setup_service
    setup_nginx
    start_services
    health_check
    show_info
    
    log_success "部署完成！SeekerAI智能学习平台已成功部署到Ubuntu服务器"
}

# 运行主函数
main "$@"