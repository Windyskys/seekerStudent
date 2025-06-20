@echo off
chcp 65001 >nul 2>&1
cls

echo.
echo ========================================
echo   综合评估API测试
echo ========================================
echo.

echo 1. 测试健康检查API...
powershell -Command "$response = Invoke-RestMethod -Uri 'http://localhost:3000/health' -Method Get; Write-Host 'Status:' $response.status; Write-Host 'AI Service:' $response.ai_service"

echo.
echo 2. 测试综合评估启动API...
powershell -Command "try { $body = @{ studentId='student_001'; subjects=@('数学','语文','物理'); questionCount=6 } | ConvertTo-Json; $response = Invoke-RestMethod -Uri 'http://localhost:3000/api/comprehensive-assessment/start' -Method Post -Body $body -ContentType 'application/json'; Write-Host '✅ 综合评估启动成功'; Write-Host 'Session ID:' $response.session.id; Write-Host '题目数量:' $response.questions.Count; $env:SESSION_ID = $response.session.id; [Environment]::SetEnvironmentVariable('SESSION_ID', $response.session.id, 'Process') } catch { Write-Host '❌ 综合评估启动失败:' $_.Exception.Message }"

echo.
echo 3. 测试综合评估完成API（模拟答题）...
powershell -Command "try { $sessionId = $env:SESSION_ID; if(-not $sessionId) { $sessionId = 'test-session-id' }; $answers = @( @{ questionId=1; subject='数学'; studentAnswer='A'; isCorrect=$true; responseTime=30; knowledgePoints=@('有理数运算') }, @{ questionId=2; subject='语文'; studentAnswer='B'; isCorrect=$false; responseTime=45; knowledgePoints=@('字音识别') }, @{ questionId=3; subject='物理'; studentAnswer='A'; isCorrect=$true; responseTime=35; knowledgePoints=@('声学基础') } ); $body = @{ sessionId=$sessionId; answers=$answers } | ConvertTo-Json -Depth 5; $response = Invoke-RestMethod -Uri 'http://localhost:3000/api/comprehensive-assessment/complete' -Method Post -Body $body -ContentType 'application/json'; Write-Host '✅ 综合评估完成成功'; Write-Host 'Report ID:' $response.report.id; Write-Host '总体得分:' $response.report.overall_score } catch { Write-Host '❌ 综合评估完成失败:' $_.Exception.Message }"

echo.
echo 4. 测试数据看板更新...
powershell -Command "try { $response = Invoke-RestMethod -Uri 'http://localhost:3000/api/dashboard/student_001' -Method Get; Write-Host '✅ 数据看板更新成功'; Write-Host '总测评次数:' $response.dashboard.totalTests; Write-Host '平均得分:' $response.dashboard.averageScore; Write-Host '本月测评:' $response.dashboard.thisMonthTests } catch { Write-Host '❌ 数据看板获取失败:' $_.Exception.Message }"

echo.
echo 测试完成！
pause 