#!/bin/bash

# SeekerAI智能学习平台 - Ubuntu服务器管理脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置变量
SERVICE_NAME="seeker-ai"
PROJECT_DIR="/var/www/seekerStudent"
PORT=3000

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

# 显示使用帮助
show_help() {
    echo -e "${BLUE}SeekerAI Ubuntu服务器管理工具${NC}"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "可用命令:"
    echo "  start     - 启动服务"
    echo "  stop      - 停止服务"
    echo "  restart   - 重启服务"
    echo "  status    - 查看服务状态"
    echo "  logs      - 查看服务日志"
    echo "  health    - 健康检查"
    echo "  update    - 更新代码并重启"
    echo "  backup    - 备份数据库"
    echo "  restore   - 恢复数据库"
    echo "  monitor   - 实时监控"
    echo "  info      - 显示服务信息"
    echo "  help      - 显示此帮助"
    echo ""
}

# 启动服务
start_service() {
    log_info "启动SeekerAI服务..."
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_warning "服务已在运行中"
        return 0
    fi
    
    systemctl start $SERVICE_NAME
    systemctl start nginx
    
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_success "服务启动成功"
    else
        log_error "服务启动失败"
        systemctl status $SERVICE_NAME
        return 1
    fi
}

# 停止服务
stop_service() {
    log_info "停止SeekerAI服务..."
    
    if ! systemctl is-active --quiet $SERVICE_NAME; then
        log_warning "服务未运行"
        return 0
    fi
    
    systemctl stop $SERVICE_NAME
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_error "服务停止失败"
        return 1
    else
        log_success "服务已停止"
    fi
}

# 重启服务
restart_service() {
    log_info "重启SeekerAI服务..."
    
    systemctl restart $SERVICE_NAME
    systemctl reload nginx
    
    sleep 3
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_success "服务重启成功"
    else
        log_error "服务重启失败"
        systemctl status $SERVICE_NAME
        return 1
    fi
}

# 查看服务状态
show_status() {
    echo -e "${BLUE}=== 服务状态 ===${NC}"
    
    # Node.js服务状态
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "SeekerAI服务: ${GREEN}运行中${NC}"
    else
        echo -e "SeekerAI服务: ${RED}已停止${NC}"
    fi
    
    # Nginx状态
    if systemctl is-active --quiet nginx; then
        echo -e "Nginx服务: ${GREEN}运行中${NC}"
    else
        echo -e "Nginx服务: ${RED}已停止${NC}"
    fi
    
    # 端口监听状态
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "端口 $PORT: ${GREEN}监听中${NC}"
    else
        echo -e "端口 $PORT: ${RED}未监听${NC}"
    fi
    
    # API健康状态
    if curl -s -f "http://localhost:$PORT/health" > /dev/null 2>&1; then
        echo -e "API健康: ${GREEN}正常${NC}"
    else
        echo -e "API健康: ${RED}异常${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}=== 详细状态 ===${NC}"
    systemctl status $SERVICE_NAME --no-pager
}

# 查看日志
show_logs() {
    log_info "显示SeekerAI服务日志 (按 Ctrl+C 退出)..."
    journalctl -u $SERVICE_NAME -f --no-pager
}

