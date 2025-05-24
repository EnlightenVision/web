#!/bin/bash

######################################
# 自动部署脚本（Hexo + GitHub + Cloudflare Pages + Telegram推送 + 截图）
# 功能：
#   1. 自动检测变更、构建Hexo、提交推送GitHub
#   2. 检查部署网站延迟与关键词，统计成功率
#   3. 自动打开浏览器、对Safari主窗口截图
#   4. 通过Telegram推送状态与页面截图
#   5. 日志自动保存
# macOS适用
######################################

# ========= 配置区域 =========
PAGE_URL="https://enlightenvision.net"   # 你的 Cloudflare Pages 网站主页
KEYWORD="EnlightenVision"                # 用于检测部署内容的关键词
CHAT_ID="413142477"                      # Telegram个人或群组 Chat ID
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"  # Telegram Bot Token
OPEN_BROWSER=true                        # 是否自动打开 Safari 浏览器访问主页
SEND_SCREENSHOT=true                     # 是否自动截图并推送

# ========= 变量初始化 =========
DATE_TAG=$(date "+%Y%m%d_%H%M%S")        # 当前时间戳，用于标识部署
LOG_FILE="deploy_log_${DATE_TAG}.txt"    # 本次详细日志文件名
DEPLOY_DIR="$(pwd)"                      # 当前目录（一般为 Hexo 项目根目录）

# ========= 检查是否有Git改动 =========
echo "检查 Git 状态..."
if git diff --quiet && git diff --cached --quiet; then
  echo "[略过] 没有文件变更，停止部署。"
  echo "[$DATE_TAG] No changes detected. Skipped." >> deploy_history.log
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
# 用python3兼容所有macOS取毫秒时间戳
START_TIME=$(python3 -c 'import time; print(int(time.time()*1000))')
HTML=$(curl -s -m 10 "$PAGE_URL")
END_TIME=$(python3 -c 'import time; print(int(time.time()*1000))')
DELAY_MS=$((END_TIME - START_TIME))
MATCH_COUNT=$(echo "$HTML" | grep -o "$KEYWORD" | wc -l)

# 判断部署状态
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
  sleep 3  # 等待动画结束
fi

# ========= 保存和统计日志 =========
echo "[$DATE_TAG] $STATUS 延迟 ${DELAY_MS}ms" >> deploy_history.log
SUCCESS_COUNT=$(grep -c "✅ 部署成功" deploy_history.log)
FAIL_COUNT=$(grep -c "❌" deploy_history.log)
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

# ========= 只推送一条 Telegram HTML 消息 =========
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="$HTML_REPORT" \
  -d parse_mode="HTML"

# ========= Safari主窗口截图并推送 =========
if $SEND_SCREENSHOT; then
  SCREENSHOT_PATH="/tmp/page_shot_${DATE_TAG}.png"
  # 获取 Safari 当前主窗口的ID，仅截该窗口内容
  WINDOW_ID=$(osascript -e 'tell app "Safari" to id of window 1')
  screencapture -x -l $WINDOW_ID "$SCREENSHOT_PATH"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
    -F chat_id="$CHAT_ID" \
    -F photo="@${SCREENSHOT_PATH}" \
    -F caption="📸 页面截图"
fi

echo "部署完成 ✅"
exit 0