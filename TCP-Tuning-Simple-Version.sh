#!/usr/bin/env bash

# =================================================================
# TCP调优脚本 - 最终美化版 v6
# 作者: BlackSheep & Gemini
#
# 此版本修复了UI颜色代码显示的BUG，并优化了状态显示逻辑。
# 经过多轮排查，以确保代码的稳定性和准确性。
# =================================================================


# --------------------------------------------------
# 全局变量与颜色定义
# --------------------------------------------------
# 使用tput来获取终端颜色能力，如果不支持则禁用颜色
if tput setaf 1 &> /dev/null; then
    BOLD_WHITE='\033[1;37m'
    CYAN='\033[0;36m'
    YELLOW='\033[1;33m'
    GREEN='\033[1;32m'
    RED='\033[1;31m'
    NC='\033[0m' # No Color
else
    BOLD_WHITE=''
    CYAN=''
    YELLOW=''
    GREEN=''
    RED=''
    NC=''
fi


# =================================================================
# UI绘制函数
# =================================================================

# 绘制脚本主标题
draw_header() {
    clear
    printf "<span class="math-inline">\{CYAN\}╔════════════════════════════════════════════════════════════╗</span>{NC}\n"
    printf "${CYAN}║                <span class="math-inline">\{BOLD\_WHITE\}TCP 调优脚本 \- 简单版</span>{CYAN}                ║<span class="math-inline">\{NC\}\\n"
printf "</span>{CYAN}╚════════════════════════════════════════════════════════════╝<span class="math-inline">\{NC\}\\n\\n"
\}
\# 绘制注意事项
draw\_notes\(\) \{
printf "</span>{YELLOW}┌─ 注意事项 ───────────────────────────────────<span class="math-inline">\{NC\}\\n"
printf "</span>{YELLOW}│${NC}  <span class="math-inline">\{RED\}1\. 此脚本的TCP调优操作对劣质线路无效</span>{NC}\n"
    printf "<span class="math-inline">\{YELLOW\}│</span>{NC}  <span class="math-inline">\{RED\}2\. 小带宽或低延迟场景下，调优效果不显著</span>{NC}\n"
    printf "<span class="math-inline">\{YELLOW\}│</span>{NC}  <span class="math-inline">\{RED\}3\. 请尽量在晚高峰进行调优</span>{NC}\n"
    printf "<span class="math-inline">\{YELLOW\}└────────────────────────────────────────────────────</span>{NC}\n\n"
}

# 绘制并显示系统状态
draw_status() {
    # 获取TCP缓冲区大小
    wmem=$(sysctl net.ipv4.tcp_wmem | awk -F'= ' '{print <span class="math-inline">2\}'\)
rmem\=</span>(sysctl net.ipv4.tcp_rmem | awk -F'= ' '{print <span class="math-inline">2\}'\)
printf "</span>{GREEN}┌─ 系统状态 ───────────────────────────────────<span class="math-inline">\{NC\}\\n"
printf "</span>{GREEN}│<span class="math-inline">\{NC\}  依赖状态\:\\n"
\# 循环检查并显示每个依赖的状态
local dependencies\=\("iperf3" "nohup" "bc"\)
for dep in "</span>{dependencies[@]}"; do
        local status_text
        local status_color
        if command -v "<span class="math-inline">dep" &\> /dev/null; then
status\_text\="已安装"
status\_color\="</span>{GREEN}"
        else
            status_text="未安装"
            status_color="<span class="math-inline">\{RED\}"
fi
printf "</span>{GREEN}│${NC}    ● %-8s : <span class="math-inline">\{status\_color\}%s</span>{NC}\n" "$dep" "<span class="math-inline">status\_text"
done
printf "</span>{GREEN}│<span class="math-inline">\{NC\}\\n"
printf "</span>{GREEN}│<span class="math-inline">\{NC\}  TCP缓冲区 \(当前值\)\:\\n"
printf "</span>{GREEN}│${NC}    读 (rmem): <span class="math-inline">\{BOLD\_WHITE\}%\-35s</span>{NC}\n" "<span class="math-inline">rmem"
printf "</span>{GREEN}│${NC}    写 (wmem): <span class="math-inline">\{BOLD\_WHITE\}%\-35s</span>{NC}\n" "<span class="math-inline">wmem"
printf "</span>{GREEN}└────────────────────────────────────────────────────<span class="math-inline">\{NC\}\\n\\n"
\}
\# 绘制主菜单
draw\_main\_menu\(\) \{
printf "</span>{CYAN}┌─ 主菜单 ─────────────────────────────────────<span class="math-inline">\{NC\}\\n"
printf "</span>{CYAN}│${NC}   <span class="math-inline">\{YELLOW\}1\.</span>{NC} 自由调整\n"
    printf "<span class="math-inline">\{CYAN\}│</span>{NC}   <span class="math-inline">\{YELLOW\}2\.</span>{NC} 调整复原\n"
    printf "<span class="math-inline">\{CYAN\}│</span>{NC}   <span class="math-inline">\{YELLOW\}0\.</span>{NC} 退出脚本\n"
    printf "<span class="math-inline">\{CYAN\}└────────────────────────────────────────────────────</span>{NC}\n\n"
}

