#!/bin/bash

######################################
# Hexo 一键自动部署脚本 (hexopush)
# 支持全局调用！任何终端直接输入 hexopush 即可
######################################

# ========== 路径配置 ==========
PROJECT_DIR="/Users/zshe/evo"                      # Hexo 项目目录
LOG_DIR="$PROJECT_DIR/deploy_logs"                 # 日志目录
PAGE_URL="https://enlightenvision.net"             # Cloudflare Pages 网站
KEYWORD="EnlightenVision"                          # 部署检查关键词
CHAT_ID="413142477"                                # Telegram Chat ID
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"   # Telegram Token
OPEN_BROWSER=true                                  # 自动打开浏览器
SEND_SCREENSHOT=true                               # 自动截图并推送

# ========== 进入 Hexo 目录 ==========
cd "$PROJECT_DIR" || { echo "❌ Hexo项目路径不存在：$PROJECT_DIR"; exit 1; }

# ========== 日志准备 ==========
mkdir -p "$LOG_DIR"
DATE_TAG=$(date "+%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/deploy_log_${DATE_TAG}.txt"

# ========== 检查 Git 改动 ==========
echo "检查 Git 状态..."
if git diff --quiet && git diff --cached --quiet; then
  echo "[略过] 没有文件变更，停止部署。"
  echo "[$DATE_TAG] No changes detected. Skipped." >> "$LOG_DIR/deploy_history.log"
  exit 0
fi

# 记录更变摘要
GIT_DIFF=$(git status --short)

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
echo "提交和推送变更到GitHub..."
git add .
git commit -m "Auto deploy at $DATE_TAG"
git push origin main

# ========== 网站检测 ==========
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

# ========== 自动打开网站 ==========
if $OPEN_BROWSER; then
  echo "自动打开浏览器预览页面..."
  open -a Safari "$PAGE_URL"
  sleep 3
fi

# ========== 保存和统计日志 ==========
echo "[$DATE_TAG] $STATUS 延迟 ${DELAY_MS}ms" >> "$LOG_DIR/deploy_history.log"
echo "[$DATE_TAG] ---- GIT CHANGES BEGIN ----" >> "$LOG_FILE"
echo "$GIT_DIFF" >> "$LOG_FILE"
echo "[$DATE_TAG] ---- GIT CHANGES END ----" >> "$LOG_FILE"
echo "[$DATE_TAG] $STATUS 延迟 ${DELAY_MS}ms" >> "$LOG_FILE"
SUCCESS_COUNT=$(grep -c "✅ 部署成功" "$LOG_DIR/deploy_history.log")
FAIL_COUNT=$(grep -c "❌" "$LOG_DIR/deploy_history.log")
TOTAL_COUNT=$((SUCCESS_COUNT + FAIL_COUNT))
SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))

# ========== 生成HTML格式报告 ==========
HTML_REPORT="<b>${STATUS}</b>
关键词: <code>${KEYWORD}</code>
关键词出现: <b>${MATCH_COUNT}</b> 次
延迟: <code>${DELAY_MS} ms</code>
部署时间: <code>${DATE_TAG}</code>
成功率: <b>${SUCCESS_RATE}%%</b> (${SUCCESS_COUNT}/${TOTAL_COUNT})
🔗 <a href='${PAGE_URL}'>预览网站</a>"

# ========== Telegram 只推送一条 HTML 消息 ==========
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="$HTML_REPORT" \
  -d parse_mode="HTML"

# ========== Safari主窗口截图并推送 ==========
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