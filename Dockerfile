# SeekerAI智能学习平台 Dockerfile
FROM node:18-alpine

# 设置工作目录
WORKDIR /app

# 安装系统依赖
RUN apk add --no-cache \
    sqlite \
    sqlite-dev \
    python3 \
    make \
    g++

# 复制package文件
COPY package*.json ./

# 安装Node.js依赖
RUN npm install --production && npm cache clean --force

# 复制项目文件
COPY . .

# 创建必要的目录
RUN mkdir -p database logs && \
    chmod 755 database logs

# 设置环境变量
ENV NODE_ENV=production
ENV PORT=3000

# 暴露端口
EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:3000/ || exit 1

# 启动应用
CMD ["node", "server.js"] 