# 绘制子菜单
draw_submenu() {
    printf "<span class="math-inline">\{CYAN\}┌─ 自由调整子菜单 ───────────────────────────────</span>{NC}\n"
    printf "<span class="math-inline">\{CYAN\}│</span>{NC}   <span class="math-inline">\{YELLOW\}1\.</span>{NC} 后台启动 iperf3\n"
    printf "<span class="math-inline">\{CYAN\}│</span>{NC}\n"
    printf "<span class="math-inline">\{CYAN\}│</span>{NC}   <span class="math-inline">\{YELLOW\}2\.</span>{NC} TCP缓冲区(MiB)设为指定值 (永久生效)\n"
    printf "<span class="math-inline">\{CYAN\}│</span>{NC}   <span class="math-inline">\{YELLOW\}3\.</span>{NC} TCP缓冲区(BDP/字节)设为指定值 (永久生效)\n"
    printf "<span class="math-inline">\{CYAN\}│</span>{NC}\n"
    printf "<span class="math-inline">\{CYAN\}│</span>{NC}   <span class="math-inline">\{YELLOW\}4\.</span>{NC} 重置TCP缓冲区参数\n"
    printf "<span class="math-inline">\{CYAN\}│</span>{NC}   <span class="math-inline">\{YELLOW\}5\.</span>{NC} 返回主菜单\n"
    printf "<span class="math-inline">\{CYAN\}│</span>{NC}   <span class="math-inline">\{YELLOW\}0\.</span>{NC} 停止 iperf3 并返回主菜单\n"
    printf "<span class="math-inline">\{CYAN\}└────────────────────────────────────────────────────</span>{NC}\n\n"
}

# 绘制输入提示符，并接收输入
prompt_input() {
    local prompt_text=$1
    local -n input_var=<span class="math-inline">2
printf "</span>{GREEN}${prompt_text} ➤ <span class="math-inline">\{NC\}"
read input\_var
\}
\# 绘制一个简单的确认提示
prompt\_continue\(\) \{
printf "\\n</span>{YELLOW}按回车键继续...<span class="math-inline">\{NC\}"
read \-r
\}
\# \=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=
\# 核心功能函数
\# \=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=
\# 清理sysctl\.conf中的TCP缓冲区配置
clear\_conf\(\) \{
sed \-i '/^net\\\.ipv4\\\.tcp\_wmem/d' /etc/sysctl\.conf
sed \-i '/^net\\\.ipv4\\\.tcp\_rmem/d' /etc/sysctl\.conf
if \[ \-n "</span>(tail -c1 /etc/sysctl.conf)" ]; then
        echo "" >> /etc/sysctl.conf
    fi
}

