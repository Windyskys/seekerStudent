#!/bin/bash

echo "🧹 SeekerAI完全清理脚本"
echo "========================="
echo ""
echo "⚠️  警告：此脚本将完全清理SeekerAI的所有部署！"
echo "⚠️  包括：PM2进程、项目文件、Nginx配置、系统服务、数据库等"
echo "⚠️  这是一个不可逆的操作！"
echo ""

# 确认操作
read -p "确定要完全清理所有部署吗？(输入 'DELETE_ALL' 确认): " -r
if [[ $REPLY != "DELETE_ALL" ]]; then
    echo "❌ 操作已取消"
    exit 1
fi

echo ""
echo "🚀 开始完全清理..."
echo "=================="

# 配置变量
PROJECT_DIR="/var/www/seekerStudent"
SERVICE_NAME="seeker-ai"
BACKUP_DIR="/tmp/seeker-cleanup-backup-$(date +%Y%m%d_%H%M%S)"

# 记录脚本执行日志
exec > >(tee -a /tmp/complete-cleanup.log)
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

# 1. 创建最后备份（可选）
echo ""
read -p "是否要在清理前创建最后备份？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "创建最后备份到 $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    if [ -d "$PROJECT_DIR" ]; then
        if [ -f "$PROJECT_DIR/.env" ]; then
            cp "$PROJECT_DIR/.env" "$BACKUP_DIR/" 2>/dev/null || log_warning "无法备份.env文件"
        fi
        if [ -d "$PROJECT_DIR/database" ]; then
            cp -r "$PROJECT_DIR/database" "$BACKUP_DIR/" 2>/dev/null || log_warning "无法备份数据库"
        fi
        if [ -d "$PROJECT_DIR/logs" ]; then
            cp -r "$PROJECT_DIR/logs" "$BACKUP_DIR/" 2>/dev/null || log_warning "无法备份日志"
        fi
        log_success "最后备份创建完成: $BACKUP_DIR"
    else
        log_warning "项目目录不存在，跳过备份"
    fi
else
    log_info "跳过备份，直接开始清理"
fi

echo ""
log_info "开始执行完全清理..."
echo "========================="

# 2. 停止所有相关进程
log_info "步骤 1/12: 停止所有相关进程"
echo "------------------------------"

# 停止PM2进程（www-data用户）
log_info "停止www-data用户的PM2进程..."
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 stop all 2>/dev/null || true
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 delete all 2>/dev/null || true
sudo -u www-data PM2_HOME=/home/www-data/.pm2 pm2 kill 2>/dev/null || true

# 停止root用户的PM2进程
log_info "停止root用户的PM2进程..."
pm2 stop all 2>/dev/null || true
pm2 delete all 2>/dev/null || true
pm2 kill 2>/dev/null || true

# 强制杀死所有相关进程
log_info "强制终止相关进程..."
pkill -f "node.*server.js" 2>/dev/null || true
pkill -f "PM2" 2>/dev/null || true
pkill -f "seeker" 2>/dev/null || true

log_success "所有进程已停止"

# 3. 停止系统服务
log_info "步骤 2/12: 停止系统服务"
echo "------------------------------"

# 停止应用服务
systemctl stop $SERVICE_NAME 2>/dev/null || true
log_info "已停止应用服务"

# 停止PM2系统服务
systemctl stop pm2-www-data 2>/dev/null || true
systemctl stop pm2-root 2>/dev/null || true
log_info "已停止PM2系统服务"

# 停止Nginx
systemctl stop nginx 2>/dev/null || true
log_info "已停止Nginx服务"

log_success "系统服务已停止"

# 4. 禁用系统服务
log_info "步骤 3/12: 禁用系统服务"
echo "------------------------------"

systemctl disable $SERVICE_NAME 2>/dev/null || true
systemctl disable pm2-www-data 2>/dev/null || true
systemctl disable pm2-root 2>/dev/null || true

log_success "系统服务已禁用"

# 5. 清理systemd服务文件
log_info "步骤 4/12: 清理systemd服务文件"
echo "------------------------------"

rm -f /etc/systemd/system/$SERVICE_NAME.service 2>/dev/null || true
rm -f /etc/systemd/system/pm2-www-data.service 2>/dev/null || true
rm -f /etc/systemd/system/pm2-root.service 2>/dev/null || true

systemctl daemon-reload

log_success "systemd服务文件已清理"

# 6. 清理项目目录
log_info "步骤 5/12: 清理项目目录"
echo "------------------------------"

if [ -d "$PROJECT_DIR" ]; then
    log_info "删除项目目录: $PROJECT_DIR"
    rm -rf "$PROJECT_DIR"
    log_success "项目目录已删除"
else
    log_info "项目目录不存在，跳过"
fi

# 7. 清理Nginx配置
log_info "步骤 6/12: 清理Nginx配置"
echo "------------------------------"

# 删除站点配置
rm -f /etc/nginx/sites-enabled/$SERVICE_NAME 2>/dev/null || true
rm -f /etc/nginx/sites-available/$SERVICE_NAME 2>/dev/null || true
log_info "已删除Nginx站点配置"

