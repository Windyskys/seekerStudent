@echo off
echo 启动SeekerAI本地测试...
echo =======================

echo 安装依赖...
npm install

echo 创建数据库目录...
if not exist "database" mkdir database

echo 设置环境变量...
set NODE_ENV=development
set PORT=3000
set QWEN_API_KEY=sk-0eaf3643806f4d4991eedd3dc7f5aa2e
set DB_PATH=./database/seeker_ai.db

echo 启动服务器...
echo 访问地址: http://localhost:3000
echo 按 Ctrl+C 停止服务器
echo.

node server.js 