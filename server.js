const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const sqlite3 = require('sqlite3').verbose();
const axios = require('axios');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// 中间件
app.use(cors());
app.use(bodyParser.json());
app.use(express.static('.'));

// 确保数据库目录存在
const dbDir = path.dirname(process.env.DB_PATH || './database/seeker_ai.db');
if (!fs.existsSync(dbDir)) {
    fs.mkdirSync(dbDir, { recursive: true });
}

// 数据库初始化
const db = new sqlite3.Database(process.env.DB_PATH || './database/seeker_ai.db');

// 创建数据表
db.serialize(() => {
    // 学生表
    db.run(`
        CREATE TABLE IF NOT EXISTS students (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            grade INTEGER,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    `);

    // 测评会话表
    db.run(`
        CREATE TABLE IF NOT EXISTS assessment_sessions (
            id TEXT PRIMARY KEY,
            student_id TEXT,
            subject TEXT NOT NULL,
            type TEXT NOT NULL,
            status TEXT DEFAULT 'active',
            started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            completed_at DATETIME,
            total_score INTEGER DEFAULT 0,
            FOREIGN KEY (student_id) REFERENCES students (id)
        )
    `);

    // 题目表
    db.run(`
        CREATE TABLE IF NOT EXISTS questions (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            content TEXT NOT NULL,
            type TEXT NOT NULL,
            options TEXT,
            correct_answer TEXT NOT NULL,
            difficulty_level INTEGER DEFAULT 3,
            knowledge_points TEXT,
            ai_generated BOOLEAN DEFAULT 1,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (session_id) REFERENCES assessment_sessions (id)
        )
    `);

    // 学生答案表
    db.run(`
        CREATE TABLE IF NOT EXISTS student_answers (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            question_id TEXT,
            student_answer TEXT,
            is_correct BOOLEAN,
            response_time INTEGER,
            answered_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (session_id) REFERENCES assessment_sessions (id),
            FOREIGN KEY (question_id) REFERENCES questions (id)
        )
    `);

    // 测评报告表
    db.run(`
        CREATE TABLE IF NOT EXISTS assessment_reports (
            id TEXT PRIMARY KEY,
            session_id TEXT,
            overall_score INTEGER,
            strengths TEXT,
            weaknesses TEXT,
            recommendations TEXT,
            learning_plan TEXT,
            ai_analysis TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (session_id) REFERENCES assessment_sessions (id)
        )
    `);

    // 插入示例学生数据
    db.run(`
        INSERT OR IGNORE INTO students (id, name, grade) 
        VALUES ('student_001', '张明', 7)
    `);
});

// 阿里百炼AI接口类
class DashscopeAI {
    constructor() {
        this.apiKey = process.env.QWEN_API_KEY;
        this.baseURL = process.env.DASHSCOPE_BASE_URL || 'https://dashscope.aliyuncs.com/api/v1';
        if (!this.apiKey) {
            console.warn('警告: 未设置 QWEN_API_KEY，将使用模拟数据');
        }
    }

    async generateQuestion(context) {
        if (!this.apiKey) {
            return this.getMockQuestion(context);
        }

        try {
            const prompt = this.buildQuestionPrompt(context);
            const response = await axios.post(
                `${this.baseURL}/services/aigc/text-generation/generation`,
                {
                    model: "qwen-plus",
                    input: {
                        messages: [
                            {
                                role: "system",
                                content: "你是一个专业的中学数学出题专家，能够根据学生的学习情况生成合适难度的数学题目。请严格按照JSON格式返回题目，确保格式正确。"
                            },
                            {
                                role: "user",
                                content: prompt
                            }
                        ]
                    },
                    parameters: {
                        temperature: 0.7,
                        max_tokens: 1000,
                        result_format: "message"
                    }
                },
                {
                    headers: {
                        'Authorization': `Bearer ${this.apiKey}`,
                        'Content-Type': 'application/json'
                    }
                }
            );

            console.log('API响应结构:', JSON.stringify(response.data, null, 2));
            return this.parseQuestionResponse(response.data.output.text);
        } catch (error) {
            console.error('AI生成题目失败:', error.message);
            return this.getMockQuestion(context);
        }
    }

