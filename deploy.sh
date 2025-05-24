#!/bin/bash

# === 配置区 ===
REPO_PATH="/Users/zshe/evo"
PAGE_URL="https://evoptometry.pages.dev"  # 你的 Cloudflare Pages 地址
KEYWORD="EnlightenVision"
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"
CHAT_ID="7098729602"
LOG_DIR="$REPO_PATH/deploy_logs"
NOW=$(date "+%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/deploy_log_$NOW.txt"
SCREENSHOT="$LOG_DIR/screenshot_$NOW.png"

mkdir -p "$LOG_DIR"

# === 部署步骤 ===
echo "[部署开始] $(date)" | tee -a "$LOG_FILE"
cd "$REPO_PATH" || exit

hexo clean && hexo g 2>&1 | tee -a "$LOG_FILE"

# Git 推送
{
  git add . &&
  git commit -m "Auto deploy $NOW" &&
  git push origin main
} >> "$LOG_FILE" 2>&1

# 等待 Cloudflare Pages 构建完成的时间（可视需求增减）
sleep 10

# 打开预览页面
open "$PAGE_URL"

# 截图
screencapture -T 3 -x "$SCREENSHOT"

# 检测页面关键词 & 延迟
STATUS="失败"
if curl -s --max-time 10 "$PAGE_URL" | grep -q "$KEYWORD"; then
  STATUS="成功"
fi

LATENCY=$(curl -o /dev/null -s -w "%{time_total}" "$PAGE_URL")

# 第一条消息：简报
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="✅ 部署状态：$STATUS\n🌐 延迟：${LATENCY}s\n🔗 $PAGE_URL" \
  -d parse_mode="HTML"

# 第二条消息：HTML 报告
curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendPhoto" \
  -F chat_id="$CHAT_ID" \
  -F caption="<b>部署报告</b>\n状态：<b>$STATUS</b>\n延迟：<code>${LATENCY}s</code>\n关键词：<code>$KEYWORD</code>\n时间：<code>$(date)</code>\n链接：<a href=\"$PAGE_URL\">点击查看</a>" \
  -F photo="@${SCREENSHOT}" \
  -F parse_mode="HTML"

# 日志统计脚本（生成成功率）
SUCCESS_COUNT=$(grep -l "部署状态：成功" $LOG_DIR/deploy_log_*.txt | wc -l)
TOTAL_COUNT=$(ls $LOG_DIR/deploy_log_*.txt | wc -l)
RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))

# 输出统计信息
echo "[统计] 总部署次数: $TOTAL_COUNT, 成功: $SUCCESS_COUNT, 成功率: $RATE%" | tee -a "$LOG_FILE"