# 重置TCP缓冲区为系统默认值
reset_tcp() {
    clear_conf
    sysctl -w net.ipv4.tcp_wmem="4096 16384 4194304" >/dev/null
    sysctl -w net.ipv4.tcp_rmem="4096 87380 6291456" >/dev/null
    echo -e "\n${GREEN}✔ 已将TCP缓冲区(wmem/rmem)重置为默认值。<span class="math-inline">\{NC\}"
\}
\# \=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=
\# 初始化与依赖检查
\# \=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=\=
\# 启用BBR和FQ
sysctl \-w net\.ipv4\.tcp\_congestion\_control\=bbr &\>/dev/null
sysctl \-w net\.core\.default\_qdisc\=fq &\>/dev/null
if \! grep \-q "net\.ipv4\.tcp\_congestion\_control\=bbr" /etc/sysctl\.conf; then
echo "net\.ipv4\.tcp\_congestion\_control\=bbr" \>\> /etc/sysctl\.conf
fi
if \! grep \-q "net\.core\.default\_qdisc\=fq" /etc/sysctl\.conf; then
echo "net\.core\.default\_qdisc\=fq" \>\> /etc/sysctl\.conf
fi
\# 检查并安装依赖
if \! command \-v iperf3 &\> /dev/null \|\| \! command \-v nohup &\> /dev/null \|\| \! command \-v bc &\> /dev/null; then
echo "检测到依赖缺失，开始安装\.\.\."
if \[ \-f /etc/debian\_version \]; then
apt\-get update && apt\-get install \-y iperf3 coreutils bc
elif \[ \-f /etc/redhat\-release \]; then
yum install \-y iperf3 coreutils bc
else
echo \-e "</span>{RED}✘ 自动安装依赖失败，请自行安装 iperf3, coreutils 和 bc。${NC}"
        exit 1
    fi
fi


# =================================================================
# 主程序入口
# =================================================================

# 主循环
while true; do
    draw_header
    draw_notes
    draw_status
    draw_main_menu
    
    prompt_input "请输入方案编号" choice_main

    case "$choice_main" in
        1)
            # 进入子菜单循环
            while true; do
                draw_header
                draw_submenu
                prompt_input "请输入子菜单选项" sub_choice

                case "<span class="math-inline">sub\_choice" in
1\)
local\_ip\=</span>(wget -qO- --inet4-only http://icanhazip.com 2>/dev/null)
                        if [ -z "<span class="math-inline">local\_ip" \]; then
local\_ip\=</span>(wget -qO- http://icanhazip.com)
                        fi
                        echo -e "\n${CYAN}您的出口IP是: ${BOLD_WHITE}<span class="math-inline">local\_ip</span>{NC}"
                        
                        while true; do
                            prompt_input "请输入 iperf3 端口号（默认 5201）" iperf_port
                            iperf_port=${iperf_port:-5201}
                            if [[ "<span class="math-inline">iperf\_port" \=\~ ^\[0\-9\]\+</span> ]] && [ "$iperf_port" -ge 1 ] && [ "<span class="math-inline">iperf\_port" \-le 65535 \]; then
break
else
echo \-e "</span>{RED}✘ 无效的端口号！请输入 1-65535 范围内的数字。${NC}"
                            fi
                        done
                        
                        pkill iperf3 &>/dev/null
                        nohup iperf3 -s -p "<span class="math-inline">iperf\_port" \> /dev/null 2\>&1 &
echo \-e "\\n</span>{GREEN}✔ iperf3 服务端已在后台启动，端口：<span class="math-inline">iperf\_port</span>{NC}"
                        echo -e "${YELLOW}ℹ 可在客户端使用以下命令测试： iperf3 -c $local_ip -R -t 30 -p <span class="math-inline">iperf\_port</span>{NC}"
                        ;;
                    2)
                        while true; do
                            prompt_input "请输入