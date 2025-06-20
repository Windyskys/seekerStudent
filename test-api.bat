@echo off
chcp 65001 >nul
echo 🔧 SeekerAI API 测试工具 (Windows)
echo ===============================
echo.

:menu
echo 选择测试选项:
echo 1) 检查API健康状态
echo 2) 测试开始测评接口
echo 3) 测试获取题目接口  
echo 4) 查看服务器日志 (需要Node.js运行)
echo 5) 退出
echo.
set /p choice=请输入选项 (1-5): 

if "%choice%"=="1" goto health_check
if "%choice%"=="2" goto test_start
if "%choice%"=="3" goto test_question
if "%choice%"=="4" goto view_logs
if "%choice%"=="5" goto exit
goto invalid

:health_check
echo.
echo 🏥 检查API健康状态
echo ==================
echo 测试 GET /health
powershell -Command "try { $response = Invoke-RestMethod -Uri 'http://localhost:3000/health' -Method Get; Write-Host '✅ 健康检查: 正常' -ForegroundColor Green; $response } catch { Write-Host '❌ 健康检查: 失败' -ForegroundColor Red; $_.Exception.Message }"

echo.
echo 测试 GET /api/status  
powershell -Command "try { $response = Invoke-RestMethod -Uri 'http://localhost:3000/api/status' -Method Get; Write-Host '✅ API状态: 正常' -ForegroundColor Green; $response } catch { Write-Host '❌ API状态: 失败' -ForegroundColor Red; $_.Exception.Message }"
goto continue

:test_start
echo.
echo 📋 测试开始测评接口
echo ==================
echo 测试 POST /api/assessment/start
powershell -Command "$body = @{ studentId='test_001'; subject='数学'; gradeLevel='七年级' } | ConvertTo-Json; try { $response = Invoke-RestMethod -Uri 'http://localhost:3000/api/assessment/start' -Method Post -Body $body -ContentType 'application/json'; Write-Host '✅ 开始测评: 正常' -ForegroundColor Green; $response } catch { Write-Host '❌ 开始测评: 失败' -ForegroundColor Red; $_.Exception.Message }"
goto continue

:test_question
echo.
echo 📝 测试获取题目接口
echo ==================
echo 测试 POST /api/assessment/next-question
powershell -Command "$body = @{ sessionId='test-session-123'; previousAnswers=@() } | ConvertTo-Json; try { $response = Invoke-RestMethod -Uri 'http://localhost:3000/api/assessment/next-question' -Method Post -Body $body -ContentType 'application/json'; Write-Host '✅ 获取题目: 正常' -ForegroundColor Green; $response } catch { Write-Host '❌ 获取题目: 失败' -ForegroundColor Red; $_.Exception.Message }"
goto continue

:view_logs
echo.
echo 📋 查看Node.js控制台输出
echo ========================
echo 如果Node.js正在另一个终端运行，请查看那个终端的输出
echo 或者重新运行 test-local.bat 来查看实时日志
echo.
echo 常见的API日志格式:
echo [API] 收到开始测评请求: {...}
echo [API] 创建会话: {...}
echo [API] 会话创建成功: session-id
echo [API] 收到获取下一题请求: {...}
echo [API] AI生成题目成功: {...}
goto continue

:invalid
echo.
echo ❌ 无效选项，请重试
goto continue

:continue
echo.
pause
cls
goto menu

:exit
echo.
echo 👋 测试结束
pause
exit /b 0 