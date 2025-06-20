# Ubuntu服务器部署指南

## 🚀 快速部署

### 方法一：一键部署脚本（推荐）

1. **上传项目文件到服务器**
   ```bash
   # 使用scp上传项目文件
   scp -r /path/to/seekerStudent root@your-server-ip:/tmp/
   
   # 或者使用rsync
   rsync -avz --exclude node_modules /path/to/seekerStudent/ root@your-server-ip:/tmp/seekerStudent/
   ```

2. **连接到服务器并运行部署脚本**
   ```bash
   ssh root@your-server-ip
   cd /tmp/seekerStudent
   chmod +x deploy.sh
   sudo ./deploy.sh
   ```

3. **配置API密钥**
   ```bash
   nano /var/www/seekerStudent/.env
   # 修改 QWEN_API_KEY=your_actual_api_key_here
   ```

4. **重启服务**
   ```bash
   seeker-ai-manage restart
   ```

### 方法二：手动部署

如果您喜欢更多控制，可以按以下步骤手动部署：

#### 1. 系统准备
```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装基础依赖
sudo apt install -y curl wget git nginx ufw
```

#### 2. 安装Node.js
```bash
# 添加NodeSource仓库
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -

# 安装Node.js
sudo apt install -y nodejs

# 验证安装
node --version
npm --version
```

#### 3. 安装PM2
```bash
sudo npm install -g pm2
```

#### 4. 部署项目
```bash
# 创建项目目录
sudo mkdir -p /var/www/seekerStudent
sudo chown $USER:$USER /var/www/seekerStudent

# 复制项目文件
cp -r /tmp/seekerStudent/* /var/www/seekerStudent/
cd /var/www/seekerStudent

# 安装依赖
npm install --production
```

#### 5. 配置环境变量
```bash
cat > .env << EOF
QWEN_API_KEY=your_qwen_api_key_here
DASHSCOPE_BASE_URL=https://dashscope.aliyuncs.com/api/v1
PORT=3000
NODE_ENV=production
DB_PATH=./database/seeker_ai.db
EOF
```

#### 6. 配置PM2
```bash
cat > ecosystem.config.js << EOF
module.exports = {
  apps: [{
    name: 'seeker-ai',
    script: 'server.js',
    instances: 'max',
    exec_mode: 'cluster',
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
};
EOF

# 启动应用
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

#### 7. 配置Nginx
```bash
sudo cat > /etc/nginx/sites-available/seeker-ai << EOF
server {
    listen 80;
    server_name your-domain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

# 启用站点
sudo ln -s /etc/nginx/sites-available/seeker-ai /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
```

#### 8. 配置防火墙
```bash
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3000/tcp
```

## 🔧 管理和维护

### 服务管理
```bash
# 查看服务状态
pm2 status

# 重启服务
pm2 restart seeker-ai

# 查看日志
pm2 logs seeker-ai

# 停止服务
pm2 stop seeker-ai
```

### Nginx管理
```bash
# 检查配置
sudo nginx -t

# 重启Nginx
sudo systemctl restart nginx

# 查看状态
sudo systemctl status nginx
```

### 日志查看
```bash
# 应用日志
tail -f /var/www/seekerStudent/logs/combined.log

# Nginx日志
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# 系统日志
sudo journalctl -u nginx -f
```

## 🔒 SSL证书配置

### 使用Let's Encrypt
```bash
# 安装Certbot
sudo apt install -y certbot python3-certbot-nginx

# 获取证书
sudo certbot --nginx -d your-domain.com

# 设置自动续期
sudo crontab -e
# 添加: 0 12 * * * /usr/bin/certbot renew --quiet
```

## 📊 监控和优化

### 系统监控
```bash
# 查看系统资源
htop
df -h
free -h

# 查看网络连接
netstat -tulpn | grep :3000
```

### 性能优化
```bash
# PM2集群模式（已在配置中启用）
pm2 start ecosystem.config.js

# Nginx缓存配置（已包含在Nginx配置中）
# 静态文件缓存已自动配置
```

## 🔧 故障排查

### 常见问题

1. **端口被占用**
   ```bash
   sudo lsof -i :3000
   sudo kill -9 <PID>
   ```

2. **权限问题**
   ```bash
   sudo chown -R www-data:www-data /var/www/seekerStudent
   sudo chmod -R 755 /var/www/seekerStudent
   ```

3. **Node.js版本问题**
   ```bash
   node --version  # 确保 >= 14.0.0
   ```

4. **PM2无法启动**
   ```bash
   pm2 delete all
   pm2 start ecosystem.config.js
   ```

5. **数据库权限**
   ```bash
   sudo mkdir -p /var/www/seekerStudent/database
   sudo chown -R www-data:www-data /var/www/seekerStudent/database
   ```

### 日志分析
```bash
# 查看详细错误日志
pm2 logs seeker-ai --lines 100

# 查看Nginx错误
sudo tail -f /var/log/nginx/error.log

# 检查系统日志
sudo journalctl -xe
```

## 📋 检查清单

部署完成后，请检查以下项目：

- [ ] Node.js和npm已安装
- [ ] 项目依赖已安装
- [ ] 环境变量已配置（QWEN_API_KEY）
- [ ] PM2服务正常运行
- [ ] Nginx反向代理配置正确
- [ ] 防火墙规则已设置
- [ ] 应用可以通过80端口访问
- [ ] 数据库目录权限正确
- [ ] SSL证书已配置（可选）

## 🎯 访问应用

部署成功后，您可以通过以下方式访问：

- **HTTP**: http://your-server-ip
- **直接访问**: http://your-server-ip:3000
- **域名**: http://your-domain.com（如果配置了域名）
- **HTTPS**: https://your-domain.com（如果配置了SSL）

## 📞 技术支持

如遇到问题，请检查：
1. 服务器系统要求：Ubuntu 18.04+ 
2. 最低配置：1GB RAM, 1 CPU Core
3. 推荐配置：2GB RAM, 2 CPU Cores
4. 确保服务器可以访问外网（AI API调用需要） 