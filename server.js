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
            explanation TEXT,
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

    // 学期学习规划表
    db.run(`
        CREATE TABLE IF NOT EXISTS semester_plans (
            id TEXT PRIMARY KEY,
            student_id TEXT,
            semester TEXT NOT NULL,
            subject TEXT NOT NULL,
            overall_performance TEXT,
            learning_goals TEXT,
            study_schedule TEXT,
            key_improvements TEXT,
            resources_needed TEXT,
            progress_tracking TEXT,
            ai_analysis TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (student_id) REFERENCES students (id)
        )
    `);

    // 数据库升级：检查并添加缺失的字段
    db.run(`PRAGMA table_info(questions)`, (err, result) => {
        if (!err) {
            db.all(`PRAGMA table_info(questions)`, (err, columns) => {
                if (!err) {
                    const hasExplanation = columns.some(col => col.name === 'explanation');
                    if (!hasExplanation) {
                        console.log('[DB] 添加explanation字段到questions表');
                        db.run(`ALTER TABLE questions ADD COLUMN explanation TEXT`);
                    }
                }
            });
        }
    });

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
        this.maxRetries = 3; // 最大重试次数
        if (!this.apiKey) {
            console.warn('警告: 未设置 QWEN_API_KEY，将使用模拟数据');
        }
    }

    // 一次性生成多道题目
    async generateQuestions(context) {
        if (!this.apiKey) {
            return this.getMockQuestions(context);
        }

        for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
            try {
                console.log(`[AI] 尝试生成题目，第${attempt}次尝试`);
                const prompt = this.buildQuestionsPrompt(context);
                const response = await axios.post(
                    `${this.baseURL}/services/aigc/text-generation/generation`,
                    {
                        model: "qwen-plus",
                        input: {
                            messages: [
                                {
                                    role: "system",
                                    content: "你是一个专业的中学数学出题专家。请严格按照JSON数组格式返回题目，确保每个题目都是完整有效的JSON对象。"
                                },
                                {
                                    role: "user",
                                    content: prompt
                                }
                            ]
                        },
                        parameters: {
                            temperature: 0.7,
                            max_tokens: 3000,
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

                console.log(`[AI] 第${attempt}次尝试，API响应结构:`, JSON.stringify(response.data, null, 2));
                const questions = this.parseQuestionsResponse(response.data.output?.choices?.[0]?.message?.content);
                
                if (questions && questions.length >= context.questionCount) {
                    console.log(`[AI] 第${attempt}次尝试成功生成${questions.length}道题目`);
                    return questions.slice(0, context.questionCount);
                } else {
                    console.warn(`[AI] 第${attempt}次尝试生成题目数量不足: ${questions?.length || 0}/${context.questionCount}`);
                }
            } catch (error) {
                console.error(`[AI] 第${attempt}次尝试失败:`, error.message);
                if (attempt === this.maxRetries) {
                    console.error('[AI] 所有尝试均失败，使用模拟题目');
                    return this.getMockQuestions(context);
                }
                // 等待1秒后重试
                await new Promise(resolve => setTimeout(resolve, 1000));
            }
        }
        
        return this.getMockQuestions(context);
    }

    // 单个题目生成（保持向后兼容）
    async generateQuestion(context) {
        const questions = await this.generateQuestions({...context, questionCount: 1});
        return questions[0];
    }

    // 生成多个题目的提示词
    buildQuestionsPrompt(context) {
        const { subject, difficulty, questionCount = 8, knowledgePoints, existingQuestions = [] } = context;
        
        let prompt = `请为${subject}科目一次性生成${questionCount}道难度等级为${difficulty}的题目。\n\n`;
        
        if (knowledgePoints && knowledgePoints.length > 0) {
            prompt += `重点考查知识点：${knowledgePoints.join('、')}\n`;
        }
        
        // 避免重复题目
        if (existingQuestions.length > 0) {
            prompt += `\n已有题目示例（请避免重复）：\n`;
            existingQuestions.slice(0, 3).forEach((q, i) => {
                prompt += `${i + 1}. ${q.content}\n`;
            });
            prompt += `\n请确保新生成的题目与上述题目不重复。\n`;
        }
        
        prompt += `\n请严格按照以下JSON数组格式返回${questionCount}道题目：
[
    {
        "content": "题目内容1",
        "type": "multiple_choice",
        "options": ["A. 选项1", "B. 选项2", "C. 选项3", "D. 选项4"],
        "correct_answer": "A",
        "difficulty_level": ${difficulty},
        "knowledge_points": ["知识点1", "知识点2"],
        "explanation": "解题思路说明1"
    },
    {
        "content": "题目内容2", 
        "type": "multiple_choice",
        "options": ["A. 选项1", "B. 选项2", "C. 选项3", "D. 选项4"],
        "correct_answer": "B",
        "difficulty_level": ${difficulty},
        "knowledge_points": ["知识点1", "知识点2"],
        "explanation": "解题思路说明2"
    }
]

重要要求：
1. 必须返回完整的JSON数组格式
2. 每道题目必须包含所有必需字段
3. 题目内容要清晰、准确，避免歧义
4. 选项要有合理的干扰项，符合学生认知水平
5. 难度要符合中学${subject}水平
6. 确保所有题目都不重复
7. JSON格式必须完全正确，可以直接解析
8. 不要添加任何解释文字，只返回JSON数组`;

        return prompt;
    }

    // 兼容单个题目的提示词
    buildQuestionPrompt(context) {
        return this.buildQuestionsPrompt({...context, questionCount: 1});
    }

    // 解析多个题目的响应
    parseQuestionsResponse(response) {
        if (!response) {
            console.error('[AI] 响应内容为空');
            return null;
        }

        try {
            console.log('[AI] 原始响应内容:', response);
            
            // 尝试直接解析JSON数组
            if (typeof response === 'object' && Array.isArray(response)) {
                return this.validateQuestions(response);
            }
            
            // 如果是字符串，先尝试直接解析
            if (typeof response === 'string') {
                try {
                    const directParse = JSON.parse(response);
                    if (Array.isArray(directParse)) {
                        return this.validateQuestions(directParse);
                    }
                } catch (e) {
                    // 继续尝试其他解析方式
                }
                
                // 尝试提取JSON数组（更宽松的匹配）
                const jsonArrayMatch = response.match(/\[[\s\S]*\]/);
                if (jsonArrayMatch) {
                    const parsed = JSON.parse(jsonArrayMatch[0]);
                    if (Array.isArray(parsed)) {
                        return this.validateQuestions(parsed);
                    }
                }
                
                // 尝试提取单个JSON对象并包装成数组
                const jsonObjectMatch = response.match(/\{[\s\S]*\}/);
                if (jsonObjectMatch) {
                    const parsed = JSON.parse(jsonObjectMatch[0]);
                    return this.validateQuestions([parsed]);
                }
            }
        } catch (error) {
            console.error('[AI] 解析响应失败:', error.message);
            console.error('[AI] 原始响应:', response);
        }
        
        console.warn('[AI] 所有解析方式失败，返回null');
        return null;
    }

    // 验证题目格式
    validateQuestions(questions) {
        if (!Array.isArray(questions)) {
            return null;
        }

        const validQuestions = questions.filter(q => {
            return q && 
                   typeof q.content === 'string' && q.content.trim() &&
                   typeof q.type === 'string' &&
                   Array.isArray(q.options) && q.options.length >= 4 &&
                   typeof q.correct_answer === 'string' &&
                   typeof q.difficulty_level === 'number' &&
                   Array.isArray(q.knowledge_points);
        });

        console.log(`[AI] 验证结果: ${validQuestions.length}/${questions.length} 道题目有效`);
        return validQuestions.length > 0 ? validQuestions : null;
    }

    // 兼容单个题目解析
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

    // 生成多个模拟题目
    getMockQuestions(context) {
        const { difficulty = 3, questionCount = 8, existingQuestions = [] } = context;
        
        const allMockQuestions = [
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
            },
            {
                content: "化简：3x + 2x = ?",
                type: "multiple_choice",
                options: ["A. 5x", "B. 6x", "C. 5x²", "D. 6"],
                correct_answer: "A",
                difficulty_level: difficulty,
                knowledge_points: ["代数式"],
                explanation: "同类项合并：3x + 2x = 5x"
            },
            {
                content: "计算：2² × 3 = ?",
                type: "multiple_choice",
                options: ["A. 12", "B. 18", "C. 36", "D. 6"],
                correct_answer: "A",
                difficulty_level: difficulty,
                knowledge_points: ["幂运算", "有理数运算"],
                explanation: "2² = 4，4 × 3 = 12"
            },
            {
                content: "下列哪个数是质数？",
                type: "multiple_choice",
                options: ["A. 9", "B. 15", "C. 17", "D. 21"],
                correct_answer: "C",
                difficulty_level: difficulty,
                knowledge_points: ["质数"],
                explanation: "17只能被1和17整除，是质数"
            },
            {
                content: "计算：(-2) × (-3) = ?",
                type: "multiple_choice",
                options: ["A. -6", "B. 6", "C. -1", "D. 1"],
                correct_answer: "B",
                difficulty_level: difficulty,
                knowledge_points: ["有理数运算"],
                explanation: "负数乘负数得正数：(-2) × (-3) = 6"
            },
            {
                content: "若 3x - 1 = 8，则 x = ?",
                type: "multiple_choice",
                options: ["A. 2", "B. 3", "C. 4", "D. 5"],
                correct_answer: "B",
                difficulty_level: difficulty,
                knowledge_points: ["一元一次方程"],
                explanation: "3x = 9，所以 x = 3"
            },
            {
                content: "计算：|−7| + |3| = ?",
                type: "multiple_choice",
                options: ["A. 4", "B. 10", "C. -4", "D. -10"],
                correct_answer: "B",
                difficulty_level: difficulty,
                knowledge_points: ["绝对值"],
                explanation: "|−7| = 7，|3| = 3，所以 7 + 3 = 10"
            },
            {
                content: "下列式子中，正确的是：",
                type: "multiple_choice",
                options: ["A. a + a = a²", "B. a × a = 2a", "C. a + a = 2a", "D. a² + a² = 2a"],
                correct_answer: "C",
                difficulty_level: difficulty,
                knowledge_points: ["代数式"],
                explanation: "同类项合并：a + a = 2a"
            }
        ];
        
        // 过滤掉已存在的题目
        const existingContents = existingQuestions.map(q => q.content);
        const availableQuestions = allMockQuestions.filter(q => 
            !existingContents.includes(q.content)
        );
        
        // 如果可用题目不足，使用所有题目
        const sourceQuestions = availableQuestions.length >= questionCount ? 
            availableQuestions : allMockQuestions;
        
        // 随机选择题目
        const shuffled = [...sourceQuestions].sort(() => Math.random() - 0.5);
        return shuffled.slice(0, questionCount);
    }

    // 兼容单个题目
    getMockQuestion(context) {
        const questions = this.getMockQuestions({...context, questionCount: 1});
        return questions[0];
    }

    async generateReport(assessmentData) {
        if (!this.apiKey) {
            return this.getMockReport(assessmentData);
        }

        for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
            try {
                console.log(`[AI] 尝试生成报告，第${attempt}次尝试`);
                const prompt = this.buildReportPrompt(assessmentData);
                const response = await axios.post(
                    `${this.baseURL}/services/aigc/text-generation/generation`,
                    {
                        model: "qwen-plus",
                        input: {
                            messages: [
                                {
                                    role: "system",
                                    content: "你是一个专业的教育评估专家，能够分析学生的测评结果并提供个性化的学习建议。必须严格按照JSON格式返回分析报告，不要添加任何解释文字。"
                                },
                                {
                                    role: "user",
                                    content: prompt
                                }
                            ]
                        },
                        parameters: {
                            temperature: 0.5,
                            max_tokens: 2500,
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

                console.log(`[AI] 第${attempt}次尝试，报告API响应结构:`, JSON.stringify(response.data, null, 2));
                const report = this.parseReportResponse(response.data.output?.choices?.[0]?.message?.content);
                
                if (report && this.validateReport(report)) {
                    console.log(`[AI] 第${attempt}次尝试成功生成报告`);
                    return report;
                } else {
                    console.warn(`[AI] 第${attempt}次尝试生成的报告格式无效`);
                }
            } catch (error) {
                console.error(`[AI] 第${attempt}次尝试生成报告失败:`, error.message);
                if (attempt === this.maxRetries) {
                    console.error('[AI] 所有尝试均失败，使用模拟报告');
                    return this.getMockReport(assessmentData);
                }
                // 等待1秒后重试
                await new Promise(resolve => setTimeout(resolve, 1000));
            }
        }
        
        return this.getMockReport(assessmentData);
    }

    buildReportPrompt(assessmentData) {
        const { answers, totalQuestions, correctCount, subject } = assessmentData;
        const accuracy = totalQuestions > 0 ? (correctCount / totalQuestions * 100).toFixed(1) : 0;
        
        let prompt = `请为学生的${subject}测评结果生成专业的学习分析报告。\n\n`;
        prompt += `## 测评数据\n`;
        prompt += `- 科目：${subject}\n`;
        prompt += `- 总题数：${totalQuestions}题\n`;
        prompt += `- 正确题数：${correctCount}题\n`;
        prompt += `- 正确率：${accuracy}%\n\n`;
        
        if (answers && answers.length > 0) {
            prompt += `## 详细答题记录\n`;
            answers.forEach((answer, index) => {
                prompt += `第${index + 1}题：${answer.isCorrect ? '✓正确' : '✗错误'}`;
                if (answer.knowledgePoints && answer.knowledgePoints.length > 0) {
                    prompt += ` | 知识点：${answer.knowledgePoints.join('、')}`;
                }
                if (answer.responseTime) {
                    prompt += ` | 用时：${answer.responseTime}秒`;
                }
                prompt += `\n`;
            });
            
            // 知识点分析
            const knowledgeStats = {};
            answers.forEach(answer => {
                if (answer.knowledgePoints) {
                    answer.knowledgePoints.forEach(kp => {
                        if (!knowledgeStats[kp]) {
                            knowledgeStats[kp] = { correct: 0, total: 0 };
                        }
                        knowledgeStats[kp].total++;
                        if (answer.isCorrect) {
                            knowledgeStats[kp].correct++;
                        }
                    });
                }
            });
            
            if (Object.keys(knowledgeStats).length > 0) {
                prompt += `\n## 知识点掌握情况\n`;
                Object.entries(knowledgeStats).forEach(([kp, stats]) => {
                    const kpAccuracy = ((stats.correct / stats.total) * 100).toFixed(1);
                    prompt += `${kp}：${stats.correct}/${stats.total}题正确 (${kpAccuracy}%)\n`;
                });
            }
        }
        
        prompt += `\n## 要求
请基于以上数据生成完整的JSON格式分析报告，必须包含以下所有字段：

\`\`\`json
{
    "overall_score": ${Math.round(accuracy)},
    "strengths": ["学生表现突出的方面1", "学生表现突出的方面2"],
    "weaknesses": ["需要改进的薄弱点1", "需要改进的薄弱点2"],
    "recommendations": ["具体学习建议1", "具体学习建议2", "具体学习建议3"],
    "learning_plan": {
        "immediate": ["即时行动建议，今天就可以做的"],
        "short_term": ["1-2周内的学习计划"],
        "long_term": ["1-3个月的提升目标"]
    },
    "ai_analysis": "基于数据的详细分析，包括学习能力评估、知识掌握分析、学习建议等，字数300-500字"
}
\`\`\`

注意事项：
1. 所有字段都必须存在且格式正确
2. 数组字段不能为空，至少包含2个元素
3. overall_score必须是0-100的数字
4. ai_analysis要详细具体，有针对性
5. 只返回JSON，不要添加任何解释文字
6. 确保JSON格式完全正确，可以直接解析`;

        return prompt;
    }

    // 验证报告格式
    validateReport(report) {
        try {
            return report &&
                   typeof report.overall_score === 'number' &&
                   report.overall_score >= 0 && report.overall_score <= 100 &&
                   Array.isArray(report.strengths) && report.strengths.length >= 2 &&
                   Array.isArray(report.weaknesses) && report.weaknesses.length >= 2 &&
                   Array.isArray(report.recommendations) && report.recommendations.length >= 3 &&
                   report.learning_plan &&
                   Array.isArray(report.learning_plan.immediate) && report.learning_plan.immediate.length > 0 &&
                   Array.isArray(report.learning_plan.short_term) && report.learning_plan.short_term.length > 0 &&
                   Array.isArray(report.learning_plan.long_term) && report.learning_plan.long_term.length > 0 &&
                   typeof report.ai_analysis === 'string' && report.ai_analysis.length > 50;
        } catch (error) {
            console.error('[AI] 报告验证失败:', error.message);
            return false;
        }
    }

    parseReportResponse(response) {
        if (!response) {
            console.error('[AI] 报告响应内容为空');
            return null;
        }

        try {
            console.log('[AI] 原始报告响应:', response);
            
            // 尝试直接解析JSON
            if (typeof response === 'object') {
                return this.validateReport(response) ? response : null;
            }
            
            if (typeof response === 'string') {
                // 清理响应内容，移除markdown标记
                let cleanResponse = response.replace(/```json\s*/g, '').replace(/```\s*/g, '');
                
                // 尝试直接解析
                try {
                    const directParse = JSON.parse(cleanResponse);
                    if (this.validateReport(directParse)) {
                        console.log('[AI] 直接解析报告成功');
                        return directParse;
                    }
                } catch (e) {
                    // 继续尝试其他方式
                }
                
                // 尝试提取JSON对象（更宽松的匹配）
                const jsonMatch = cleanResponse.match(/\{[\s\S]*\}/);
                if (jsonMatch) {
                    try {
                        const parsed = JSON.parse(jsonMatch[0]);
                        if (this.validateReport(parsed)) {
                            console.log('[AI] 提取解析报告成功');
                            return parsed;
                        }
                    } catch (e) {
                        console.error('[AI] JSON提取解析失败:', e.message);
                    }
                }
                
                // 尝试修复常见的JSON格式问题
                try {
                    let fixedJson = cleanResponse;
                    // 修复常见的引号问题
                    fixedJson = fixedJson.replace(/'/g, '"');
                    // 修复NaN值
                    fixedJson = fixedJson.replace(/:\s*NaN/g, ': 0');
                    // 修复undefined值
                    fixedJson = fixedJson.replace(/:\s*undefined/g, ': null');
                    
                    const fixedMatch = fixedJson.match(/\{[\s\S]*\}/);
                    if (fixedMatch) {
                        const parsed = JSON.parse(fixedMatch[0]);
                        if (this.validateReport(parsed)) {
                            console.log('[AI] 修复解析报告成功');
                            return parsed;
                        }
                    }
                } catch (e) {
                    console.error('[AI] 修复解析失败:', e.message);
                }
            }
        } catch (error) {
            console.error('[AI] 解析报告失败:', error.message);
            console.error('[AI] 原始响应:', response);
        }
        
        console.warn('[AI] 所有解析方式失败，返回null');
        return null;
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

    // 生成学期学习规划
    async generateSemesterPlan(planData) {
        if (!this.apiKey) {
            return this.getMockSemesterPlan(planData);
        }

        for (let attempt = 1; attempt <= this.maxRetries; attempt++) {
            try {
                console.log(`[AI] 尝试生成学期规划，第${attempt}次尝试`);
                const prompt = this.buildSemesterPlanPrompt(planData);
                const response = await axios.post(
                    `${this.baseURL}/services/aigc/text-generation/generation`,
                    {
                        model: "qwen-plus",
                        input: {
                            messages: [
                                {
                                    role: "system",
                                    content: "你是一个专业的教育规划专家，能够基于学生的学习数据制定个性化的学期学习规划。必须严格按照JSON格式返回规划内容。"
                                },
                                {
                                    role: "user",
                                    content: prompt
                                }
                            ]
                        },
                        parameters: {
                            temperature: 0.6,
                            max_tokens: 2500,
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

                console.log(`[AI] 第${attempt}次尝试，学期规划API响应:`, JSON.stringify(response.data, null, 2));
                const plan = this.parseSemesterPlanResponse(response.data.output?.choices?.[0]?.message?.content);
                
                if (plan && this.validateSemesterPlan(plan)) {
                    console.log(`[AI] 第${attempt}次尝试成功生成学期规划`);
                    return plan;
                } else {
                    console.warn(`[AI] 第${attempt}次尝试生成的规划格式无效`);
                }
            } catch (error) {
                console.error(`[AI] 第${attempt}次尝试生成学期规划失败:`, error.message);
                if (attempt === this.maxRetries) {
                    console.error('[AI] 所有尝试均失败，使用模拟规划');
                    return this.getMockSemesterPlan(planData);
                }
                await new Promise(resolve => setTimeout(resolve, 1000));
            }
        }
        
        return this.getMockSemesterPlan(planData);
    }

    buildSemesterPlanPrompt(planData) {
        const { studentId, semester, subject, assessmentHistory, currentPerformance } = planData;
        
        let prompt = `请为学生制定${semester}学期的${subject}学习规划。\n\n`;
        
        if (assessmentHistory && assessmentHistory.length > 0) {
            prompt += `## 学生历史表现数据\n`;
            assessmentHistory.forEach((record, index) => {
                prompt += `测评${index + 1}：得分${record.score}分，正确率${record.accuracy}%，`;
                prompt += `强项：${record.strengths?.join('、') || '暂无'}，`;
                prompt += `薄弱点：${record.weaknesses?.join('、') || '暂无'}\n`;
            });
        }
        
        if (currentPerformance) {
            prompt += `\n## 当前综合表现\n`;
            prompt += `平均得分：${currentPerformance.averageScore || 0}分\n`;
            prompt += `平均正确率：${currentPerformance.averageAccuracy || 0}%\n`;
            prompt += `主要强项：${currentPerformance.mainStrengths?.join('、') || '待分析'}\n`;
            prompt += `主要薄弱点：${currentPerformance.mainWeaknesses?.join('、') || '待分析'}\n`;
        }
        
        prompt += `\n## 要求
请基于以上数据生成完整的JSON格式学期学习规划：

\`\`\`json
{
    "overall_performance": "对学生整体表现的客观评价和分析",
    "learning_goals": ["本学期主要学习目标1", "本学期主要学习目标2", "本学期主要学习目标3"],
    "study_schedule": {
        "weekly_plan": ["每周学习安排1", "每周学习安排2", "每周学习安排3"],
        "monthly_milestones": ["第一个月目标", "第二个月目标", "第三个月目标", "第四个月目标"],
        "daily_practice": ["每日练习建议1", "每日练习建议2"]
    },
    "key_improvements": ["重点提升领域1", "重点提升领域2", "重点提升领域3"],
    "resources_needed": ["推荐学习资源1", "推荐学习资源2", "推荐学习资源3"],
    "progress_tracking": ["进度跟踪方法1", "进度跟踪方法2", "进度跟踪方法3"],
    "ai_analysis": "基于数据的详细分析和个性化建议，包含学习策略、时间安排、重难点突破等，字数400-600字"
}
\`\`\`

注意事项：
1. 所有字段都必须存在且内容充实
2. 数组字段至少包含3个具体的条目
3. 学习目标要具体可衡量
4. 时间安排要合理可执行
5. AI分析要深入具体，有实用性
6. 只返回JSON，不要添加解释文字`;

        return prompt;
    }

    parseSemesterPlanResponse(response) {
        if (!response) {
            console.error('[AI] 学期规划响应内容为空');
            return null;
        }

        try {
            console.log('[AI] 原始学期规划响应:', response);
            
            if (typeof response === 'object') {
                return this.validateSemesterPlan(response) ? response : null;
            }
            
            if (typeof response === 'string') {
                let cleanResponse = response.replace(/```json\s*/g, '').replace(/```\s*/g, '');
                
                try {
                    const directParse = JSON.parse(cleanResponse);
                    if (this.validateSemesterPlan(directParse)) {
                        console.log('[AI] 直接解析学期规划成功');
                        return directParse;
                    }
                } catch (e) {
                    // 继续尝试其他方式
                }
                
                const jsonMatch = cleanResponse.match(/\{[\s\S]*\}/);
                if (jsonMatch) {
                    try {
                        const parsed = JSON.parse(jsonMatch[0]);
                        if (this.validateSemesterPlan(parsed)) {
                            console.log('[AI] 提取解析学期规划成功');
                            return parsed;
                        }
                    } catch (e) {
                        console.error('[AI] JSON提取解析失败:', e.message);
                    }
                }
            }
        } catch (error) {
            console.error('[AI] 解析学期规划失败:', error.message);
        }
        
        return null;
    }

    validateSemesterPlan(plan) {
        try {
            return plan &&
                   typeof plan.overall_performance === 'string' && plan.overall_performance.length > 20 &&
                   Array.isArray(plan.learning_goals) && plan.learning_goals.length >= 3 &&
                   plan.study_schedule &&
                   Array.isArray(plan.study_schedule.weekly_plan) && plan.study_schedule.weekly_plan.length >= 3 &&
                   Array.isArray(plan.study_schedule.monthly_milestones) && plan.study_schedule.monthly_milestones.length >= 4 &&
                   Array.isArray(plan.study_schedule.daily_practice) && plan.study_schedule.daily_practice.length >= 2 &&
                   Array.isArray(plan.key_improvements) && plan.key_improvements.length >= 3 &&
                   Array.isArray(plan.resources_needed) && plan.resources_needed.length >= 3 &&
                   Array.isArray(plan.progress_tracking) && plan.progress_tracking.length >= 3 &&
                   typeof plan.ai_analysis === 'string' && plan.ai_analysis.length > 100;
        } catch (error) {
            console.error('[AI] 学期规划验证失败:', error.message);
            return false;
        }
    }

    getMockSemesterPlan(planData) {
        const { subject = '数学', semester = '本学期' } = planData;
        
        return {
            overall_performance: `基于历史测评数据分析，您在${subject}学科表现出良好的学习潜力。在基础知识掌握方面表现稳定，但在应用能力和综合分析方面还有提升空间。建议在${semester}重点加强练习和知识点巩固。`,
            learning_goals: [
                `提高${subject}基础知识的熟练度，达到90%以上的正确率`,
                `增强解题技巧和思维逻辑，缩短答题时间`,
                `培养自主学习能力，建立完整的知识体系`
            ],
            study_schedule: {
                weekly_plan: [
                    "每周完成3-4次练习，每次45分钟",
                    "周末进行1次综合复习和错题整理",
                    "每周学习2个新知识点并做相关练习"
                ],
                monthly_milestones: [
                    "第一个月：巩固基础概念，完成入门测评",
                    "第二个月：提高解题速度，掌握核心题型",
                    "第三个月：加强综合应用，攻克难点",
                    "第四个月：系统复习，准备期末测评"
                ],
                daily_practice: [
                    "每日完成10-15道基础练习题",
                    "每日复习当天所学知识点并做笔记"
                ]
            },
            key_improvements: [
                "加强基础运算能力，提高计算准确性",
                "培养逻辑思维能力，提升解题效率",
                "增强知识点间的联系理解，建立知识网络"
            ],
            resources_needed: [
                "教材配套练习册和在线题库",
                "错题本和学习笔记本",
                "在线学习平台和视频教程资源"
            ],
            progress_tracking: [
                "每周进行小测验，跟踪学习进度",
                "每月进行综合测评，评估学习效果",
                "建立学习档案，记录进步轨迹和反思总结"
            ],
            ai_analysis: `根据您的学习数据分析，建议采用"循序渐进、重点突破"的学习策略。首先巩固基础知识，确保概念理解透彻；然后通过大量练习提高解题熟练度；最后进行综合应用训练。学习时间安排建议每天1小时，周末可延长至2小时。重点关注薄弱知识点的突破，建议采用"错题重做"的方法加深印象。同时要注意劳逸结合，保持学习的积极性和持续性。定期进行自我评估，及时调整学习计划和方法。`
        };
    }
}

const aiService = new DashscopeAI();

// API路由

// 开始新的测评会话（一次性生成所有题目）
app.post('/api/assessment/start', async (req, res) => {
    try {
        console.log('[API] 收到开始测评请求:', req.body);
        
        const { studentId = 'student_001', subject = '数学', gradeLevel = '七年级' } = req.body;
        const sessionId = uuidv4();
        const questionCount = 8;
        
        console.log('[API] 创建会话:', { sessionId, studentId, subject, gradeLevel });
        
        // 创建测评会话
        await new Promise((resolve, reject) => {
            db.run(
                `INSERT INTO assessment_sessions (id, student_id, subject, type) 
                 VALUES (?, ?, ?, ?)`,
                [sessionId, studentId, subject, gradeLevel],
                function(err) {
                    if (err) reject(err);
                    else resolve();
                }
            );
        });

        console.log('[API] 会话创建成功，开始生成题目');

        // 一次性生成所有题目
        const questionContext = {
            subject,
            difficulty: 2, // 开始难度
            questionCount,
            knowledgePoints: ['有理数', '绝对值', '数轴', '运算', '代数式', '方程'],
            existingQuestions: [] // 避免重复
        };

        console.log('[API] 准备调用AI服务生成题目，参数:', questionContext);
        
        let questions;
        try {
            questions = await aiService.generateQuestions(questionContext);
            console.log(`[API] AI生成 ${questions.length} 道题目成功`);
        } catch (error) {
            console.warn('[API] AI生成题目失败，使用模拟题目:', error.message);
            questions = aiService.getMockQuestions(questionContext);
        }

        // 保存题目到数据库
        for (let i = 0; i < questions.length; i++) {
            const question = questions[i];
            const questionId = uuidv4();
            
            await new Promise((resolve, reject) => {
                db.run(
                    `INSERT INTO questions (id, session_id, content, type, options, correct_answer, difficulty_level, knowledge_points, explanation, ai_generated)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [
                        questionId,
                        sessionId,
                        question.content,
                        question.type,
                        JSON.stringify(question.options || []),
                        question.correct_answer,
                        question.difficulty_level,
                        Array.isArray(question.knowledge_points) ? question.knowledge_points.join(',') : '',
                        question.explanation || '',
                        1
                    ],
                    function(err) {
                        if (err) reject(err);
                        else {
                            questions[i].id = questionId;
                            resolve();
                        }
                    }
                );
            });
        }

        console.log('[API] 所有题目已保存到数据库');

        res.json({
            success: true,
            session: {
                id: sessionId,
                studentId,
                subject,
                gradeLevel,
                questionCount: questions.length
            },
            questions: questions,
            message: `测评会话创建成功，已生成${questions.length}道题目`
        });

    } catch (error) {
        console.error('[API] 创建测评会话失败:', error);
        res.status(500).json({ 
            success: false,
            error: '创建测评会话失败',
            details: error.message 
        });
    }
});

// 获取下一题（从预生成的题目中获取）
app.post('/api/assessment/next-question', async (req, res) => {
    try {
        console.log('[API] 收到获取下一题请求:', req.body);
        const { sessionId, previousAnswers = [] } = req.body;
        
        if (!sessionId) {
            return res.status(400).json({ 
                success: false, 
                error: '缺少sessionId参数' 
            });
        }

        // 先保存上一题的答案（如果有的话）
        if (previousAnswers.length > 0) {
            const lastAnswer = previousAnswers[previousAnswers.length - 1];
            if (lastAnswer && !lastAnswer.saved) {
                const answerId = uuidv4();
                await new Promise((resolve, reject) => {
                    db.run(
                        `INSERT INTO student_answers (id, session_id, question_id, student_answer, is_correct, response_time)
                         VALUES (?, ?, ?, ?, ?, ?)`,
                        [
                            answerId,
                            sessionId,
                            lastAnswer.questionId,
                            lastAnswer.studentAnswer,
                            lastAnswer.isCorrect ? 1 : 0,
                            lastAnswer.responseTime || 0
                        ],
                        function(err) {
                            if (err) reject(err);
                            else resolve();
                        }
                    );
                });
            }
        }

        const currentQuestionIndex = previousAnswers.length;
        console.log(`[API] 获取第 ${currentQuestionIndex + 1} 题，会话ID: ${sessionId}`);

        // 从数据库获取该会话的所有题目
        db.all(
            `SELECT * FROM questions WHERE session_id = ? ORDER BY created_at`,
            [sessionId],
            (err, questions) => {
                if (err) {
                    console.error('[API] 查询题目失败:', err);
                    return res.status(500).json({ 
                        success: false, 
                        error: '查询题目失败' 
                    });
                }

                if (!questions || questions.length === 0) {
                    console.error('[API] 未找到该会话的题目');
                    return res.status(404).json({ 
                        success: false, 
                        error: '未找到题目，请重新开始测评' 
                    });
                }

                if (currentQuestionIndex >= questions.length) {
                    console.log('[API] 所有题目已完成');
                    return res.json({
                        success: true,
                        completed: true,
                        message: '所有题目已完成',
                        totalQuestions: questions.length
                    });
                }

                const currentQuestion = questions[currentQuestionIndex];
                
                // 解析选项（如果是JSON字符串）
                let options = [];
                try {
                    if (currentQuestion.options) {
                        options = JSON.parse(currentQuestion.options);
                    }
                } catch (e) {
                    console.warn('[API] 解析题目选项失败:', e.message);
                }

                const questionData = {
                    id: currentQuestion.id,
                    content: currentQuestion.content,
                    type: currentQuestion.type,
                    options: options,
                    correct_answer: currentQuestion.correct_answer,
                    difficulty_level: currentQuestion.difficulty_level,
                    knowledge_points: currentQuestion.knowledge_points ? 
                        currentQuestion.knowledge_points.split(',') : [],
                    explanation: currentQuestion.explanation || '',
                    questionNumber: currentQuestionIndex + 1,
                    totalQuestions: questions.length
                };

                console.log(`[API] 返回第 ${currentQuestionIndex + 1} 题:`, questionData.content);

                res.json({
                    success: true,
                    question: questionData
                });
            }
        );
        
    } catch (error) {
        console.error('[API] 获取下一题失败:', error);
        res.status(500).json({ 
            success: false, 
            error: '获取下一题失败',
            details: error.message 
        });
    }
});

// 完成测评并生成报告
app.post('/api/assessment/complete', async (req, res) => {
    try {
        const { sessionId, answers } = req.body;
        
        console.log('[API] 收到完成测评请求:', { sessionId, answersCount: answers?.length });
        
        // 保存所有答案到数据库
        if (answers && answers.length > 0) {
            for (const answer of answers) {
                const answerId = uuidv4();
                await new Promise((resolve, reject) => {
                    db.run(
                        `INSERT INTO student_answers (id, session_id, question_id, student_answer, is_correct, response_time)
                         VALUES (?, ?, ?, ?, ?, ?)`,
                        [
                            answerId,
                            sessionId,
                            answer.questionId,
                            answer.studentAnswer,
                            answer.isCorrect ? 1 : 0,
                            answer.responseTime || 0
                        ],
                        function(err) {
                            if (err) reject(err);
                            else resolve();
                        }
                    );
                });
            }
            console.log('[API] 保存了', answers.length, '个答案记录');
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

// 获取学生数据看板统计
app.get('/api/dashboard/:studentId', (req, res) => {
    const { studentId } = req.params;
    
    console.log('[API] 获取数据看板统计，学生ID:', studentId);
    
    // 获取测评统计数据
    db.all(
        `SELECT 
            ar.overall_score,
            ar.strengths,
            ar.weaknesses,
            s.subject,
            s.completed_at,
            ar.created_at,
            s.status,
            s.id as session_id
         FROM assessment_reports ar
         JOIN assessment_sessions s ON ar.session_id = s.id
         WHERE s.student_id = ? AND s.status = 'completed'
         ORDER BY s.completed_at DESC
         LIMIT 10`,
        [studentId],
        (err, reports) => {
            if (err) {
                console.error('[API] 数据看板查询错误:', err);
                return res.status(500).json({ error: '获取数据失败' });
            }
            
            console.log('[API] 查询到', reports.length, '条完成的测评记录');
            
            // 计算统计数据
            const totalTests = reports.length;
            const averageScore = totalTests > 0 ? 
                Math.round(reports.reduce((sum, r) => sum + r.overall_score, 0) / totalTests) : 0;
            
            // 获取最新测评
            const latestTest = reports[0];
            
            // 分析强项和薄弱点
            const allStrengths = [];
            const allWeaknesses = [];
            
            reports.forEach(report => {
                try {
                    const strengths = JSON.parse(report.strengths || '[]');
                    const weaknesses = JSON.parse(report.weaknesses || '[]');
                    allStrengths.push(...strengths);
                    allWeaknesses.push(...weaknesses);
                } catch (e) {
                    // 忽略解析错误
                }
            });
            
            // 统计出现频率最高的强项和薄弱点
            const strengthCounts = {};
            const weaknessCounts = {};
            
            allStrengths.forEach(s => {
                strengthCounts[s] = (strengthCounts[s] || 0) + 1;
            });
            
            allWeaknesses.forEach(w => {
                weaknessCounts[w] = (weaknessCounts[w] || 0) + 1;
            });
            
            const topStrengths = Object.entries(strengthCounts)
                .sort(([,a], [,b]) => b - a)
                .slice(0, 3)
                .map(([strength]) => strength);
                
            const topWeaknesses = Object.entries(weaknessCounts)
                .sort(([,a], [,b]) => b - a)
                .slice(0, 3)
                .map(([weakness]) => weakness);
            
            // 计算本月测评次数
            const currentMonth = new Date().getMonth();
            const currentYear = new Date().getFullYear();
            const thisMonthTests = reports.filter(r => {
                const testDate = new Date(r.completed_at);
                return testDate.getMonth() === currentMonth && testDate.getFullYear() === currentYear;
            }).length;
            
            // 生成图表数据
            const chartData = {
                scoreHistory: reports.slice(0, 7).reverse().map((r, index) => ({
                    test: `测评${index + 1}`,
                    score: r.overall_score,
                    date: r.completed_at
                })),
                knowledgePoints: topStrengths.concat(topWeaknesses).map(point => ({
                    name: point,
                    value: Math.floor(Math.random() * 30) + 70, // 模拟掌握度
                    type: topStrengths.includes(point) ? 'strength' : 'weakness'
                }))
            };
            
            res.json({
                success: true,
                dashboard: {
                    totalTests,
                    averageScore,
                    thisMonthTests,
                    latestScore: latestTest?.overall_score || 0,
                    improvementTrend: totalTests >= 2 ? 
                        (reports[0].overall_score - reports[1].overall_score) : 0,
                    topStrengths,
                    topWeaknesses,
                    chartData,
                    lastTestDate: latestTest?.completed_at
                }
            });
        }
    );
});

// 生成学期学习规划
app.post('/api/semester-plan/generate', async (req, res) => {
    try {
        const { studentId, semester = '本学期', subject = '数学' } = req.body;
        
        console.log('[API] 收到生成学期规划请求:', { studentId, semester, subject });
        
        // 获取学生的测评历史
        const assessmentHistory = await new Promise((resolve, reject) => {
            db.all(
                `SELECT 
                    ar.overall_score as score,
                    CAST(ar.overall_score AS REAL) as accuracy,
                    ar.strengths,
                    ar.weaknesses,
                    s.completed_at
                 FROM assessment_reports ar
                 JOIN assessment_sessions s ON ar.session_id = s.id
                 WHERE s.student_id = ? AND s.status = 'completed'
                 ORDER BY s.completed_at DESC
                 LIMIT 5`,
                [studentId],
                (err, rows) => {
                    if (err) reject(err);
                    else {
                        const history = rows.map(row => ({
                            score: row.score,
                            accuracy: row.accuracy,
                            strengths: JSON.parse(row.strengths || '[]'),
                            weaknesses: JSON.parse(row.weaknesses || '[]'),
                            date: row.completed_at
                        }));
                        resolve(history);
                    }
                }
            );
        });
        
        // 计算当前综合表现
        const currentPerformance = {
            averageScore: assessmentHistory.length > 0 ? 
                Math.round(assessmentHistory.reduce((sum, h) => sum + h.score, 0) / assessmentHistory.length) : 0,
            averageAccuracy: assessmentHistory.length > 0 ? 
                Math.round(assessmentHistory.reduce((sum, h) => sum + h.accuracy, 0) / assessmentHistory.length) : 0,
            mainStrengths: [],
            mainWeaknesses: []
        };
        
        // 分析主要强项和薄弱点
        const allStrengths = assessmentHistory.flatMap(h => h.strengths);
        const allWeaknesses = assessmentHistory.flatMap(h => h.weaknesses);
        
        const strengthCounts = {};
        const weaknessCounts = {};
        
        allStrengths.forEach(s => {
            strengthCounts[s] = (strengthCounts[s] || 0) + 1;
        });
        
        allWeaknesses.forEach(w => {
            weaknessCounts[w] = (weaknessCounts[w] || 0) + 1;
        });
        
        currentPerformance.mainStrengths = Object.entries(strengthCounts)
            .sort(([,a], [,b]) => b - a)
            .slice(0, 3)
            .map(([strength]) => strength);
            
        currentPerformance.mainWeaknesses = Object.entries(weaknessCounts)
            .sort(([,a], [,b]) => b - a)
            .slice(0, 3)
            .map(([weakness]) => weakness);
        
        // 生成AI学期规划
        const planData = {
            studentId,
            semester,
            subject,
            assessmentHistory,
            currentPerformance
        };
        
        const semesterPlan = await aiService.generateSemesterPlan(planData);
        const planId = uuidv4();
        
        // 保存到数据库
        await new Promise((resolve, reject) => {
            db.run(
                `INSERT INTO semester_plans 
                 (id, student_id, semester, subject, overall_performance, learning_goals, 
                  study_schedule, key_improvements, resources_needed, progress_tracking, ai_analysis)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                [
                    planId,
                    studentId,
                    semester,
                    subject,
                    semesterPlan.overall_performance,
                    JSON.stringify(semesterPlan.learning_goals),
                    JSON.stringify(semesterPlan.study_schedule),
                    JSON.stringify(semesterPlan.key_improvements),
                    JSON.stringify(semesterPlan.resources_needed),
                    JSON.stringify(semesterPlan.progress_tracking),
                    semesterPlan.ai_analysis
                ],
                function(err) {
                    if (err) reject(err);
                    else resolve();
                }
            );
        });
        
        console.log('[API] 学期规划生成并保存成功');
        
        res.json({
            success: true,
            plan: {
                id: planId,
                ...semesterPlan,
                createdAt: new Date().toISOString()
            },
            message: '学期学习规划生成成功'
        });
        
    } catch (error) {
        console.error('[API] 生成学期规划失败:', error);
        res.status(500).json({
            success: false,
            error: '生成学期规划失败',
            details: error.message
        });
    }
});

// 获取学期学习规划
app.get('/api/semester-plan/:studentId', (req, res) => {
    const { studentId } = req.params;
    const { semester, subject } = req.query;
    
    let query = `SELECT * FROM semester_plans WHERE student_id = ?`;
    let params = [studentId];
    
    if (semester) {
        query += ` AND semester = ?`;
        params.push(semester);
    }
    
    if (subject) {
        query += ` AND subject = ?`;
        params.push(subject);
    }
    
    query += ` ORDER BY created_at DESC LIMIT 1`;
    
    db.get(query, params, (err, plan) => {
        if (err) {
            return res.status(500).json({ error: '获取学期规划失败' });
        }
        
        if (!plan) {
            return res.status(404).json({ error: '未找到学期规划' });
        }
        
        // 解析JSON字段
        try {
            plan.learning_goals = JSON.parse(plan.learning_goals || '[]');
            plan.study_schedule = JSON.parse(plan.study_schedule || '{}');
            plan.key_improvements = JSON.parse(plan.key_improvements || '[]');
            plan.resources_needed = JSON.parse(plan.resources_needed || '[]');
            plan.progress_tracking = JSON.parse(plan.progress_tracking || '[]');
        } catch (parseError) {
            console.error('解析学期规划数据失败:', parseError);
        }
        
        res.json({
            success: true,
            plan
        });
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