# 健康检查
health_check() {
    log_info "执行健康检查..."
    
    local errors=0
    
    # 检查服务状态
    if ! systemctl is-active --quiet $SERVICE_NAME; then
        log_error "SeekerAI服务未运行"
        ((errors++))
    else
        log_success "SeekerAI服务运行正常"
    fi
    
    # 检查Nginx状态
    if ! systemctl is-active --quiet nginx; then
        log_error "Nginx服务未运行"
        ((errors++))
    else
        log_success "Nginx服务运行正常"
    fi
    
    # 检查端口监听
    if ! lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        log_error "端口 $PORT 未监听"
        ((errors++))
    else
        log_success "端口监听正常"
    fi
    
    # 检查API健康
    if curl -s -f "http://localhost:$PORT/health" > /dev/null 2>&1; then
        log_success "API健康检查通过"
    else
        log_error "API健康检查失败"
        ((errors++))
    fi
    
    # 检查数据库文件
    if [ -f "$PROJECT_DIR/database/seeker_ai.db" ]; then
        log_success "数据库文件存在"
    else
        log_error "数据库文件不存在"
        ((errors++))
    fi
    
    # 检查磁盘空间
    local disk_usage=$(df $PROJECT_DIR | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        log_error "磁盘空间不足 ($disk_usage%)"
        ((errors++))
    else
        log_success "磁盘空间充足 ($disk_usage%)"
    fi
    
    # 检查内存使用
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$mem_usage" -gt 90 ]; then
        log_warning "内存使用率较高 ($mem_usage%)"
    else
        log_success "内存使用正常 ($mem_usage%)"
    fi
    
    echo ""
    if [ $errors -eq 0 ]; then
        log_success "所有检查项目通过"
        return 0
    else
        log_error "发现 $errors 个问题"
        return 1
    fi
}

# 更新代码
update_code() {
    log_info "更新代码并重启服务..."
    
    if [ ! -f "./server.js" ]; then
        log_error "当前目录未找到项目文件"
        log_info "请在包含项目文件的目录中运行此命令"
        return 1
    fi
    
    # 停止服务
    systemctl stop $SERVICE_NAME
    
    # 备份数据库
    backup_database
    
    # 更新代码
    log_info "更新项目文件..."
    rsync -av --exclude=node_modules --exclude=.git --exclude=backup \
          --exclude="*.log" --exclude="*.tmp" --exclude=database \
          ./ $PROJECT_DIR/
    
    # 更新依赖
    cd $PROJECT_DIR
    sudo -u www-data npm install --production > /dev/null 2>&1
    
    # 重启服务
    systemctl start $SERVICE_NAME
    
    # 检查状态
    sleep 3
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_success "代码更新并重启成功"
    else
        log_error "更新后服务启动失败"
        systemctl status $SERVICE_NAME
        return 1
    fi
}

# 备份数据库
backup_database() {
    log_info "备份数据库..."
    
    if [ ! -f "$PROJECT_DIR/database/seeker_ai.db" ]; then
        log_warning "数据库文件不存在，跳过备份"
        return 0
    fi
    
    local backup_dir="$PROJECT_DIR/backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    cp "$PROJECT_DIR/database/seeker_ai.db" "$backup_dir/seeker_ai.db.backup"
    
    # 压缩备份文件
    gzip "$backup_dir/seeker_ai.db.backup"
    
    log_success "数据库已备份到: $backup_dir"
    
    # 清理旧备份（保留最近10个）
    find "$PROJECT_DIR/backup" -type d -name "20*" | sort -r | tail -n +11 | xargs rm -rf 2>/dev/null || true
}

# 恢复数据库
restore_database() {
    log_info "恢复数据库..."
    
    # 列出可用备份
    local backups=($(find "$PROJECT_DIR/backup" -name "*.backup.gz" -o -name "*.backup" | sort -r))
    
    if [ ${#backups[@]} -eq 0 ]; then
        log_error "未找到数据库备份文件"
        return 1
    fi
    
    echo "可用备份:"
    for i in "${!backups[@]}"; do
        echo "  $((i+1)). $(basename ${backups[i]})"
    done
    
    echo -n "请选择要恢复的备份编号 [1-${#backups[@]}]: "
    read -r choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#backups[@]} ]; then
        log_error "无效的选择"
        return 1
    fi
    
    local backup_file="${backups[$((choice-1))]}"
    
    # 停止服务
    systemctl stop $SERVICE_NAME
    
    # 备份当前数据库
    if [ -f "$PROJECT_DIR/database/seeker_ai.db" ]; then
        cp "$PROJECT_DIR/database/seeker_ai.db" "$PROJECT_DIR/database/seeker_ai.db.pre-restore"
    fi
    
    # 恢复数据库
    if [[ "$backup_file" == *.gz ]]; then
        gunzip -c "$backup_file" > "$PROJECT_DIR/database/seeker_ai.db"
    else
        cp "$backup_file" "$PROJECT_DIR/database/seeker_ai.db"
    fi
    
    chown www-data:www-data "$PROJECT_DIR/database/seeker_ai.db"
    
    # 重启服务
    systemctl start $SERVICE_NAME
    
    log_success "数据库恢复完成"
}

# 实时监控
monitor_service() {
    log_info "启动实时监控 (按 Ctrl+C 退出)..."
    
    while true; do
        clear
        echo -e "${BLUE}SeekerAI 实时监控 - $(date)${NC}"
        echo "=================================="
        
        # 服务状态
        if systemctl is-active --quiet $SERVICE_NAME; then
            echo -e "服务状态: ${GREEN}运行中${NC}"
        else
            echo -e "服务状态: ${RED}已停止${NC}"
        fi
        
        # 系统资源
        echo "CPU使用: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
        echo "内存使用: $(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
        echo "磁盘使用: $(df $PROJECT_DIR | awk 'NR==2 {print $5}')"
        
        # 网络连接
        local connections=$(netstat -an | grep ":$PORT" | wc -l)
        echo "活跃连接: $connections"
        
        # 最近日志
        echo ""
        echo -e "${BLUE}最近日志:${NC}"
        journalctl -u $SERVICE_NAME -n 5 --no-pager -o short
        
        sleep 5
    done
}

# 显示服务信息
show_info() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   SeekerAI 服务信息${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "服务名称: $SERVICE_NAME"
    echo "项目目录: $PROJECT_DIR"
    echo "运行端口: $PORT"
    echo "运行用户: www-data"
    echo ""
    echo "访问地址:"
    echo "  • 主页: http://$(hostname -I | awk '{print $1}')"
    echo "  • 综合评估: http://$(hostname -I | awk '{print $1}')/comprehensive-assessment.html"
    echo "  • 数据看板: http://$(hostname -I | awk '{print $1}')/dashboard.html"
    echo ""
    echo "配置文件:"
    echo "  • 服务配置: /etc/systemd/system/$SERVICE_NAME.service"
    echo "  • Nginx配置: /etc/nginx/sites-available/seekerStudent"
    echo "  • 环境变量: $PROJECT_DIR/.env"
    echo ""
    echo "数据文件:"
    echo "  • 数据库: $PROJECT_DIR/database/seeker_ai.db"
    echo "  • 备份目录: $PROJECT_DIR/backup/"
    echo ""
}

# 主函数
main() {
    case "${1:-help}" in
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        health)
            health_check
            ;;
        update)
            if [[ $EUID -ne 0 ]]; then
                log_error "更新操作需要root权限"
                exit 1
            fi
            update_code
            ;;
        backup)
            if [[ $EUID -ne 0 ]]; then
                log_error "备份操作需要root权限"
                exit 1
            fi
            backup_database
            ;;
        restore)
            if [[ $EUID -ne 0 ]]; then
                log_error "恢复操作需要root权限"
                exit 1
            fi
            restore_database
            ;;
        monitor)
            monitor_service
            ;;
        info)
            show_info
            ;;
        help|*)
            show_help
            ;;
    esac
}

# 运行主函数
main "$@" 