#!/bin/bash

# ========== 配置部分 ==========
PAGE_URL="https://enlightenvision.net"             # Cloudflare Pages 地址
KEYWORD="EnlightenVision"                          # 页面关键词
CHAT_ID="413142477"                                # Telegram Chat ID
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"  # Telegram Token
OPEN_BROWSER=true                                  # 是否自动打开浏览器
SEND_SCREENSHOT=true                               # 是否发送截图

# ========== 初始化变量 ==========
DATE_TAG=$(date "+%Y%m%d_%H%M%S")
LOG_FILE="deploy_log_${DATE_TAG}.txt"
DEPLOY_HISTORY="./deploy_history.log"
DEPLOY_DIR="$(pwd)"

# ========== 检查是否有改动 ==========
echo "检查 Git 状态..."
if git diff --quiet && git diff --cached --quiet; then
  echo "[略过] 没有文件变更，停止部署。"
  echo "[$DATE_TAG] No changes detected. Skipped." >> "$DEPLOY_HISTORY"
  exit 0
fi

# 记录本次变更内容摘要（只显示一屏，太多只显示前20行）
GIT_DIFF_SUMMARY=$(git diff --stat)
GIT_DIFF_DETAIL=$(git diff | head -20)
GIT_LAST_COMMIT=$(git log -1 --pretty=format:"%h %s (%an)")

# ========== Hexo 构建 ==========
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

# ========== Git 提交与推送 ==========
git add .
git commit -m "Auto deploy at $DATE_TAG"
git push origin main

# ========== 部署延迟和页面检查 ==========
START_TIME=$(date +%s%3N)
HTML=$(curl -s -m 10 "$PAGE_URL")
END_TIME=$(date +%s%3N)
DELAY_MS=$((END_TIME - START_TIME))
MATCH_COUNT=$(echo "$HTML" | grep -o "$KEYWORD" | wc -l)

if [[ "$HTML" == *"$KEYWORD"* ]]; then
  STATUS="✅ 部署成功"
else
  STATUS="❌ 部署失败：找不到关键词"
fi

# ========== 自动打开浏览器 ==========
if $OPEN_BROWSER; then
  echo "自动打开浏览器预览页面..."
  open -a Safari "$PAGE_URL"
  sleep 4  # 页面动画结束
fi

# ========== 保存日志 ==========
{
  echo "[$DATE_TAG] $STATUS 延迟 ${DELAY_MS}ms"
  echo "上次提交: $GIT_LAST_COMMIT"
  echo "更变摘要:"
  echo "$GIT_DIFF_SUMMARY"
  echo ""
} >> "$DEPLOY_HISTORY"

SUCCESS_COUNT=$(grep -c "✅ 部署成功" "$DEPLOY_HISTORY")
FAIL_COUNT=$(grep -c "❌" "$DEPLOY_HISTORY")
TOTAL_COUNT=$((SUCCESS_COUNT + FAIL_COUNT))
SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))

# ========== 构建 Telegram 报告 ==========
HTML_REPORT="<b>${STATUS}</b>%0A关键词: <code>${KEYWORD}</code>%0A关键词出现: <b>${MATCH_COUNT}</b> 次%0A延迟: <code>${DELAY_MS} ms</code>%0A部署时间: <code>${DATE_TAG}</code>%0A成功率: <b>${SUCCESS_RATE}%%</b> (${SUCCESS_COUNT}/${TOTAL_COUNT})%0A🔗 <a href='${PAGE_URL}'>预览网站</a>%0A
<b>更变摘要:</b>%0A<code>${GIT_DIFF_SUMMARY}</code>%0A
<b>最近提交:</b>%0A<code>${GIT_LAST_COMMIT}</code>"

# ========== Telegram 推送 ==========
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="$HTML_REPORT" \
  -d parse_mode="HTML"

# ========== 页面截图 ==========
if $SEND_SCREENSHOT; then
  SCREENSHOT_PATH="/tmp/page_shot_${DATE_TAG}.png"
  echo "截图页面..."
  screencapture -x -R0,0,1280,800 "$SCREENSHOT_PATH"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
    -F chat_id="$CHAT_ID" \
    -F photo="@${SCREENSHOT_PATH}" \
    -F caption="📸 页面截图"
fi

echo "部署完成 ✅"
exit 0