@echo off
chcp 65001 >nul 2>&1
cls

echo.
echo ========================================
echo   SeekerAI 综合评估功能测试
echo ========================================
echo.

echo [1/4] 检查 Node.js 环境...
node --version >nul 2>&1
if errorlevel 1 (
    echo ❌ 错误: 未找到 Node.js
    echo    请先安装 Node.js: https://nodejs.org/
    pause
    exit /b 1
)
echo ✅ Node.js 环境正常

echo.
echo [2/4] 检查项目文件...
if not exist package.json (
    echo ❌ 错误: 未找到 package.json 文件
    pause
    exit /b 1
)

if not exist server.js (
    echo ❌ 错误: 未找到 server.js 文件
    pause
    exit /b 1
)

if not exist comprehensive-assessment.html (
    echo ❌ 错误: 未找到 comprehensive-assessment.html 文件
    pause
    exit /b 1
)

if not exist comprehensive-result.html (
    echo ❌ 错误: 未找到 comprehensive-result.html 文件
    pause
    exit /b 1
)
echo ✅ 项目文件完整

echo.
echo [3/4] 设置环境变量...
set QWEN_API_KEY=sk-0eaf3643806f4d4991eedd3dc7f5aa2e
set NODE_ENV=development
set PORT=3000
echo ✅ 环境变量设置完成

echo.
echo [4/4] 启动服务器...
echo.
echo 🌐 服务地址: http://localhost:3000
echo 📚 综合评估: http://localhost:3000/comprehensive-assessment.html
echo 📊 数据看板: http://localhost:3000/dashboard.html
echo.
echo 按 Ctrl+C 可停止服务器
echo.

node server.js