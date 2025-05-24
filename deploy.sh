#!/bin/bash

# ========== 配置 ==========
PAGE_URL="https://enlightenvision.net"
KEYWORD="EnlightenVision"
CHAT_ID="413142477"
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"
DEPLOY_DIR="/Users/zshe/evo"
OPEN_BROWSER=true
SEND_SCREENSHOT=true

# ========== 初始化 ==========
cd "$DEPLOY_DIR"
DATE_TAG=$(date "+%Y%m%d_%H%M%S")
LOG_DIR="${DEPLOY_DIR}/deploy_logs"
LOG_FILE="${LOG_DIR}/deploy_log_${DATE_TAG}.txt"
SCREENSHOT_FILE="${LOG_DIR}/screenshot_${DATE_TAG}.png"
mkdir -p "$LOG_DIR"

echo "[部署开始] $(date)" | tee "$LOG_FILE"

# ========== 检查更改 ==========
if git diff --quiet && git diff --cached --quiet; then
  echo "[略过] 没有变更。" | tee -a "$LOG_FILE"
  echo "[$DATE_TAG] No changes detected. Skipped." >> "${LOG_DIR}/deploy_history.log"
  exit 0
fi

# ========== Hexo 构建 ==========
hexo clean && hexo g >> "$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
  MSG="❌ Hexo 构建失败"
  echo "$MSG" | tee -a "$LOG_FILE"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" -d text="$MSG"
  exit 1
fi

# ========== Git 提交并记录更动 ==========
CHANGES=$(git status --short)
git add . && git commit -m "Auto deploy ${DATE_TAG}" && git push origin main >> "$LOG_FILE" 2>&1

# ========== 延迟测试 ==========
START_TIME=$(date +%s%3N)
HTML=$(curl -s -m 10 "$PAGE_URL")
END_TIME=$(date +%s%3N)
DELAY_MS=$((END_TIME - START_TIME))

# ========== 状态判定 ==========
if [[ "$HTML" == *"$KEYWORD"* ]]; then
  STATUS="✅ 部署成功"
else
  STATUS="❌ 失败：关键词缺失"
fi

# ========== 截图 Safari ==========
if $SEND_SCREENSHOT; then
  echo "截图页面..." >> "$LOG_FILE"
  osascript <<EOF
tell application "Safari"
    open location "$PAGE_URL"
    delay 3
    activate
end tell
delay 2
do shell script "screencapture -l$(osascript -e 'tell app \"Safari\" to id of front window') \"$SCREENSHOT_FILE\""
EOF
fi

# ========== 打开浏览器 ==========
$OPEN_BROWSER && open -a Safari "$PAGE_URL"

# ========== 写入日志 ==========
echo "[$DATE_TAG] $STATUS 延迟 ${DELAY_MS}ms" >> "${LOG_DIR}/deploy_history.log"

# ========== 统计成功率 ==========
SUCCESS=$(grep -c "✅ 部署成功" "${LOG_DIR}/deploy_history.log")
FAIL=$(grep -c "❌" "${LOG_DIR}/deploy_history.log")
TOTAL=$((SUCCESS + FAIL))
SUCCESS_RATE=$((SUCCESS * 100 / TOTAL))

# ========== 生成图表 ==========
CHART_PATH="${LOG_DIR}/chart_${DATE_TAG}.png"
gnuplot <<EOF
set terminal png size 600,300
set output "${CHART_PATH}"
set title "部署成功率"
set style data histograms
set style fill solid
plot "-" using 2:xtic(1) title "次数"
成功 $SUCCESS
失败 $FAIL
EOF

# ========== HTML 报告 ==========
HTML_REPORT="<b>${STATUS}</b><br>
关键词: <code>${KEYWORD}</code><br>
延迟: <code>${DELAY_MS} ms</code><br>
部署时间: <code>${DATE_TAG}</code><br>
成功率: <b>${SUCCESS_RATE}%</b> (${SUCCESS}/${TOTAL})<br>
更改摘要:<pre>${CHANGES}</pre>
🔗 <a href='${PAGE_URL}'>预览网站</a>"

# ========== 推送 Telegram ==========
# 报告
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d parse_mode="HTML" \
  --data-urlencode "text=${HTML_REPORT}"

# 截图
if $SEND_SCREENSHOT && [ -f "$SCREENSHOT_FILE" ]; then
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
    -F chat_id="${CHAT_ID}" \
    -F photo=@"${SCREENSHOT_FILE}" \
    -F caption="📸 页面截图"
fi

# 成功率图表
if [ -f "$CHART_PATH" ]; then
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
    -F chat_id="${CHAT_ID}" \
    -F photo=@"${CHART_PATH}" \
    -F caption="📊 部署统计图"
fi

echo "部署完成 ✅"
exit 0