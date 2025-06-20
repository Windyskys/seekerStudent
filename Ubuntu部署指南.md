# SeekerAI智能学习平台 - Ubuntu服务器部署指南

## 快速部署

### 1. 准备工作

确保你的Ubuntu服务器满足以下要求：
- Ubuntu 18.04 或更高版本
- 至少 1GB RAM
- 至少 2GB 可用磁盘空间
- 具有sudo权限的用户账户

### 2. 一键部署

在项目目录中运行以下命令：

```bash
# 给脚本执行权限
chmod +x redeploy-ubuntu.sh manage-ubuntu.sh

# 执行部署（需要root权限）
sudo ./redeploy-ubuntu.sh
```

部署脚本会自动完成以下操作：
- ✅ 安装Node.js、npm、nginx等依赖
- ✅ 创建项目目录和用户权限
- ✅ 部署代码文件
- ✅ 安装Node.js依赖包
- ✅ 配置环境变量和API密钥
- ✅ 创建systemd服务
- ✅ 配置Nginx反向代理
- ✅ 启动所有服务
- ✅ 执行健康检查

### 3. 验证部署

部署完成后，访问以下地址验证服务：

```bash
# 获取服务器IP地址
hostname -I

# 访问以下地址（将IP替换为实际地址）：
# http://YOUR_SERVER_IP                              - 主页
# http://YOUR_SERVER_IP/comprehensive-assessment.html - 综合评估
# http://YOUR_SERVER_IP/dashboard.html               - 数据看板
# http://YOUR_SERVER_IP/health                       - API健康检查
```

## 服务管理

### 使用管理脚本

```bash
# 基本操作
./manage-ubuntu.sh start     # 启动服务
./manage-ubuntu.sh stop      # 停止服务
./manage-ubuntu.sh restart   # 重启服务
./manage-ubuntu.sh status    # 查看状态

# 监控和调试
./manage-ubuntu.sh logs      # 查看日志
./manage-ubuntu.sh health    # 健康检查
./manage-ubuntu.sh monitor   # 实时监控

# 数据管理
sudo ./manage-ubuntu.sh backup   # 备份数据库
sudo ./manage-ubuntu.sh restore  # 恢复数据库

# 代码更新
sudo ./manage-ubuntu.sh update   # 更新代码并重启
```

### 使用systemctl命令

```bash
# 服务控制
sudo systemctl start seeker-ai     # 启动服务
sudo systemctl stop seeker-ai      # 停止服务
sudo systemctl restart seeker-ai   # 重启服务
sudo systemctl status seeker-ai    # 查看状态

# 开机自启
sudo systemctl enable seeker-ai    # 启用开机自启
sudo systemctl disable seeker-ai   # 禁用开机自启

# 查看日志
sudo journalctl -u seeker-ai -f    # 实时日志
sudo journalctl -u seeker-ai -n 50 # 最近50行日志
```

## 目录结构

```
/var/www/seekerStudent/          # 项目根目录
├── server.js                    # Node.js服务器
├── package.json                 # 项目配置
├── .env                         # 环境变量
├── database/                    # 数据库目录
│   └── seeker_ai.db            # SQLite数据库
├── backup/                      # 备份目录
├── css/                         # 样式文件
├── img/                         # 图片资源
├── *.html                       # 前端页面
└── logs/                        # 日志目录
```

## 配置文件位置

- **服务配置**: `/etc/systemd/system/seeker-ai.service`
- **Nginx配置**: `/etc/nginx/sites-available/seekerStudent`
- **环境变量**: `/var/www/seekerStudent/.env`
- **项目目录**: `/var/www/seekerStudent/`

## 故障排除

### 常见问题

1. **服务无法启动**
   ```bash
   # 检查服务状态
   sudo systemctl status seeker-ai
   
   # 查看详细日志
   sudo journalctl -u seeker-ai -n 50
   
   # 检查端口占用
   sudo lsof -i :3000
   ```

2. **无法访问网站**
   ```bash
   # 检查Nginx状态
   sudo systemctl status nginx
   
   # 测试Nginx配置
   sudo nginx -t
   
   # 检查防火墙
   sudo ufw status
   ```

3. **API调用失败**
   ```bash
   # 测试API健康
   curl http://localhost:3000/health
   
   # 检查API密钥配置
   cat /var/www/seekerStudent/.env
   
   # 查看API错误日志
   sudo journalctl -u seeker-ai | grep "API"
   ```

### 手动修复步骤

1. **重置服务**
   ```bash
   sudo systemctl stop seeker-ai
   sudo systemctl start seeker-ai
   sudo systemctl status seeker-ai
   ```

2. **重新配置Nginx**
   ```bash
   sudo nginx -t
   sudo systemctl reload nginx
   ```

3. **检查文件权限**
   ```bash
   sudo chown -R www-data:www-data /var/www/seekerStudent
   sudo chmod -R 755 /var/www/seekerStudent
   ```

## 更新部署

### 方式一：使用管理脚本（推荐）

```bash
# 在项目源码目录中执行
sudo ./manage-ubuntu.sh update
```

### 方式二：手动更新

```bash
# 1. 停止服务
sudo systemctl stop seeker-ai

# 2. 备份数据库
sudo cp /var/www/seekerStudent/database/seeker_ai.db /tmp/seeker_ai.db.backup

# 3. 更新代码
sudo rsync -av --exclude=node_modules --exclude=database ./ /var/www/seekerStudent/

# 4. 更新依赖
cd /var/www/seekerStudent
sudo -u www-data npm install --production

# 5. 恢复数据库
sudo cp /tmp/seeker_ai.db.backup /var/www/seekerStudent/database/seeker_ai.db
sudo chown www-data:www-data /var/www/seekerStudent/database/seeker_ai.db

# 6. 启动服务
sudo systemctl start seeker-ai
```

## 性能优化

### 资源监控

```bash
# CPU和内存使用
top
htop

# 磁盘使用
df -h

# 网络连接
netstat -tlnp | grep :3000

# 实时监控
./manage-ubuntu.sh monitor
```

### 日志管理

```bash
# 清理旧日志（保留最近7天）
sudo journalctl --vacuum-time=7d

# 限制日志大小
sudo journalctl --vacuum-size=100M
```

## 安全建议

1. **防火墙配置**
   ```bash
   sudo ufw enable
   sudo ufw allow 22/tcp      # SSH
   sudo ufw allow 80/tcp      # HTTP
   sudo ufw allow 443/tcp     # HTTPS（如果使用SSL）
   ```

2. **定期备份**
   ```bash
   # 设置定时备份（每天凌晨2点）
   echo "0 2 * * * root /var/www/seekerStudent/manage-ubuntu.sh backup" | sudo tee -a /etc/crontab
   ```

3. **更新系统**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

## 支持

如遇到问题，请检查：
1. 服务运行状态：`./manage-ubuntu.sh status`
2. 系统日志：`./manage-ubuntu.sh logs`
3. 健康检查：`./manage-ubuntu.sh health`

完整的错误信息有助于快速定位和解决问题。 