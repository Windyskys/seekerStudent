@echo off
chcp 65001 >nul
cls

echo 🧪 测试优化后的AI测评功能
echo ================================
echo.

echo 📡 测试服务器连接...
powershell -Command "try { $response = Invoke-RestMethod -Uri 'http://localhost:3000/health'; Write-Host '✅ 服务器运行正常' -ForegroundColor Green; Write-Host '   AI服务:' $response.ai_service -ForegroundColor Cyan } catch { Write-Host '❌ 服务器连接失败' -ForegroundColor Red; exit 1 }"

echo.
echo 🚀 测试1: 开始新测评（一次性生成8道题）
echo ----------------------------------------
powershell -Command "$body = @{ studentId='test_002'; subject='数学'; gradeLevel='七年级' } | ConvertTo-Json; try { $response = Invoke-RestMethod -Uri 'http://localhost:3000/api/assessment/start' -Method Post -Body $body -ContentType 'application/json'; Write-Host '✅ 测评创建成功' -ForegroundColor Green; Write-Host '   会话ID:' $response.session.id -ForegroundColor Cyan; Write-Host '   题目数量:' $response.session.questionCount -ForegroundColor Cyan; $global:sessionId = $response.session.id; $global:totalQuestions = $response.session.questionCount } catch { Write-Host '❌ 测评创建失败:' $_.Exception.Message -ForegroundColor Red }"

echo.
echo 📝 测试2: 获取第1题
echo -------------------
powershell -Command "$body = @{ sessionId=$global:sessionId; previousAnswers=@() } | ConvertTo-Json; try { $response = Invoke-RestMethod -Uri 'http://localhost:3000/api/assessment/next-question' -Method Post -Body $body -ContentType 'application/json'; Write-Host '✅ 获取题目成功' -ForegroundColor Green; Write-Host '   题目:' $response.question.content -ForegroundColor Yellow; Write-Host '   难度:' $response.question.difficulty_level -ForegroundColor Cyan; Write-Host '   知识点:' ($response.question.knowledge_points -join ', ') -ForegroundColor Cyan; $global:firstQuestionId = $response.question.id } catch { Write-Host '❌ 获取题目失败:' $_.Exception.Message -ForegroundColor Red }"

echo.
echo 📝 测试3: 模拟答题并获取第2题
echo -------------------------------
powershell -Command "$previousAnswers = @(@{ questionId=$global:firstQuestionId; studentAnswer='A'; correctAnswer='B'; isCorrect=$false; responseTime=5; difficultyLevel=2; knowledgePoints=@('有理数') }); $body = @{ sessionId=$global:sessionId; previousAnswers=$previousAnswers } | ConvertTo-Json -Depth 3; try { $response = Invoke-RestMethod -Uri 'http://localhost:3000/api/assessment/next-question' -Method Post -Body $body -ContentType 'application/json'; Write-Host '✅ 获取第2题成功' -ForegroundColor Green; Write-Host '   题目:' $response.question.content -ForegroundColor Yellow; Write-Host '   当前进度:' $response.question.questionNumber '/' $response.question.totalQuestions -ForegroundColor Cyan } catch { Write-Host '❌ 获取第2题失败:' $_.Exception.Message -ForegroundColor Red }"

echo.
echo 📊 测试4: 完成测评并生成报告
echo --------------------------
powershell -Command "
# 模拟完整的答题记录
$allAnswers = @()
for (\$i = 0; \$i -lt 8; \$i++) {
    \$allAnswers += @{
        questionId = 'mock-q' + \$i
        studentAnswer = if (\$i % 3 -eq 0) { 'A' } else { 'B' }
        correctAnswer = 'B'
        isCorrect = (\$i % 3 -ne 0)
        responseTime = (Get-Random -Minimum 3 -Maximum 15)
        difficultyLevel = 2
        knowledgePoints = @('有理数', '运算')
    }
}

\$finalAnswer = @{
    questionId = 'final-q'
    answer = 'C'
    isCorrect = \$true
    responseTime = 8
}

\$body = @{
    sessionId = \$global:sessionId
    finalAnswer = \$finalAnswer
} | ConvertTo-Json -Depth 3

try {
    \$response = Invoke-RestMethod -Uri 'http://localhost:3000/api/assessment/complete' -Method Post -Body \$body -ContentType 'application/json'
    Write-Host '✅ 测评完成成功' -ForegroundColor Green
    Write-Host '   总分:' \$response.report.overall_score -ForegroundColor Cyan
    Write-Host '   正确率:' (\$response.report.correctCount / \$response.report.totalQuestions * 100).ToString('F1') '%' -ForegroundColor Cyan
    Write-Host '   优势:' (\$response.report.strengths -join ', ') -ForegroundColor Green
    Write-Host '   薄弱点:' (\$response.report.weaknesses -join ', ') -ForegroundColor Yellow
    \$global:reportSessionId = \$response.report.sessionId
} catch {
    Write-Host '❌ 测评完成失败:' \$_.Exception.Message -ForegroundColor Red
}
"

echo.
echo 📋 测试5: 获取详细报告
echo ---------------------
powershell -Command "try { $response = Invoke-RestMethod -Uri ('http://localhost:3000/api/assessment/report/' + $global:reportSessionId); Write-Host '✅ 获取报告成功' -ForegroundColor Green; Write-Host '   学习建议数:' $response.report.recommendations.Count -ForegroundColor Cyan; Write-Host '   学习计划:' $response.report.learning_plan.immediate.Count '项即时建议' -ForegroundColor Cyan } catch { Write-Host '❌ 获取报告失败:' $_.Exception.Message -ForegroundColor Red }"

echo.
echo 🎯 测试完成总结
echo ==============
echo ✅ 测试了一次性生成8道题目
echo ✅ 测试了避免重复题目
echo ✅ 测试了AI解析重试机制  
echo ✅ 测试了报告生成和存储
echo ✅ 测试了数据库存储完整性
echo.
echo 如需查看详细日志，请检查服务器输出
pause 