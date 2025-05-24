#!/bin/bash

# ========== 配置部分 ==========
PAGE_URL="https://enlightenvision.net"   # 你的 Cloudflare Pages 地址
KEYWORD="EnlightenVision"                 # 用于检测部署内容的关键词
CHAT_ID="413142477"                      # Telegram Chat ID
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"  # Telegram Bot Token
OPEN_BROWSER=true                          # 是否自动打开浏览器
SEND_SCREENSHOT=true                       # 是否发送截图

# ========== 初始化变量 ==========
DATE_TAG=$(date "+%Y%m%d_%H%M%S")
LOG_FILE="deploy_log_${DATE_TAG}.txt"
DEPLOY_DIR="$(pwd)"

# ========== 检查是否有改动 ==========
echo "检查 Git 状态..."
if git diff --quiet && git diff --cached --quiet; then
  echo "[略过] 没有文件变更，停止部署。"
  echo "[$DATE_TAG] No changes detected. Skipped." >> deploy_history.log
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
    -d text="❌ Hexo 构建失败，请检查日志。"
  exit 1
fi

# ========== Git 提交与推送 ==========
git add .
git commit -m "Auto deploy at $DATE_TAG"
git push origin main

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
  echo "自动打开浏览器预览页面..."
  open -a Safari "$PAGE_URL"
fi

# ========== 保存并统计日志 ==========
echo "[$DATE_TAG] $STATUS 延迟 ${DELAY_MS}ms" >> deploy_history.log
SUCCESS_COUNT=$(grep -c "✅ 部署成功" deploy_history.log)
FAIL_COUNT=$(grep -c "❌" deploy_history.log)
TOTAL_COUNT=$((SUCCESS_COUNT + FAIL_COUNT))
SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))

# ========== 生成 HTML 报告 ==========
HTML_REPORT="<b>${STATUS}</b><br>
关键词: <code>${KEYWORD}</code><br>
延迟: <code>${DELAY_MS} ms</code><br>
部署时间: <code>${DATE_TAG}</code><br>
成功率: <b>${SUCCESS_RATE}%</b> (${SUCCESS_COUNT}/${TOTAL_COUNT})<br>
🔗 <a href='${PAGE_URL}'>预览网站</a>"

# ========== 发送 Telegram 消息 ==========
# 文本
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="${STATUS}：${DELAY_MS}ms" \
  -d parse_mode="HTML"

# HTML 报告
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="$HTML_REPORT" \
  -d parse_mode="HTML"

# 截图（可选）
if $SEND_SCREENSHOT; then
  SCREENSHOT_PATH="/tmp/page_shot.png"
  echo "截图页面..."
  screencapture -x -R0,0,1280,720 "$SCREENSHOT_PATH"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
    -F chat_id="$CHAT_ID" \
    -F photo="@${SCREENSHOT_PATH}" \
    -F caption="📸 页面截图"
fi

echo "部署完成 ✅"
exit 0