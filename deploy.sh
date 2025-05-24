#!/bin/bash

# ========== 配置部分 ==========
PAGE_URL="https://enlightenvision.net"
KEYWORD="EnlightenVision"
CHAT_ID="413142477"
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"
OPEN_BROWSER=true
SEND_SCREENSHOT=true

# ========== 初始化变量 ==========
DATE_TAG=$(date "+%Y%m%d_%H%M%S")
DEPLOY_DIR="/Users/zshe/evo"
LOG_DIR="$DEPLOY_DIR/deploy_logs"
LOG_FILE="$LOG_DIR/deploy_log_${DATE_TAG}.txt"
mkdir -p "$LOG_DIR"

cd "$DEPLOY_DIR" || exit 1

# ========== 检查是否有改动 ==========
echo "检查 Git 状态..."
if git diff --quiet && git diff --cached --quiet; then
  echo "[略过] 没有文件变更，停止部署。"
  echo "[$DATE_TAG] No changes detected. Skipped." >> "$LOG_DIR/deploy_history.log"
  exit 0
fi

# ========== Hexo 构建 ==========
echo "开始 Hexo 构建..."
hexo clean && hexo g
BUILD_SUCCESS=$?

if [ $BUILD_SUCCESS -ne 0 ]; then
  echo "❌ 构建失败，退出。" | tee "$LOG_FILE"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d parse_mode="HTML" \
    --data-urlencode "text=❌ Hexo 构建失败，请检查日志"
  exit 1
fi

# ========== Git 提交与推送 ==========
CHANGES=$(git status --short)
git add .
git commit -m "Auto deploy at $DATE_TAG" --allow-empty
GIT_PUSH_RESULT=$(git push origin main 2>&1)

# ========== 测试部署地址延迟与内容 ==========
START_TIME=$(date +%s%3N)
HTML=$(curl -s -m 10 "$PAGE_URL")
END_TIME=$(date +%s%3N)
DELAY_MS=$((END_TIME - START_TIME))

if [[ "$HTML" == *"$KEYWORD"* ]]; then
  STATUS="✅ 部署成功"
  COLOR="green"
  echo "部署成功，延迟 ${DELAY_MS}ms"
else
  STATUS="❌ 部署失败：找不到关键词"
  COLOR="red"
  echo "部署失败，找不到关键词"
fi

# ========== 自动打开页面 ==========
if $OPEN_BROWSER; then
  open -a Safari "$PAGE_URL"
fi

# ========== 保存并统计日志 ==========
echo "[$DATE_TAG] $STATUS 延迟 ${DELAY_MS}ms" >> "$LOG_DIR/deploy_history.log"
SUCCESS_COUNT=$(grep -c "✅ 部署成功" "$LOG_DIR/deploy_history.log")
FAIL_COUNT=$(grep -c "❌" "$LOG_DIR/deploy_history.log")
TOTAL_COUNT=$((SUCCESS_COUNT + FAIL_COUNT))
SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))

# ========== 生成 HTML 报告 ==========
HTML_REPORT="<b>${STATUS}</b><br>关键词: <code>${KEYWORD}</code><br>延迟: <code>${DELAY_MS} ms</code><br>部署时间: <code>${DATE_TAG}</code><br>成功率: <b>${SUCCESS_RATE}%</b> (${SUCCESS_COUNT}/${TOTAL_COUNT})<br><b>更改内容:</b><pre>${CHANGES}</pre><br>🔗 <a href='${PAGE_URL}'>预览网站</a>"

# ========== 发送 Telegram HTML 报告 ==========
SEND_RESULT=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d parse_mode="HTML" \
  --data-urlencode "text=${HTML_REPORT}")

echo "$HTML_REPORT" > "$LOG_FILE"
echo "$SEND_RESULT" | grep -q '"ok":true'
if [ $? -ne 0 ]; then
  echo "⚠️ Telegram 消息发送失败，API 响应：$SEND_RESULT" | tee -a "$LOG_FILE"
fi

# ========== 页面截图（Mac Only） ==========
if $SEND_SCREENSHOT; then
  SCREENSHOT_PATH="/tmp/page_shot_${DATE_TAG}.png"
  screencapture -x -R0,0,1280,800 "$SCREENSHOT_PATH"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
    -F chat_id="$CHAT_ID" \
    -F photo="@${SCREENSHOT_PATH}" \
    -F caption="📸 页面截图"
fi

exit 0