    buildQuestionPrompt(context) {
        const { subject, difficulty, previousAnswers, knowledgePoints } = context;
        
        let prompt = `请为${subject}科目生成一道难度等级为${difficulty}的题目。\n\n`;
        
        if (previousAnswers && previousAnswers.length > 0) {
            const correctCount = previousAnswers.filter(a => a.isCorrect).length;
            const accuracy = (correctCount / previousAnswers.length * 100).toFixed(1);
            prompt += `学生当前答题情况：已答${previousAnswers.length}题，正确率${accuracy}%\n`;
            
            if (accuracy < 60) {
                prompt += `学生表现较弱，请降低题目难度。\n`;
            } else if (accuracy > 80) {
                prompt += `学生表现良好，可以适当提高题目难度。\n`;
            }
        }
        
        if (knowledgePoints && knowledgePoints.length > 0) {
            prompt += `重点考查知识点：${knowledgePoints.join('、')}\n`;
        }
        
        prompt += `\n请按照以下JSON格式返回题目：
{
    "content": "题目内容",
    "type": "multiple_choice",
    "options": ["A. 选项1", "B. 选项2", "C. 选项3", "D. 选项4"],
    "correct_answer": "A",
    "difficulty_level": ${difficulty},
    "knowledge_points": ["知识点1", "知识点2"],
    "explanation": "解题思路说明"
}

注意：
1. 题目内容要清晰、准确
2. 选项要有合理的干扰项
3. 难度要符合中学生水平
4. 知识点要明确`;

        return prompt;
    }

    parseQuestionResponse(response) {
        try {
            console.log('AI响应内容:', response);
            
            // 尝试直接解析JSON（如果response本身就是JSON对象）
            if (typeof response === 'object') {
                return response;
            }
            
            // 尝试从AI响应中提取JSON
            const jsonMatch = response.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
                const parsed = JSON.parse(jsonMatch[0]);
                console.log('解析成功的题目:', parsed);
                return parsed;
            }
        } catch (error) {
            console.error('解析AI响应失败:', error.message);
            console.error('原始响应:', response);
        }
        
