#!/bin/bash

echo "🔧 SeekerAI API 调试工具"
echo "======================="
echo ""

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

# 检查API健康状态
check_api_health() {
    echo "🏥 检查API健康状态"
    echo "==================="
    
    # 检查健康接口
    local health_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null)
    if [ "$health_code" = "200" ]; then
        log_success "健康检查接口: 正常 (HTTP $health_code)"
    else
        log_error "健康检查接口: 异常 (HTTP $health_code)"
    fi
    
    # 检查API状态接口
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/status 2>/dev/null)
    if [ "$status_code" = "200" ]; then
        log_success "API状态接口: 正常 (HTTP $status_code)"
    else
        log_error "API状态接口: 异常 (HTTP $status_code)"
    fi
    
    echo ""
}

# 测试测评API
test_assessment_api() {
    echo "📋 测试测评API接口"
    echo "=================="
    
    # 测试开始测评
    log_info "测试 POST /api/assessment/start"
    local start_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
        -H "Content-Type: application/json" \
        -d '{"studentId":"test_001","subject":"数学","gradeLevel":"七年级"}' \
        http://localhost:3000/api/assessment/start 2>/dev/null)
    
    local start_body=$(echo "$start_response" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
    local start_code=$(echo "$start_response" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
    
    if [ "$start_code" = "200" ]; then
        log_success "开始测评接口: 正常 (HTTP $start_code)"
        echo "响应内容: $start_body"
        
        # 提取sessionId用于后续测试
        local session_id=$(echo "$start_body" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        if [ -n "$session_id" ]; then
            log_info "获取到会话ID: $session_id"
            
            # 测试获取题目
            log_info "测试 POST /api/assessment/next-question"
            local question_response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
                -H "Content-Type: application/json" \
                -d "{\"sessionId\":\"$session_id\",\"previousAnswers\":[]}" \
                http://localhost:3000/api/assessment/next-question 2>/dev/null)
            
            local question_body=$(echo "$question_response" | sed -E 's/HTTPSTATUS\:[0-9]{3}$//')
            local question_code=$(echo "$question_response" | tr -d '\n' | sed -E 's/.*HTTPSTATUS:([0-9]{3})$/\1/')
            
            if [ "$question_code" = "200" ]; then
                log_success "获取题目接口: 正常 (HTTP $question_code)"
                echo "题目内容: $(echo "$question_body" | head -c 200)..."
            else
                log_error "获取题目接口: 异常 (HTTP $question_code)"
                echo "错误响应: $question_body"
            fi
        fi
    else
        log_error "开始测评接口: 异常 (HTTP $start_code)"
        echo "错误响应: $start_body"
    fi
    
    echo ""
}

# 查看实时日志
view_logs() {
    echo "📋 实时API日志"
    echo "=============="
    echo "按 Ctrl+C 停止日志查看"
    echo ""
    
    if command -v journalctl >/dev/null 2>&1; then
        # 在Linux系统上使用journalctl
        sudo journalctl -u seeker-ai -f --since "5 minutes ago" | grep -E '\[API\]|ERROR|error'
    else
        # 如果没有journalctl，尝试其他方法
        log_warning "无法使用journalctl，请手动检查应用日志"
        if [ -f "/var/log/seeker-ai.log" ]; then
            tail -f /var/log/seeker-ai.log | grep -E '\[API\]|ERROR|error'
        else
            log_error "找不到日志文件"
        fi
    fi
}

# 检查数据库连接
check_database() {
    echo "🗄️  检查数据库连接"
    echo "=================="
    
    if [ -f "./database/seeker_ai.db" ]; then
        log_success "数据库文件存在: ./database/seeker_ai.db"
        
        # 检查数据库表
        if command -v sqlite3 >/dev/null 2>&1; then
            local tables=$(sqlite3 ./database/seeker_ai.db ".tables" 2>/dev/null)
            if [ -n "$tables" ]; then
                log_success "数据库表: $tables"
            else
                log_warning "数据库表为空或无法读取"
            fi
        else
            log_warning "sqlite3命令不可用，无法检查数据库表"
        fi
    else
        log_error "数据库文件不存在"
    fi
    
    echo ""
}

# 检查环境变量
check_environment() {
    echo "🌍 检查环境变量"
    echo "==============="
    
    if [ -f ".env" ]; then
        log_success "找到.env文件"
        while IFS= read -r line; do
            if [[ $line =~ ^[A-Z_]+= ]]; then
                var_name=$(echo "$line" | cut -d'=' -f1)
                if [[ $var_name == *"KEY"* ]] || [[ $var_name == *"SECRET"* ]]; then
                    echo "$var_name=***隐藏***"
                else
                    echo "$line"
                fi
            fi
        done < .env
    else
        log_warning "未找到.env文件"
    fi
    
    echo ""
}

# 主菜单
show_menu() {
    echo "选择调试选项:"
    echo "1) 检查API健康状态"
    echo "2) 测试测评API接口"
    echo "3) 查看实时API日志"
    echo "4) 检查数据库连接"
    echo "5) 检查环境变量"
    echo "6) 全面检查"
    echo "7) 退出"
    echo ""
    read -p "请输入选项 (1-7): " choice
}

# 全面检查
full_check() {
    check_api_health
    test_assessment_api
    check_database
    check_environment
}

# 主循环
while true; do
    show_menu
    
    case $choice in
        1)
            check_api_health
            ;;
        2)
            test_assessment_api
            ;;
        3)
            view_logs
            ;;
        4)
            check_database
            ;;
        5)
            check_environment
            ;;
        6)
            full_check
            ;;
        7)
            log_info "调试结束"
            exit 0
            ;;
        *)
            log_error "无效选项，请重试"
            ;;
    esac
    
    echo ""
    read -p "按 Enter 继续..."
    clear
done 