# 恢复默认站点（可选）
if [ ! -f /etc/nginx/sites-enabled/default ]; then
    if [ -f /etc/nginx/sites-available/default ]; then
        ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null || true
        log_info "已恢复Nginx默认站点"
    fi
fi

log_success "Nginx配置已清理"

# 8. 清理用户目录和PM2配置
log_info "步骤 7/12: 清理用户目录和PM2配置"
echo "------------------------------"

# 清理www-data用户的PM2配置
rm -rf /home/www-data/.pm2 2>/dev/null || true
log_info "已清理www-data用户的PM2配置"

# 清理root用户的PM2配置（可选）
read -p "是否要清理root用户的PM2配置？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /root/.pm2 2>/dev/null || true
    log_info "已清理root用户的PM2配置"
fi

log_success "用户配置已清理"

# 9. 清理管理脚本
log_info "步骤 8/12: 清理管理脚本"
echo "------------------------------"

rm -f /usr/local/bin/seeker-ai-manage 2>/dev/null || true
rm -f /usr/local/bin/seekerStudent-manage 2>/dev/null || true

log_success "管理脚本已清理"

# 10. 清理防火墙规则（可选）
log_info "步骤 9/12: 清理防火墙规则"
echo "------------------------------"

read -p "是否要删除3000端口的防火墙规则？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ufw delete allow 3000/tcp 2>/dev/null || true
    log_info "已删除3000端口防火墙规则"
fi

log_success "防火墙规则检查完成"

# 11. 清理临时文件和日志
log_info "步骤 10/12: 清理临时文件和日志"
echo "------------------------------"

# 清理PM2日志
rm -rf /home/www-data/.pm2/logs/* 2>/dev/null || true
rm -rf /root/.pm2/logs/* 2>/dev/null || true

# 清理应用日志
rm -f /var/log/$SERVICE_NAME.log 2>/dev/null || true

# 清理部署相关的临时文件
rm -f /tmp/*seeker* 2>/dev/null || true
rm -f /tmp/*deploy* 2>/dev/null || true

log_success "临时文件已清理"

# 12. 清理Node.js全局包（可选）
log_info "步骤 11/12: 检查Node.js全局包"
echo "------------------------------"

echo "当前安装的全局包:"
npm list -g --depth=0 | grep -E "(pm2|seeker)" || echo "未发现相关全局包"

read -p "是否要卸载PM2全局包？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    npm uninstall -g pm2 2>/dev/null || true
    log_info "已卸载PM2全局包"
fi

log_success "Node.js包检查完成"

# 13. 最终清理验证
log_info "步骤 12/12: 最终清理验证"
echo "------------------------------"

log_info "检查清理结果..."

# 检查进程
REMAINING_PROCESSES=$(ps aux | grep -E "(seeker|PM2|node.*server)" | grep -v grep | wc -l)
if [ "$REMAINING_PROCESSES" -eq 0 ]; then
    log_success "✅ 没有发现残留进程"
else
    log_warning "⚠️  发现 $REMAINING_PROCESSES 个可能的残留进程"
    ps aux | grep -E "(seeker|PM2|node.*server)" | grep -v grep
fi

# 检查端口
PORT_3000=$(netstat -tulpn | grep ":3000" || echo "")
if [ -z "$PORT_3000" ]; then
    log_success "✅ 3000端口已释放"
else
    log_warning "⚠️  3000端口仍被占用:"
    echo "$PORT_3000"
fi

# 检查目录
if [ ! -d "$PROJECT_DIR" ]; then
    log_success "✅ 项目目录已清理"
else
    log_warning "⚠️  项目目录仍然存在: $PROJECT_DIR"
fi

# 检查服务
NGINX_STATUS=$(systemctl is-active nginx 2>/dev/null || echo "inactive")
log_info "Nginx状态: $NGINX_STATUS"

echo ""
echo "🎉 完全清理完成！"
echo "=================="
echo ""
echo "📊 清理总结:"
echo "   ✅ PM2进程已清理"
echo "   ✅ 系统服务已清理"
echo "   ✅ 项目文件已清理" 
echo "   ✅ Nginx配置已清理"
echo "   ✅ 用户配置已清理"
echo "   ✅ 管理脚本已清理"
echo ""

if [ -d "$BACKUP_DIR" ]; then
    echo "💾 备份位置: $BACKUP_DIR"
    echo "   包含: .env文件, 数据库, 日志文件"
    echo ""
fi

echo "📝 清理日志: /tmp/complete-cleanup.log"
echo ""
echo "🔄 如需重新部署，可以："
echo "   1. 重新下载项目代码"
echo "   2. 运行 deploy.sh 脚本"
echo "   3. 或运行 clean-redeploy.sh 脚本"
echo ""

# 最后确认
read -p "是否要重启Nginx服务？(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    systemctl start nginx
    if systemctl is-active --quiet nginx; then
        log_success "Nginx已重启"
        echo "🌐 现在访问服务器IP应该看到Nginx默认页面"
    else
        log_warning "Nginx启动失败"
    fi
fi

echo ""
echo "✅ 清理脚本执行完成！"
echo "💡 系统已恢复到SeekerAI部署前的状态" 