#!/bin/bash

# =============================
# Hexo + GitHub + Cloudflare Pages 自动部署脚本 with Telegram 通知
# MacOS 专用
# =============================

# 设置变量
PROJECT_DIR="/Users/zshe/evo"
PAGE_URL="https://enlightenvision.net"
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"
CHAT_ID="413142477"
KEYWORD="EnlightenVision"
LOG_FILE="$PROJECT_DIR/deploy_$(date '+%Y%m%d_%H%M%S').log"

echo "🚀 开始 Hexo 自动部署..."

# 切换目录
cd "$PROJECT_DIR" || exit

# 清理并生成
echo "🧹 hexo clean && g..." | tee -a "$LOG_FILE"
hexo clean && hexo g >> "$LOG_FILE" 2>&1

# Git 操作
echo "🔧 Git 提交..." | tee -a "$LOG_FILE"
git add . >> "$LOG_FILE" 2>&1
git commit -m "🚀 Auto Deploy: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE" 2>&1
git push origin main >> "$LOG_FILE" 2>&1

# 等待 Cloudflare 构建完成（延迟几秒以确保刷新）
echo "⏳ 等待 10 秒钟..." | tee -a "$LOG_FILE"
sleep 10

# 检查关键词是否出现在页面
echo "🔍 检测部署页面内容..." | tee -a "$LOG_FILE"
START_TIME=$(date +%s)
PAGE_CONTENT=$(curl -s "$PAGE_URL")
END_TIME=$(date +%s)
LATENCY=$((END_TIME - START_TIME))

if echo "$PAGE_CONTENT" | grep -q "$KEYWORD"; then
    echo "✅ 检测成功，关键词 '$KEYWORD' 出现。" | tee -a "$LOG_FILE"
    MSG="✅ *部署成功！*
关键词 *$KEYWORD* 出现在网页中。

🕒 部署时间：$(date '+%Y-%m-%d %H:%M:%S')
🌍 网址：$PAGE_URL
⚡️ 页面延迟：${LATENCY} 秒"
else
    echo "❌ 检测失败，关键词 '$KEYWORD' 未找到。" | tee -a "$LOG_FILE"
    MSG="❌ *部署失败！*
关键词 *$KEYWORD* 未检测到！

🕒 时间：$(date '+%Y-%m-%d %H:%M:%S')
🌍 页面：$PAGE_URL
⚠️ 页面延迟：${LATENCY} 秒"
fi

# Telegram 推送
echo "📤 发送 Telegram 通知..." | tee -a "$LOG_FILE"
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
     -d chat_id="${CHAT_ID}" \
     -d text="${MSG}" \
     -d parse_mode="Markdown"

echo "📄 日志文件保存到：$LOG_FILE"