        // 如果解析失败，返回默认题目
        console.log('使用默认题目');
        return this.getMockQuestion({});
    }

    getMockQuestion(context) {
        const { difficulty = 3 } = context;
        
        const mockQuestions = [
            {
                content: "计算：(-3) + 5 = ?",
                type: "multiple_choice",
                options: ["A. -8", "B. 2", "C. 8", "D. -2"],
                correct_answer: "B",
                difficulty_level: difficulty,
                knowledge_points: ["有理数运算"],
                explanation: "负数与正数相加，实际上是做减法"
            },
            {
                content: "解方程：2x + 3 = 7",
                type: "multiple_choice", 
                options: ["A. x = 1", "B. x = 2", "C. x = 3", "D. x = 4"],
                correct_answer: "B",
                difficulty_level: difficulty,
                knowledge_points: ["一元一次方程"],
                explanation: "移项得到2x = 4，所以x = 2"
            },
            {
                content: "若 |x| = 5，则 x 的值为",
                type: "multiple_choice",
                options: ["A. 5", "B. -5", "C. ±5", "D. 不存在"],
                correct_answer: "C",
                difficulty_level: difficulty,
                knowledge_points: ["绝对值"],
                explanation: "绝对值等于5的数有两个：5和-5"
            }
        ];
        
        return mockQuestions[Math.floor(Math.random() * mockQuestions.length)];
    }

    async generateReport(assessmentData) {
        if (!this.apiKey) {
            return this.getMockReport(assessmentData);
        }

        try {
            const prompt = this.buildReportPrompt(assessmentData);
            const response = await axios.post(
                `${this.baseURL}/services/aigc/text-generation/generation`,
                {
                    model: "qwen-plus",
                    input: {
                        messages: [
                            {
                                role: "system",
                                content: "你是一个专业的教育评估专家，能够分析学生的测评结果并提供个性化的学习建议。请严格按照JSON格式返回分析报告。"
                            },
                            {
                                role: "user",
                                content: prompt
                            }
                        ]
                    },
                    parameters: {
                        temperature: 0.6,
                        max_tokens: 2000,
                        result_format: "message"
                    }
                },
                {
                    headers: {
                        'Authorization': `Bearer ${this.apiKey}`,
                        'Content-Type': 'application/json'
                    }
                }
            );

            console.log('报告API响应结构:', JSON.stringify(response.data, null, 2));
            return this.parseReportResponse(response.data.output.text);
        } catch (error) {
            console.error('AI生成报告失败:', error.message);
            return this.getMockReport(assessmentData);
        }
    }

    buildReportPrompt(assessmentData) {
        const { answers, totalQuestions, correctCount, subject } = assessmentData;
        const accuracy = (correctCount / totalQuestions * 100).toFixed(1);
        
        let prompt = `请为学生的${subject}测评结果生成详细的分析报告。\n\n`;
        prompt += `测评概况：\n`;
        prompt += `- 总题数：${totalQuestions}题\n`;
        prompt += `- 正确题数：${correctCount}题\n`;
        prompt += `- 正确率：${accuracy}%\n\n`;
        
        if (answers && answers.length > 0) {
            prompt += `具体答题情况：\n`;
            answers.forEach((answer, index) => {
                prompt += `第${index + 1}题：${answer.isCorrect ? '正确' : '错误'}，`;
                prompt += `知识点：${answer.knowledgePoints?.join('、') || '未分类'}，`;
                prompt += `用时：${answer.responseTime || 0}秒\n`;
            });
        }
        
        prompt += `\n请按照以下JSON格式返回分析报告：
{
    "overall_score": ${Math.round(accuracy)},
    "strengths": ["优势1", "优势2"],
    "weaknesses": ["薄弱点1", "薄弱点2"],
    "recommendations": ["建议1", "建议2", "建议3"],
    "learning_plan": {
        "immediate": ["即时学习建议"],
        "short_term": ["短期学习计划"],
        "long_term": ["长期提升目标"]
    },
    "ai_analysis": "详细的AI分析文本，包含学习能力评估、知识掌握情况分析等"
}`;

        return prompt;
    }

    parseReportResponse(response) {
        try {
            const jsonMatch = response.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
                return JSON.parse(jsonMatch[0]);
            }
        } catch (error) {
            console.error('解析AI报告失败:', error.message);
        }
        
        return this.getMockReport({});
    }

    getMockReport(assessmentData) {
        const { correctCount = 0, totalQuestions = 5 } = assessmentData;
        const accuracy = totalQuestions > 0 ? (correctCount / totalQuestions * 100) : 0;
        
        return {
            overall_score: Math.round(accuracy),
            strengths: ["基础运算能力较好", "逻辑思维清晰"],
            weaknesses: ["解题速度需要提升", "复杂题型理解有待加强"],
            recommendations: [
                "加强基础概念的理解和记忆",
                "多做同类型题目训练",
                "注意审题的准确性",
                "提高解题速度"
            ],
            learning_plan: {
                immediate: ["复习本次测评的错题"],
                short_term: ["每天练习10道同难度题目，坚持一周"],
                long_term: ["建立错题本，定期回顾和总结"]
            },
            ai_analysis: `基于本次数学测评结果，您的总体表现达到${Math.round(accuracy)}%的正确率。从答题情况来看，您在基础运算方面表现良好，具备一定的数学思维能力。但在解题速度和复杂题型的处理上还有提升空间。建议您在后续学习中加强基础概念的巩固，多进行有针对性的练习，逐步提高解题效率。`
        };
    }
}

const aiService = new DashscopeAI();

// API路由

// 开始新的测评会话
app.post('/api/assessment/start', (req, res) => {
    const { studentId = 'student_001', subject, type } = req.body;
    const sessionId = uuidv4();
    
    db.run(
        `INSERT INTO assessment_sessions (id, student_id, subject, type) 
         VALUES (?, ?, ?, ?)`,
        [sessionId, studentId, subject, type],
        function(err) {
            if (err) {
                return res.status(500).json({ error: '创建测评会话失败' });
            }
            
            res.json({
                success: true,
                sessionId,
                message: '测评会话创建成功'
            });
        }
    );
});

