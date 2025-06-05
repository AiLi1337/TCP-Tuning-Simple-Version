#!/usr/bin/env bash

# =================================================================
# TCP调优脚本 - 最终美化版 v9
# 作者: BlackSheep & Gemini
#
# 此版本在子菜单中也增加了状态显示，方便实时查看参数。
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
    printf "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║                ${BOLD_WHITE}TCP 调优脚本 - 简单版${CYAN}                ║${NC}\n"
    printf "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n\n"
}

# 绘制注意事项
draw_notes() {
    printf "${YELLOW}┌─ 注意事项 ───────────────────────────────────${NC}\n"
    printf "${YELLOW}│${NC}  ${RED}1. 此脚本的TCP调优操作对劣质线路无效${NC}\n"
    printf "${YELLOW}│${NC}  ${RED}2. 小带宽或低延迟场景下，调优效果不显著${NC}\n"
    printf "${YELLOW}│${NC}  ${RED}3. 请尽量在晚高峰进行调优${NC}\n"
    printf "${YELLOW}└────────────────────────────────────────────────────${NC}\n\n"
}

# 绘制并显示系统状态
draw_status() {
    # 获取TCP缓冲区大小
    wmem=$(sysctl net.ipv4.tcp_wmem | awk -F'= ' '{print $2}')
    rmem=$(sysctl net.ipv4.tcp_rmem | awk -F'= ' '{print $2}')

    printf "${GREEN}┌─ 系统状态 ───────────────────────────────────${NC}\n"
    printf "${GREEN}│${NC}  依赖状态:\n"

    # 循环检查并显示每个依赖的状态
    local dependencies=("iperf3" "nohup" "bc")
    for dep in "${dependencies[@]}"; do
        local status_text
        local status_color
        if command -v "$dep" &> /dev/null; then
            status_text="已安装"
            status_color="${GREEN}"
        else
            status_text="未安装"
            status_color="${RED}"
        fi
        printf "${GREEN}│${NC}    ● %-8s : ${status_color}%s${NC}\n" "$dep" "$status_text"
    done

    printf "${GREEN}│${NC}\n"
    printf "${GREEN}│${NC}  TCP缓冲区 (当前值):\n"
    printf "${GREEN}│${NC}    读 (rmem): ${BOLD_WHITE}%-35s${NC}\n" "$rmem"
    printf "${GREEN}│${NC}    写 (wmem): ${BOLD_WHITE}%-35s${NC}\n" "$wmem"
    printf "${GREEN}└────────────────────────────────────────────────────${NC}\n\n"
}

# 绘制主菜单
draw_main_menu() {
    printf "${CYAN}┌─ 主菜单 ─────────────────────────────────────${NC}\n"
    printf "${CYAN}│${NC}   ${YELLOW}1.${NC} 自由调整\n"
    printf "${CYAN}│${NC}   ${YELLOW}2.${NC} 调整复原\n"
    printf "${CYAN}│${NC}   ${YELLOW}0.${NC} 退出脚本\n"
    printf "${CYAN}└────────────────────────────────────────────────────${NC}\n\n"
}

# 绘制子菜单
draw_submenu() {
    printf "${CYAN}┌─ 自由调整子菜单 ───────────────────────────────${NC}\n"
    printf "${CYAN}│${NC}   ${YELLOW}1.${NC} 后台启动 iperf3 服务\n"
    printf "${CYAN}│${NC}   ${YELLOW}2.${NC} 停止 iperf3 服务\n"
    printf "${CYAN}│${NC}\n"
    printf "${CYAN}│${NC}   ${YELLOW}3.${NC} TCP缓冲区(MiB)设为指定值\n"
    printf "${CYAN}│${NC}   ${YELLOW}4.${NC} TCP缓冲区(BDP/字节)设为指定值\n"
    printf "${CYAN}│${NC}   ${YELLOW}5.${NC} 重置TCP缓冲区参数\n"
    printf "${CYAN}│${NC}\n"
    printf "${CYAN}│${NC}   ${YELLOW}0.${NC} 返回主菜单\n"
    printf "${CYAN}└────────────────────────────────────────────────────${NC}\n\n"
}

# 绘制一个简单的确认提示
prompt_continue() {
    printf "\n${YELLOW}按回车键继续...${NC}"
    read -r
}


# =================================================================
# 核心功能函数
# =================================================================

# 清理sysctl.conf中的TCP缓冲区配置
clear_conf() {
    sed -i '/^net\.ipv4\.tcp_wmem/d' /etc/sysctl.conf
    sed -i '/^net\.ipv4\.tcp_rmem/d' /etc/sysctl.conf
    if [ -n "$(tail -c1 /etc/sysctl.conf)" ]; then
        echo "" >> /etc/sysctl.conf
    fi
}

# 重置TCP缓冲区为系统默认值
reset_tcp() {
    clear_conf
    sysctl -w net.ipv4.tcp_wmem="4096 16384 4194304" >/dev/null
    sysctl -w net.ipv4.tcp_rmem="4096 87380 6291456" >/dev/null
    echo -e "\n${GREEN}✔ 已将TCP缓冲区(wmem/rmem)重置为默认值。${NC}"
}


# =================================================================
# 初始化与依赖检查
# =================================================================

# 启用BBR和FQ
sysctl -w net.ipv4.tcp_congestion_control=bbr &>/dev/null
sysctl -w net.core.default_qdisc=fq &>/dev/null
if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
fi
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
fi

