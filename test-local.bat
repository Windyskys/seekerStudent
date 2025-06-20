@echo off
chcp 65001 >nul 2>&1
cls

echo 🚀 启动SeekerAI本地测试
echo ========================
echo.

echo 📦 检查依赖...
if not exist "node_modules" (
    echo 正在安装项目依赖...
    npm install
    if errorlevel 1 (
        echo ❌ 依赖安装失败！
        pause
        exit /b 1
    )
    echo ✅ 依赖安装完成
) else (
    echo ✅ 依赖已存在
)

echo.
echo 📁 创建数据库目录...
if not exist "database" mkdir database
echo ✅ 数据库目录准备完成

echo.
echo 🔧 清理已有进程...
taskkill /F /IM node.exe >nul 2>&1
echo ✅ 进程清理完成

echo.
echo ⚙️ 设置环境变量...
set NODE_ENV=development
set PORT=3000
set QWEN_API_KEY=sk-0eaf3643806f4d4991eedd3dc7f5aa2e
set DB_PATH=./database/seeker_ai.db
echo ✅ 环境变量设置完成

echo.
echo 🌐 服务器信息:
echo   访问地址: http://localhost:3000
echo   首页: http://localhost:3000
echo   测评页面: http://localhost:3000/assessment-test.html
echo   健康检查: http://localhost:3000/health
echo   API状态: http://localhost:3000/api/status
echo.
echo 🎯 可用测试工具:
echo   - 运行 test-api.bat 进行API测试
echo   - 运行 debug-api.sh 查看详细日志 (Linux/Git Bash)
echo.
echo 🔍 启动服务器...
echo   按 Ctrl+C 停止服务器
echo ================================
echo.

node server.js

echo.
echo 👋 服务器已停止
pause 