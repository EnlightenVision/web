#!/bin/bash

############################################
#         Cloudflare + Hexo 一键部署脚本
#   1. 检查 Git 变更，无变更自动跳过
#   2. Hexo 构建、Git 提交、推送 GitHub
#   3. 检测页面延迟与关键词判断部署
#   4. 自动保存日志、生成统计图
#   5. 自动发送 Telegram 消息（含图表/截图）
#   6. 构建失败自动重试
#   7. 打开 Safari 浏览器预览
############################################

# ========== 配置区域 ==========
PAGE_URL="https://enlightenvision.net"   # 你的 Cloudflare Pages 网址
KEYWORD="EnlightenVision"                # 部署页面检测关键词
CHAT_ID="413142477"                      # Telegram Chat ID
BOT_TOKEN="8106822194:AAF-xkNrMk6iCkVuBXz3FZRJpidgu-MoqPI"  # Telegram Bot Token
OPEN_BROWSER=true                        # 是否自动打开 Safari
SEND_SCREENSHOT=true                     # 是否发送页面截图
RETRY=2                                  # 失败自动重试次数

# ========== 初始化变量 ==========
DATE_TAG=$(date "+%Y%m%d_%H%M%S")
LOG_FILE="deploy_log_${DATE_TAG}.txt"
DEPLOY_DIR="$(pwd)"
GIT_CHANGE_FILE="deploy_git_changes_${DATE_TAG}.txt"
PNG_CHART="deploy_chart_${DATE_TAG}.png"

# ========== 检查是否有变更 ==========
echo "检查 Git 状态..."
if git diff --quiet && git diff --cached --quiet; then
  echo "[略过] 没有文件变更，停止部署。"
  echo "[$DATE_TAG] No changes detected. Skipped." >> deploy_history.log
  exit 0
fi

# ========== 收集本次 Git 变更 ==========
git status > "$GIT_CHANGE_FILE"
git diff >> "$GIT_CHANGE_FILE"
git diff --cached >> "$GIT_CHANGE_FILE"

# ========== 部署流程(含失败重试) ==========
TRY=0
SUCCESS=false
while [ $TRY -le $RETRY ]; do
  TRY=$((TRY+1))
  echo "第 $TRY 次尝试 Hexo 构建..."
  hexo clean && hexo g
  BUILD_SUCCESS=$?
  if [ $BUILD_SUCCESS -eq 0 ]; then
    # 构建成功
    git add .
    git commit -m "Auto deploy at $DATE_TAG"
    git push origin main
    # 检查页面延迟与关键词
    sleep 4  # 保证 Cloudflare 端有时间同步（可调）
    START_TIME=$(date +%s%3N)
    HTML=$(curl -s -m 15 "$PAGE_URL")
    END_TIME=$(date +%s%3N)
    DELAY_MS=$((END_TIME - START_TIME))
    if [[ "$HTML" == *"$KEYWORD"* ]]; then
      STATUS="✅ 部署成功"
      SUCCESS=true
      break
    else
      STATUS="❌ 部署失败：找不到关键词"
    fi
  else
    STATUS="❌ Hexo 构建失败"
  fi
  # 构建失败自动重试
  if [ $TRY -le $RETRY ]; then
    echo "部署失败，$((10*TRY))秒后重试..."
    sleep $((10 * TRY))
  fi
done

# ========== 日志记录与统计 ==========
echo "[$DATE_TAG] $STATUS 延迟 ${DELAY_MS:-0}ms" >> deploy_history.log
SUCCESS_COUNT=$(grep -c "✅ 部署成功" deploy_history.log)
FAIL_COUNT=$(grep -c "❌" deploy_history.log)
TOTAL_COUNT=$((SUCCESS_COUNT + FAIL_COUNT))
SUCCESS_RATE=0
if [ $TOTAL_COUNT -ne 0 ]; then
  SUCCESS_RATE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))
fi

# ========== 生成本地 HTML/Markdown 简易报告 ==========
REPORT_MD="deploy_report_${DATE_TAG}.md"
REPORT_HTML="deploy_report_${DATE_TAG}.html"
echo -e "# 部署报告 ${DATE_TAG}\n\n**状态：** $STATUS\n**延迟：** ${DELAY_MS:-0}ms\n**关键词检测：** $KEYWORD\n**网址：** [$PAGE_URL]($PAGE_URL)\n**成功率：** $SUCCESS_RATE% ($SUCCESS_COUNT/$TOTAL_COUNT)\n\n## 本次变更\n\`\`\`\n$(cat $GIT_CHANGE_FILE)\n\`\`\`" > "$REPORT_MD"
pandoc "$REPORT_MD" -o "$REPORT_HTML" --from markdown --to html

# ========== 生成统计图表（延迟/成功率）==========
python3 << EOF
import matplotlib.pyplot as plt, re
log_path = "deploy_history.log"
delays = []
statuses = []
with open(log_path) as f:
    for line in f:
        m = re.search(r'(\d+)ms', line)
        if m: delays.append(int(m.group(1)))
        statuses.append("成功" if "✅" in line else "失败")
fig, ax = plt.subplots()
ax.plot(delays, marker='o', label='延迟(ms)')
ax.set_xlabel("部署次数")
ax.set_ylabel("延迟(ms)")
ax2 = ax.twinx()
ax2.plot([i for i,s in enumerate(statuses) if s=="成功"], [delays[i] for i,s in enumerate(statuses) if s=="成功"], 'g.', label='成功', alpha=0.5)
ax2.plot([i for i,s in enumerate(statuses) if s=="失败"], [delays[i] for i,s in enumerate(statuses) if s=="失败"], 'r.', label='失败', alpha=0.5)
plt.title("部署延迟 & 成功分布")
plt.savefig("$PNG_CHART")
EOF

# ========== 自动打开浏览器 ==========
if $OPEN_BROWSER; then
  open -a Safari "$PAGE_URL"
fi

# ========== Telegram HTML 报告 ==========
HTML_REPORT="<b>${STATUS}</b><br>
关键词: <code>${KEYWORD}</code><br>
延迟: <code>${DELAY_MS:-0} ms</code><br>
部署时间: <code>${DATE_TAG}</code><br>
成功率: <b>${SUCCESS_RATE}%</b> (${SUCCESS_COUNT}/${TOTAL_COUNT})<br>
🔗 <a href='${PAGE_URL}'>预览网站</a><br>
<pre>变更:\n$(tail -20 $GIT_CHANGE_FILE | sed 's/</\&lt;/g; s/>/\&gt;/g;')</pre>"

curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
  -d chat_id="$CHAT_ID" \
  -d text="$HTML_REPORT" \
  -d parse_mode="HTML"

# ========== Telegram 统计图表 ==========
curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
  -F chat_id="$CHAT_ID" \
  -F photo=@"$PNG_CHART" \
  -F caption="📈 部署延迟和成功率统计"

# ========== 页面截图（Safari 页面加载动画延迟）==========
if $SEND_SCREENSHOT; then
  SCREENSHOT_PATH="/tmp/page_shot_${DATE_TAG}.png"
  sleep 4  # 延迟，确保动画结束
  screencapture -x -R0,0,1280,900 "$SCREENSHOT_PATH"
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
    -F chat_id="$CHAT_ID" \
    -F photo="@${SCREENSHOT_PATH}" \
    -F caption="📸 页面截图 (${DATE_TAG})"
fi

echo "部署完成 ✅"
exit 0