// 获取下一题
app.post('/api/assessment/next-question', async (req, res) => {
    try {
        const { sessionId, previousAnswer } = req.body;
        
        // 如果有上一题的答案，先保存
        if (previousAnswer) {
            const answerId = uuidv4();
            db.run(
                `INSERT INTO student_answers (id, session_id, question_id, student_answer, is_correct, response_time)
                 VALUES (?, ?, ?, ?, ?, ?)`,
                [
                    answerId,
                    sessionId,
                    previousAnswer.questionId,
                    previousAnswer.answer,
                    previousAnswer.isCorrect ? 1 : 0,
                    previousAnswer.responseTime || 0
                ]
            );
        }
        
        // 获取当前会话信息
        db.get(
            `SELECT * FROM assessment_sessions WHERE id = ?`,
            [sessionId],
            async (err, session) => {
                if (err || !session) {
                    return res.status(404).json({ error: '会话不存在' });
                }
                
                // 获取已答题目数量和答题记录
                db.all(
                    `SELECT sa.*, q.knowledge_points, q.difficulty_level 
                     FROM student_answers sa 
                     JOIN questions q ON sa.question_id = q.id 
                     WHERE sa.session_id = ?`,
                    [sessionId],
                    async (err, previousAnswers) => {
                        if (err) {
                            return res.status(500).json({ error: '获取答题记录失败' });
                        }
                        
                        // 根据答题情况调整难度
                        let difficulty = 3; // 默认中等难度
                        if (previousAnswers.length > 0) {
                            const correctCount = previousAnswers.filter(a => a.is_correct).length;
                            const accuracy = correctCount / previousAnswers.length;
                            
                            if (accuracy > 0.8) {
                                difficulty = Math.min(5, difficulty + 1);
                            } else if (accuracy < 0.4) {
                                difficulty = Math.max(1, difficulty - 1);
                            }
                        }
                        
                        // 生成新题目
                        const questionContext = {
                            subject: session.subject,
                            difficulty,
                            previousAnswers: previousAnswers.map(a => ({
                                isCorrect: Boolean(a.is_correct),
                                knowledgePoints: a.knowledge_points ? a.knowledge_points.split(',') : [],
                                responseTime: a.response_time
                            })),
                            knowledgePoints: ['有理数运算', '方程求解', '绝对值']
                        };
                        
                        try {
                            const questionData = await aiService.generateQuestion(questionContext);
                            const questionId = uuidv4();
                            
                            // 保存题目到数据库
                            db.run(
                                `INSERT INTO questions (id, session_id, content, type, options, correct_answer, difficulty_level, knowledge_points)
                                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                                [
                                    questionId,
                                    sessionId,
                                    questionData.content,
                                    questionData.type,
                                    JSON.stringify(questionData.options || []),
                                    questionData.correct_answer,
                                    questionData.difficulty_level,
                                    questionData.knowledge_points ? questionData.knowledge_points.join(',') : ''
                                ],
                                (err) => {
                                    if (err) {
                                        console.error('保存题目失败:', err);
                                    }
                                }
                            );
                            
                            res.json({
                                success: true,
                                question: {
                                    id: questionId,
                                    ...questionData
                                }
                            });
                            
                        } catch (error) {
                            console.error('生成题目失败:', error);
                            res.status(500).json({ error: '生成题目失败' });
                        }
                    }
                );
            }
        );
        
    } catch (error) {
        console.error('获取下一题失败:', error);
        res.status(500).json({ error: '获取下一题失败' });
    }
});

// 完成测评并生成报告
app.post('/api/assessment/complete', async (req, res) => {
    try {
        const { sessionId, finalAnswer } = req.body;
        
        // 保存最后一题的答案
        if (finalAnswer) {
            const answerId = uuidv4();
            db.run(
                `INSERT INTO student_answers (id, session_id, question_id, student_answer, is_correct, response_time)
                 VALUES (?, ?, ?, ?, ?, ?)`,
                [
                    answerId,
                    sessionId,
                    finalAnswer.questionId,
                    finalAnswer.answer,
                    finalAnswer.isCorrect ? 1 : 0,
                    finalAnswer.responseTime || 0
                ]
            );
        }
        
        // 获取所有答题记录
        db.all(
            `SELECT sa.*, q.knowledge_points, q.difficulty_level, s.subject
             FROM student_answers sa 
             JOIN questions q ON sa.question_id = q.id 
             JOIN assessment_sessions s ON sa.session_id = s.id
             WHERE sa.session_id = ?`,
            [sessionId],
            async (err, answers) => {
                if (err) {
                    return res.status(500).json({ error: '获取答题记录失败' });
                }
                
                const totalQuestions = answers.length;
                const correctCount = answers.filter(a => a.is_correct).length;
                const subject = answers[0]?.subject || '数学';
                
                // 生成AI报告
                const assessmentData = {
                    answers: answers.map(a => ({
                        isCorrect: Boolean(a.is_correct),
                        knowledgePoints: a.knowledge_points ? a.knowledge_points.split(',') : [],
                        responseTime: a.response_time
                    })),
                    totalQuestions,
                    correctCount,
                    subject
                };
                
                try {
                    const reportData = await aiService.generateReport(assessmentData);
                    const reportId = uuidv4();
                    
                    // 保存报告到数据库
                    db.run(
                        `INSERT INTO assessment_reports (id, session_id, overall_score, strengths, weaknesses, recommendations, learning_plan, ai_analysis)
                         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                        [
                            reportId,
                            sessionId,
                            reportData.overall_score,
                            JSON.stringify(reportData.strengths),
                            JSON.stringify(reportData.weaknesses),
                            JSON.stringify(reportData.recommendations),
                            JSON.stringify(reportData.learning_plan),
                            reportData.ai_analysis
                        ]
                    );
                    
                    // 更新会话状态
                    db.run(
                        `UPDATE assessment_sessions 
                         SET status = 'completed', completed_at = CURRENT_TIMESTAMP, total_score = ?
                         WHERE id = ?`,
                        [reportData.overall_score, sessionId]
                    );
                    
                    res.json({
                        success: true,
                        report: {
                            id: reportId,
                            sessionId,
                            totalQuestions,
                            correctCount,
                            ...reportData
                        }
                    });
                    
                } catch (error) {
                    console.error('生成报告失败:', error);
                    res.status(500).json({ error: '生成报告失败' });
                }
            }
        );
        
    } catch (error) {
        console.error('完成测评失败:', error);
        res.status(500).json({ error: '完成测评失败' });
    }
});

// 获取测评报告
app.get('/api/assessment/report/:sessionId', (req, res) => {
    const { sessionId } = req.params;
    
    db.get(
        `SELECT ar.*, s.subject, s.started_at, s.completed_at, st.name as student_name
         FROM assessment_reports ar
         JOIN assessment_sessions s ON ar.session_id = s.id
         JOIN students st ON s.student_id = st.id
         WHERE ar.session_id = ?`,
        [sessionId],
        (err, report) => {
            if (err) {
                return res.status(500).json({ error: '获取报告失败' });
            }
            
            if (!report) {
                return res.status(404).json({ error: '报告不存在' });
            }
            
            // 解析JSON字段
            try {
                report.strengths = JSON.parse(report.strengths || '[]');
                report.weaknesses = JSON.parse(report.weaknesses || '[]');
                report.recommendations = JSON.parse(report.recommendations || '[]');
                report.learning_plan = JSON.parse(report.learning_plan || '{}');
            } catch (parseError) {
                console.error('解析报告数据失败:', parseError);
            }
            
            res.json({
                success: true,
                report
            });
        }
    );
});

// 获取学生测评历史
app.get('/api/student/:studentId/history', (req, res) => {
    const { studentId } = req.params;
    
    db.all(
        `SELECT s.*, ar.overall_score
         FROM assessment_sessions s
         LEFT JOIN assessment_reports ar ON s.id = ar.session_id
         WHERE s.student_id = ? AND s.status = 'completed'
         ORDER BY s.completed_at DESC
         LIMIT 10`,
        [studentId],
        (err, sessions) => {
            if (err) {
                return res.status(500).json({ error: '获取历史记录失败' });
            }
            
            res.json({
                success: true,
                history: sessions
            });
        }
    );
});

// 健康检查接口
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        version: '1.0.0',
        database: 'connected',
        ai_service: process.env.QWEN_API_KEY ? 'configured' : 'mock'
    });
});

// API状态检查
app.get('/api/status', (req, res) => {
    res.json({
        success: true,
        message: 'SeekerAI API服务运行正常',
        timestamp: new Date().toISOString(),
        features: {
            ai_generation: !!process.env.QWEN_API_KEY,
            database: true,
            assessment: true
        }
    });
});

// 根路径重定向到首页
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

// 启动服务器
app.listen(PORT, () => {
    console.log(`
🚀 SeekerAI智能学习平台后端服务已启动
🌐 服务地址: http://localhost:${PORT}
📊 数据库: ${process.env.DB_PATH || './database/seeker_ai.db'}
🤖 AI服务: ${process.env.QWEN_API_KEY ? 'Qwen-Plus已配置✅' : '使用模拟数据⚠️'}
🔑 API密钥: ${process.env.QWEN_API_KEY ? '已设置' : '未设置'}
    `);
});

// 优雅关闭
process.on('SIGINT', () => {
    console.log('\n正在关闭数据库连接...');
    db.close((err) => {
        if (err) {
            console.error('关闭数据库失败:', err.message);
        } else {
            console.log('数据库连接已关闭');
        }
        process.exit(0);
    });
}); 