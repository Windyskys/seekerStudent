@echo off
echo.
echo ========================================
echo   SeekerAI智能学习平台启动脚本
echo ========================================
echo.

REM 检查Node.js是否安装
node --version >nul 2>&1
if errorlevel 1 (
    echo 错误: 未检测到Node.js，请先安装Node.js
    echo 下载地址: https://nodejs.org/
    pause
    exit /b 1
)

REM 检查是否已安装依赖
if not exist "node_modules" (
    echo 正在安装项目依赖...
    npm install
    if errorlevel 1 (
        echo 依赖安装失败，请检查网络连接
        pause
        exit /b 1
    )
)

REM 检查环境配置文件
if not exist ".env" (
    echo 正在创建环境配置文件...
    copy ".env.example" ".env"
    echo.
    echo 重要提示：
    echo 请编辑 .env 文件，配置您的阿里百炼API密钥（QWEN_API_KEY）
    echo 获取API密钥: https://dashscope.aliyun.com/
    echo.
    echo 按任意键继续启动服务...
    pause >nul
)

echo 正在启动后端服务...
echo.
echo 服务地址: http://localhost:3000
echo 测评页面: http://localhost:3000/assessment.html
echo.
echo 按 Ctrl+C 停止服务
echo.

npm start 