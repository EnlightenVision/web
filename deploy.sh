#!/bin/bash

# ========== 配置 ==========
PAGE_URL="https://enlightenvision.net"
KEYWORD="EnlightenVision"
CHAT_ID="413142477"
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"
OPEN_BROWSER=true
SEND_SCREENSHOT=true

# ========== 路径 ==========
DEPLOY_DIR="/Users/zshe/evo"
LOG_DIR="$DEPLOY_DIR/deploy_logs"
mkdir -p "$LOG_DIR"

DATE_TAG=$(date "+%Y%m%d_%H%M%S")
LOG_FILE="deploy_log_${DATE_TAG}.txt"

# ========== 检查 Git ==========
cd "$DEPLOY_DIR" || exit 1
echo "检查 Git 状态..."
if git diff --quiet && git diff --cached --quiet; then
  echo "[略过] 没有文件变更，停止部署。"
  echo "[$DATE_TAG] No changes detected. Skipped." >> "$DEPLOY_DIR/deploy_history.log"
  exit 0
fi

# ========== Hexo ==========
echo "开始 Hexo 构建..."
hexo clean && hexo g
BUILD_SUCCESS=$?
if [ $BUILD_SUCCESS -ne 0 ]; then
  echo "❌ 构建失败，退出。" | tee "$LOG_DIR/$LOG_FILE"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="❌ Hexo 构建失败，请检查日志。"
  exit 1
fi

# ========== Git 提交 ==========
git add .
git commit -m "Auto deploy at $DATE_TAG"
git push origin main

# ========== 延迟检测 ==========
START_TIME=$(date +%s%3N)
HTML=$(curl -s -m 10 "$PAGE_URL")
END_TIME=$(date +%s%3N)
DELAY_MS=$((END_TIME - START_TIME))

if [[ "$HTML" == *"$KEYWORD"* ]]; then
  STATUS="✅ 部署成功"
else
  STATUS="❌ 部署失败：找不到关键词"
fi

# ========== 自动打开 ==========
if $OPEN_BROWSER; then
  open -a Safari "$PAGE_URL"
fi

# ========== 日志 ==========
echo "[$DATE_TAG] $STATUS 延迟 ${DELAY_MS}ms" | tee -a "$DEPLOY_DIR/deploy_history.log" "$LOG_DIR/$LOG_FILE"

SUCCESS_COUNT=$(grep -c "✅ 部署成功" "$DEPLOY_DIR/deploy_history.log")
FAIL_COUNT=$(grep -c "❌" "$DEPLOY_DIR/deploy_history.log")
TOTAL_COUNT=$((SUCCESS_COUNT + FAIL_COUNT))
if [ "$TOTAL_COUNT" -gt 0 ]; then
  SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))
else
  SUCCESS_RATE=0
fi

HTML_REPORT="<b>${STATUS}</b><br>
关键词: <code>${KEYWORD}</code><br>
延迟: <code>${DELAY_MS} ms</code><br>
部署时间: <code>${DATE_TAG}</code><br>
成功率: <b>${SUCCESS_RATE}%</b> (${SUCCESS_COUNT}/${TOTAL_COUNT})<br>
🔗 <a href='${PAGE_URL}'>预览网站</a>"

# ========== Telegram ==========
echo "推送 Telegram 文本消息…"
TG_RESPONSE=$(curl -s -w "\n%{http_code}\n" -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  --data-urlencode "text=${HTML_REPORT}" \
  -d parse_mode="HTML")
echo "消息推送响应：$TG_RESPONSE" | tee -a "$LOG_DIR/$LOG_FILE"

if $SEND_SCREENSHOT; then
  SCREENSHOT_PATH="/tmp/page_shot_${DATE_TAG}.png"
  sleep 4
  screencapture -x -R0,0,1280,800 "$SCREENSHOT_PATH"
  echo "推送 Telegram 截图…"
  TG_PHOTO_RESPONSE=$(curl -s -w "\n%{http_code}\n" -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
    -F chat_id="$CHAT_ID" \
    -F photo="@${SCREENSHOT_PATH}" \
    -F caption="📸 页面截图 (${DATE_TAG})")
  echo "截图推送响应：$TG_PHOTO_RESPONSE" | tee -a "$LOG_DIR/$LOG_FILE"
fi

echo "部署完成 ✅" | tee -a "$LOG_DIR/$LOG_FILE"
exit 0