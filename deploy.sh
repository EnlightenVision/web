#!/bin/bash

# ===================== 配置部分 =====================
PAGE_URL="https://enlightenvision.net"                 # Cloudflare Pages 实际网址
KEYWORD="EnlightenVision"                             # 部署页面应包含的关键词
CHAT_ID="413142477"                                  # Telegram Chat ID
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"  # Telegram 机器人 Token
OPEN_BROWSER=true                                      # 是否自动打开 Safari 预览
SEND_SCREENSHOT=true                                   # 是否发送页面截图
MAX_RETRY=3                                            # 构建失败最大重试次数

# ===================== 初始化变量 =====================
DATE_TAG=$(date "+%Y%m%d_%H%M%S")
DEPLOY_DIR="/Users/zshe/evo"                            # 项目路径（固定为你当前路径）
LOG_FILE="$DEPLOY_DIR/deploy_log_${DATE_TAG}.txt"
HISTORY_LOG="$DEPLOY_DIR/deploy_history.log"

cd "$DEPLOY_DIR" || exit 1

# ===================== 检查是否有 Git 改动 =====================
echo "检查 Git 状态..."
git diff --quiet && git diff --cached --quiet
if [ $? -eq 0 ]; then
  echo "[$DATE_TAG] 无文件变动，停止部署。" | tee -a "$HISTORY_LOG"
  exit 0
fi

# ===================== Hexo 构建（自动重试） =====================
RETRY=0
while [ $RETRY -lt $MAX_RETRY ]; do
  echo "Hexo 构建中... 第 $((RETRY+1)) 次尝试"
  hexo clean && hexo g && break
  RETRY=$((RETRY+1))
  echo "构建失败，重试中 ($RETRY/$MAX_RETRY)..."
  sleep 2

done

if [ $RETRY -eq $MAX_RETRY ]; then
  echo "❌ 构建失败，已达到最大重试次数。" | tee "$LOG_FILE"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="❌ Hexo 构建失败，最大重试已达，请手动检查。"
  exit 1
fi

# ===================== Git 提交与推送 =====================
CHANGES=$(git status --short)
git add .
git commit -m "Auto deploy at $DATE_TAG"
git push origin main

# ===================== 测试部署地址延迟与内容 =====================
START_TIME=$(date +%s%3N)
HTML=$(curl -s -m 20 "$PAGE_URL")
END_TIME=$(date +%s%3N)
DELAY_MS=$((END_TIME - START_TIME))

if [[ "$HTML" == *"$KEYWORD"* ]]; then
  STATUS="✅ 部署成功"
  COLOR="green"
else
  STATUS="❌ 部署失败：关键词未发现"
  COLOR="red"
fi

# ===================== 自动打开浏览器 =====================
if $OPEN_BROWSER; then
  echo "打开 Safari 预览..."
  open -a Safari "$PAGE_URL"
fi

# ===================== 保存历史日志 =====================
echo "[$DATE_TAG] $STATUS 延迟 ${DELAY_MS}ms" | tee "$LOG_FILE" >> "$HISTORY_LOG"
SUCCESS_COUNT=$(grep -c "✅ 部署成功" "$HISTORY_LOG")
FAIL_COUNT=$(grep -c "❌" "$HISTORY_LOG")
TOTAL_COUNT=$((SUCCESS_COUNT + FAIL_COUNT))
if [ $TOTAL_COUNT -gt 0 ]; then
  SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))
else
  SUCCESS_RATE=0
fi

# ===================== 生成部署报告 HTML =====================
HTML_REPORT="<b>${STATUS}</b><br>
关键词: <code>${KEYWORD}</code><br>
延迟: <code>${DELAY_MS} ms</code><br>
部署时间: <code>${DATE_TAG}</code><br>
成功率: <b>${SUCCESS_RATE}%</b> (${SUCCESS_COUNT}/${TOTAL_COUNT})<br>
🔗 <a href='${PAGE_URL}'>点我预览</a><br>
📄 <pre>${CHANGES}</pre>"

# ===================== 推送 Telegram 报告 =====================
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="${CHAT_ID}" \
  -d text="$HTML_REPORT" \
  -d parse_mode="HTML"

# ===================== 页面截图（完整） =====================
if $SEND_SCREENSHOT; then
  echo "准备截图..."
  sleep 3
  SCREENSHOT_PATH="/tmp/page_shot_${DATE_TAG}.png"
  screencapture -x -R0,0,1280,800 "$SCREENSHOT_PATH"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
    -F chat_id="${CHAT_ID}" \
    -F photo="@${SCREENSHOT_PATH}" \
    -F caption="📸 页面截图"
fi

# ===================== 生成成功率图表（可选） =====================
python3 <<EOF
import matplotlib.pyplot as plt
import re
from datetime import datetime

lines = open("$HISTORY_LOG").readlines()
dates, statuses, delays = [], [], []
for line in lines:
    m = re.match(r"\\[(.*?)\\] (.*?) 延迟 (\\d+)ms", line)
    if m:
        dt = datetime.strptime(m[1], "%Y%m%d_%H%M%S")
        dates.append(dt)
        statuses.append("成功" if "✅" in m[2] else "失败")
        delays.append(int(m[3]))

plt.figure(figsize=(10, 4))
colors = ["green" if s == "成功" else "red" for s in statuses]
plt.bar(dates, delays, color=colors)
plt.xticks(rotation=45)
plt.title("部署延迟趋势图")
plt.ylabel("延迟 (ms)")
plt.tight_layout()
chart_path = "$DEPLOY_DIR/deploy_chart_${DATE_TAG}.png"
plt.savefig(chart_path)

# 推送图表到 Telegram
import requests
requests.post(
    f"https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto",
    data={"chat_id": "$CHAT_ID"},
    files={"photo": open(chart_path, "rb")}
)
EOF

# ===================== 结束 =====================
echo "部署完成 ✅"
exit 0