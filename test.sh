#!/bin/bash
# Hexo 本地测试自动化脚本（hexotest）

# 切换到 Hexo 项目目录
cd /Users/zshe/evo || { echo "❌ 目录不存在！"; exit 1; }

echo "🧹 清理 Hexo 旧文件..."
hexo clean

echo "🔧 生成 Hexo 静态页面..."
hexo g

echo "🚀 启动本地预览服务..."
# 检查是否已有 hexo s 进程
if pgrep -f "hexo s" >/dev/null; then
  echo "⚠️ 已有 hexo s 进程，无需重复启动。"
else
  nohup hexo s > /dev/null 2>&1 &
  sleep 2
fi

echo "🌐 打开本地预览页面：http://localhost:4000/"
open -a Safari "http://localhost:4000/"

echo "✅ Hexo 本地预览已启动，可在浏览器查看效果。"

