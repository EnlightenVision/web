#!/bin/bash

######################################
# 自动部署脚本（Hexo + GitHub + Cloudflare Pages + Telegram推送 + 截图）
# 支持将部署日志保存到 /Users/zshe/evo/deploy_logs/
######################################

# ========= 配置区域 =========
PAGE_URL="https://enlightenvision.net"
KEYWORD="EnlightenVision"
CHAT_ID="413142477"
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"
OPEN_BROWSER=true
SEND_SCREENSHOT=true

# ========= 日志目录与文件名 =========
LOG_DIR="/Users/zshe/evo/deploy_logs"            # 日志保存路径
mkdir -p "$LOG_DIR"                              # 自动创建目录（如果不存在）
DATE_TAG=$(date "+%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/deploy_log_${DATE_TAG}.txt"   # 详细日志
HISTORY_LOG="$LOG_DIR/deploy_history.log"        # 汇总日志

DEPLOY_DIR="$(pwd)"

# ========= 检查是否有Git改动 =========
echo "检查 Git 状态..."
if git diff --quiet && git diff --cached --quiet; then
  echo "[略过] 没有文件变更，停止部署。"
  echo "[$DATE_TAG] No changes detected. Skipped." >> "$HISTORY_LOG"
  exit 0
fi

# ========= Hexo 构建 =========
echo "开始 Hexo 构建..."
hexo clean && hexo g
BUILD_SUCCESS=$?
if [ $BUILD_SUCCESS -ne 0 ]; then
  echo "❌ 构建失败，退出。" | tee "$LOG_FILE"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="❌ Hexo 构建失败，请检查日志。"
  exit 1
fi

# ========= Git 提交与推送 =========
echo "提交和推送变更到GitHub..."
git add .
git commit -m "Auto deploy at $DATE_TAG"
git push origin main

# ========= 网站延迟与关键词检测 =========
echo "检测页面延迟与内容..."
START_TIME=$(python3 -c 'import time; print(int(time.time()*1000))')
HTML=$(curl -s -m 10 "$PAGE_URL")
END_TIME=$(python3 -c 'import time; print(int(time.time()*1000))')
DELAY_MS=$((END_TIME - START_TIME))
MATCH_COUNT=$(echo "$HTML" | grep -o "$KEYWORD" | wc -l)

if [[ "$HTML" == *"$KEYWORD"* ]]; then
  STATUS="✅ 部署成功"
  COLOR="green"
  echo "部署成功，延迟 ${DELAY_MS}ms"
else
  STATUS="❌ 部署失败：找不到关键词"
  COLOR="red"
  echo "部署失败，找不到关键词"
fi

# ========= 自动打开网站（可选）=========
if $OPEN_BROWSER; then
  echo "自动打开浏览器预览页面..."
  open -a Safari "$PAGE_URL"
  sleep 3
fi

# ========= 记录本次更变内容到日志 =========
echo "记录本次更变内容到日志..."
CHANGE_SUMMARY=$(git diff --name-status HEAD~1 HEAD 2>/dev/null)
if [ -z "$CHANGE_SUMMARY" ]; then
  CHANGE_SUMMARY=$(git diff --name-status)
fi
CHANGE_LOG="---\n本次更变文件:\n$CHANGE_SUMMARY\n---"

# ========= 保存和统计日志 =========
{
  echo "[$DATE_TAG] $STATUS 延迟 ${DELAY_MS}ms"
  echo -e "$CHANGE_LOG"
} >> "$HISTORY_LOG"

SUCCESS_COUNT=$(grep -c "✅ 部署成功" "$HISTORY_LOG")
FAIL_COUNT=$(grep -c "❌" "$HISTORY_LOG")
TOTAL_COUNT=$((SUCCESS_COUNT + FAIL_COUNT))
SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))

# ========= 生成HTML格式报告 =========
HTML_REPORT="<b>${STATUS}</b>
关键词: <code>${KEYWORD}</code>
关键词出现: <b>${MATCH_COUNT}</b> 次
延迟: <code>${DELAY_MS} ms</code>
部署时间: <code>${DATE_TAG}</code>
成功率: <b>${SUCCESS_RATE}%%</b> (${SUCCESS_COUNT}/${TOTAL_COUNT})
🔗 <a href='${PAGE_URL}'>预览网站</a>"

# ========= Telegram只推送一条 HTML 消息 =========
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="$HTML_REPORT" \
  -d parse_mode="HTML"

# ========= Safari主窗口截图并推送 =========
if $SEND_SCREENSHOT; then
  SCREENSHOT_PATH="/tmp/page_shot_${DATE_TAG}.png"
  WINDOW_ID=$(osascript -e 'tell app "Safari" to id of window 1')
  screencapture -x -l $WINDOW_ID "$SCREENSHOT_PATH"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
    -F chat_id="$CHAT_ID" \
    -F photo="@${SCREENSHOT_PATH}" \
    -F caption="📸 页面截图"
fi

echo "部署完成 ✅"
exit 0