# 检查并安装依赖
if ! command -v iperf3 &> /dev/null || ! command -v nohup &> /dev/null || ! command -v bc &> /dev/null; then
    draw_header
    echo "检测到依赖缺失，开始安装..."
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y iperf3 coreutils bc
    elif [ -f /etc/redhat-release ]; then
        yum install -y iperf3 coreutils bc
    else
        echo -e "${RED}✘ 自动安装依赖失败，请自行安装 iperf3, coreutils 和 bc。${NC}"
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
    
    printf "${GREEN}请输入方案编号 ➤ ${NC}"
    read choice_main

    case "$choice_main" in
        1)
            # 进入子菜单循环
            while true; do
                draw_header
                draw_status # 在子菜单中也显示状态
                draw_submenu
                
                printf "${GREEN}请输入子菜单选项 ➤ ${NC}"
                read sub_choice

                case "$sub_choice" in
                    1)
                        local_ip=$(wget -qO- --inet4-only http://icanhazip.com 2>/dev/null)
                        if [ -z "$local_ip" ]; then
                            local_ip=$(wget -qO- http://icanhazip.com)
                        fi
                        echo -e "\n${CYAN}您的出口IP是: ${BOLD_WHITE}$local_ip${NC}"
                        
                        while true; do
                            printf "${GREEN}请输入 iperf3 端口号（默认 5201） ➤ ${NC}"
                            read iperf_port
                            iperf_port=${iperf_port:-5201}
                            if [[ "$iperf_port" =~ ^[0-9]+$ ]] && [ "$iperf_port" -ge 1 ] && [ "$iperf_port" -le 65535 ]; then
                                break
                            else
                                echo -e "${RED}✘ 无效的端口号！请输入 1-65535 范围内的数字。${NC}"
                            fi
                        done
                        
                        pkill iperf3 &>/dev/null
                        nohup iperf3 -s -p "$iperf_port" > /dev/null 2>&1 &
                        echo -e "\n${GREEN}✔ iperf3 服务端已在后台启动，端口：$iperf_port${NC}"
                        echo -e "${YELLOW}ℹ 可在客户端使用以下命令测试： iperf3 -c $local_ip -R -t 30 -p $iperf_port${NC}"
                        ;;
                    2)
                        echo -e "\n${CYAN}正在停止 iperf3 服务...${NC}"
                        pkill iperf3 &>/dev/null
                        echo -e "${GREEN}✔ iperf3 服务已停止。${NC}"
                        ;;
                    3)
                        while true; do
                            printf "${GREEN}请输入TCP缓冲区max值 (单位 MiB, 可带小数) ➤ ${NC}"
                            read tcp_value
                            if [[ "$tcp_value" =~ ^[0-9]*\.?[0-9]+$ ]] && (( $(echo "$tcp_value > 0" | bc -l) )); then
                                break
                            else
                                echo -e "${RED}✘ 无效输入，请输入一个大于0的数字。${NC}"
                            fi
                        done
                        
                        value=$(printf "%.0f" "$(echo "$tcp_value * 1024 * 1024" | bc)")
                        
                        echo -e "\n${CYAN}正在设置TCP缓冲区max值为 ${BOLD_WHITE}$tcp_value MiB ($value bytes)...${NC}"
                        clear_conf
                        echo "net.ipv4.tcp_wmem=4096 16384 $value" >> /etc/sysctl.conf
                        echo "net.ipv4.tcp_rmem=4096 87380 $value" >> /etc/sysctl.conf
                        sysctl -p >/dev/null
                        echo -e "${GREEN}✔ 设置已永久保存到 /etc/sysctl.conf，重启后依然生效。${NC}"
                        ;;
                    4)
                        while true; do
                            printf "${GREEN}请输入TCP缓冲区max值 (单位 BDP/字节) ➤ ${NC}"
                            read value
                            if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
                                break
                            else
                                echo -e "${RED}✘ 无效输入，请输入一个正整数。${NC}"
                            fi
                        done

                        echo -e "\n${CYAN}正在设置TCP缓冲区max值为 ${BOLD_WHITE}$value bytes...${NC}"
                        clear_conf
                        echo "net.ipv4.tcp_wmem=4096 16384 $value" >> /etc/sysctl.conf
                        echo "net.ipv4.tcp_rmem=4096 87380 $value" >> /etc/sysctl.conf
                        sysctl -p >/dev/null
                        echo -e "${GREEN}✔ 设置已永久保存到 /etc/sysctl.conf，重启后依然生效。${NC}"
                        ;;
                    5)
                        reset_tcp
                        ;;
                    0)
                        echo -e "\n${CYAN}正在返回主菜单...${NC}"
                        sleep 1
                        break 
                        ;;
                    *)
                        echo -e "\n${RED}✘ 无效选择，请输入0-5之间的数字。${NC}"
                        ;;
                esac
                prompt_continue
            done
            ;;
        2)
            echo -e "\n${CYAN}执行TCP参数复原...${NC}"
            reset_tcp
            echo -e "\n${GREEN}✔ 复原已完成。${NC}"
            prompt_continue
            ;;
        0)
            echo -e "\n${CYAN}感谢使用，退出脚本。${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}✘ 无效选择，请输入0-2之间的数字。${NC}"
            prompt_continue
            ;;
    esac
done