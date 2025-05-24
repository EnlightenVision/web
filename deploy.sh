#!/bin/bash

# 设置你的 Hexo 项目目录
cd /Users/zshe/evo || exit

# 记录起始时间
start_time=$(date +%s)

echo "🚀 正在清理并生成 Hexo 静态页面..."
hexo clean && hexo g
hexo_status=$?

echo "📦 正在提交并推送到 GitHub..."
git add .
git commit -m "🚀 Auto Deploy: $(date '+%Y-%m-%d %H:%M:%S')"
git push origin main
push_status=$?

# 计算耗时
end_time=$(date +%s)
duration=$((end_time - start_time))

# macOS 系统通知
notify() {
    osascript -e "display notification \"$1\" with title \"🚀 Hexo 部署脚本\""
}

# 判断结果并发送通知
if [[ $hexo_status -eq 0 && $push_status -eq 0 ]]; then
    echo "✅ 部署成功，耗时 ${duration} 秒"
    notify "✅ 部署成功！耗时 ${duration} 秒，Cloudflare Pages 将自动构建"
else
    echo "❌ 部署失败，请检查日志，耗时 ${duration} 秒"
    notify "❌ 部署失败！耗时 ${duration} 秒，请查看终端输出"
fi