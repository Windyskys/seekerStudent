# SeekerAI智能学习平台 - AI测评系统

## 项目简介

这是一个基于AI的智能学习测评平台，主要功能包括：

- 🤖 **AI智能出题**：基于阿里百炼平台API，根据学生答题情况自适应生成题目
- 📊 **智能测评分析**：实时分析答题表现，动态调整题目难度
- 📝 **AI测评报告**：生成详细的学习分析报告和个性化学习建议
- 💾 **数据持久化**：使用SQLite数据库存储学生答题记录和测评报告
- 📱 **响应式设计**：支持多端访问，界面美观友好

## 技术架构

### 前端
- HTML5 + CSS3 + JavaScript (原生)
- Lucide Icons 图标库
- Chart.js 图表库
- 响应式设计，支持移动端

### 后端
- Node.js + Express
- SQLite 数据库
- RESTful API 设计
- 阿里百炼AI接口集成

### AI服务
- 阿里百炼平台 (DashScope)
- Qwen-Plus模型
- 支持智能题目生成和报告分析

## 安装指南

### 1. 环境要求
- Node.js >= 14.0.0
- npm >= 6.0.0

### 2. 安装依赖
```bash
npm install
```

### 3. 配置环境变量
复制 `.env.example` 文件为 `.env`：
```bash
cp .env.example .env
```

编辑 `.env` 文件，配置您的阿里百炼API密钥：
```env
# 阿里百炼API配置（Qwen-Plus模型）
QWEN_API_KEY=your_actual_api_key_here
DASHSCOPE_BASE_URL=https://dashscope.aliyuncs.com/api/v1

# 服务器配置
PORT=3000
NODE_ENV=development

# 数据库配置
DB_PATH=./database/seeker_ai.db
```

### 4. 获取阿里百炼API密钥
1. 访问 [阿里百炼平台](https://dashscope.aliyun.com/)
2. 注册/登录账号
3. 创建应用并获取API Key
4. 将API Key填入 `.env` 文件中的 `QWEN_API_KEY`

## 使用指南

### 启动后端服务
```bash
npm start
```

或者使用开发模式（自动重启）：
```bash
npm run dev
```

### 访问应用
启动成功后，在浏览器中访问：
- 主页：http://localhost:3000/index.html
- 测评页面：http://localhost:3000/assessment.html

## 功能特性

### 🎯 智能测评流程
1. **选择测评类型**：快速检测、能力评估、错题专项等
2. **AI生成题目**：根据学生水平动态生成合适难度的题目
3. **自适应难度调整**：根据答题正确率实时调整后续题目难度
4. **完成测评**：生成详细的AI分析报告

### 📊 测评报告内容
- **整体得分**：综合评分和正确率统计
- **知识点分析**：各个知识点的掌握情况
- **能力雷达图**：多维度学习能力分析
- **AI智能分析**：个性化的学习建议和改进方案
- **学习规划**：短期和中期的学习计划建议

### 🗄️ 数据库设计
- **students**：学生信息表
- **assessment_sessions**：测评会话表
- **questions**：题目表（支持AI生成题目）
- **student_answers**：学生答案表
- **assessment_reports**：测评报告表

## API接口文档

### 开始测评
```http
POST /api/assessment/start
Content-Type: application/json

{
  "studentId": "student_001",
  "subject": "数学",
  "type": "diagnostic"
}
```

### 获取下一题
```http
POST /api/assessment/next-question
Content-Type: application/json

{
  "sessionId": "session_xxx",
  "previousAnswer": {
    "questionId": "question_xxx",
    "answer": "B",
    "isCorrect": true,
    "responseTime": 30
  }
}
```

### 完成测评
```http
POST /api/assessment/complete
Content-Type: application/json

{
  "sessionId": "session_xxx",
  "finalAnswer": {
    "questionId": "question_xxx",
    "answer": "C",
    "isCorrect": false,
    "responseTime": 45
  }
}
```

### 获取测评报告
```http
GET /api/assessment/report/:sessionId
```

## 项目结构

```
seekerStudent/
├── css/
│   └── styles.css           # 样式文件
├── img/
│   ├── logo.svg            # Logo图标
│   └── logowhite.svg       # 白色Logo
├── database/
│   └── seeker_ai.db        # SQLite数据库（自动生成）
├── 人教初中数学教材/          # 教材资源
├── *.html                  # 前端页面
├── server.js               # 后端服务器
├── package.json            # 项目配置
├── .env                    # 环境变量配置
└── README.md              # 项目说明
```

## 开发特性

### 🔄 离线模式支持
当AI服务不可用时，系统会自动切换到离线模式，使用内置的题目库和分析模板，确保功能正常运行。

### 🎨 响应式设计
- 支持桌面端、平板和手机端
- 自适应布局，优化各种屏幕尺寸的显示效果
- 现代化的UI设计，提供良好的用户体验

### 🔧 可扩展架构
- 模块化设计，便于功能扩展
- 支持多科目测评（当前实现数学，可扩展到其他科目）
- 数据库结构设计考虑了未来功能扩展的需求

## 注意事项

1. **API密钥安全**：请勿将真实的API密钥提交到代码仓库中
2. **数据备份**：定期备份 `database/seeker_ai.db` 文件
3. **性能优化**：在生产环境中建议使用Redis等缓存系统
4. **安全设置**：在生产环境中请配置适当的CORS策略和身份认证

## 贡献指南

欢迎提交Issue和Pull Request来帮助改进这个项目！

## 许可证

MIT License

## 联系方式

如有问题或建议，请通过GitHub Issues联系我们。 