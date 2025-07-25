#!/bin/bash

echo " SeekerAI 服务监控报告"
echo "========================="
echo "时间: $(date 
'
+%Y-%m-%d %H:%M:%S
'
)"
echo ""

# 检查服务状态
echo " 服务状态:"
echo "------------"
if systemctl is-active --quiet seeker-ai; then
    echo " SeekerAI服务: 运行中"
else
    echo " SeekerAI服务: 未运行"
fi

if systemctl is-active --quiet nginx; then
    echo " Nginx服务: 运行中"
else
    echo " Nginx服务: 未运行"
fi

echo ""

# 检查端口监听
echo " 端口状态:"
echo "------------"
if netstat -tulpn | grep -q ":3000"; then
    echo " 应用端口3000: 监听中"
else
    echo " 应用端口3000: 未监听"
fi

if netstat -tulpn | grep -q ":80"; then
    echo " HTTP端口80: 监听中"
else
    echo " HTTP端口80: 未监听"
fi

echo ""

# API健康检查
echo " API健康检查:"
echo "---------------"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    echo " API健康检查: 通过 (HTTP $HTTP_CODE)"
else
    echo " API健康检查: 失败 (HTTP $HTTP_CODE)"
fi

echo ""

# 快速操作提示
echo " 快速操作:"
echo "------------"
echo "查看实时日志: seeker-manage logs"
echo "重启服务:     seeker-manage restart"
echo "查看详细状态: seeker-manage status"
echo "手动测试API:  curl http://localhost:3000/health"

echo ""
echo "监控完成! "
