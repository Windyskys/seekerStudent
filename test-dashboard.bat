@echo off
chcp 65001 >nul 2>&1
cls

echo =================================================
echo 测试数据看板和学期规划功能
echo =================================================
echo.

echo 1. 测试服务器健康状态...
powershell -Command "try { $r = Invoke-RestMethod -Uri 'http://localhost:3000/health'; Write-Host '✅ 服务器状态正常' -ForegroundColor Green; $r } catch { Write-Host '❌ 服务器未启动' -ForegroundColor Red }"
echo.

echo 2. 测试数据看板API...
powershell -Command "try { $r = Invoke-RestMethod -Uri 'http://localhost:3000/api/dashboard/student_001'; Write-Host '✅ 数据看板API正常' -ForegroundColor Green; $r.dashboard } catch { Write-Host '❌ 数据看板API失败' -ForegroundColor Red; $_.Exception.Message }"
echo.

echo 3. 测试学期规划API...
powershell -Command "try { $body = @{studentId='student_001';semester='本学期';subject='数学'} | ConvertTo-Json; $r = Invoke-RestMethod -Uri 'http://localhost:3000/api/semester-plan/generate' -Method POST -Body $body -ContentType 'application/json'; Write-Host '✅ 学期规划API正常' -ForegroundColor Green; $r.message } catch { Write-Host '❌ 学期规划API失败' -ForegroundColor Red; $_.Exception.Message }"
echo.

echo 4. 完成一次完整的测评流程...
powershell -Command "try { $startBody = @{studentId='student_001';subject='数学';gradeLevel='七年级'} | ConvertTo-Json; $startResult = Invoke-RestMethod -Uri 'http://localhost:3000/api/assessment/start' -Method POST -Body $startBody -ContentType 'application/json'; Write-Host '✅ 开始测评成功' -ForegroundColor Green; $sessionId = $startResult.session.id; $answers = @(); for($i=1; $i -le 8; $i++) { $nextBody = @{sessionId=$sessionId; previousAnswers=$answers} | ConvertTo-Json -Depth 3; $nextResult = Invoke-RestMethod -Uri 'http://localhost:3000/api/assessment/next-question' -Method POST -Body $nextBody -ContentType 'application/json'; if($nextResult.success) { $answer = @{questionId=$i; studentAnswer=$nextResult.question.options[0].Substring(0,1); correctAnswer=$nextResult.question.correct_answer; isCorrect=($nextResult.question.options[0].Substring(0,1) -eq $nextResult.question.correct_answer); responseTime=Get-Random -Minimum 10 -Maximum 60; difficultyLevel=$nextResult.question.difficulty_level; knowledgePoints=$nextResult.question.knowledge_points}; $answers += $answer } }; $completeBody = @{sessionId=$sessionId; answers=$answers} | ConvertTo-Json -Depth 4; $completeResult = Invoke-RestMethod -Uri 'http://localhost:3000/api/assessment/complete' -Method POST -Body $completeBody -ContentType 'application/json'; Write-Host '✅ 完成测评成功，得分:' $completeResult.report.overall_score -ForegroundColor Green } catch { Write-Host '❌ 测评流程失败' -ForegroundColor Red; $_.Exception.Message }"
echo.

echo 5. 重新测试数据看板（应该有数据了）...
powershell -Command "try { $r = Invoke-RestMethod -Uri 'http://localhost:3000/api/dashboard/student_001'; Write-Host '✅ 数据看板更新成功' -ForegroundColor Green; Write-Host '总测评次数:' $r.dashboard.totalTests; Write-Host '平均得分:' $r.dashboard.averageScore; Write-Host '本月测评:' $r.dashboard.thisMonthTests } catch { Write-Host '❌ 数据看板更新失败' -ForegroundColor Red; $_.Exception.Message }"
echo.

echo =================================================
echo 测试完成
echo =================================================
pause 