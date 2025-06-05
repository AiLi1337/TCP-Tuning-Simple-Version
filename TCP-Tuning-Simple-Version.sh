#!/usr/bin/env bash

# =================================================================
# TCP调优脚本 - 最终美化版
# 作者: BlackSheep & Gemini
#
# 此脚本集成了彩色UI和模块化功能，旨在提供更友好的用户体验。
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
    # 检查依赖
    iperf3_status="${GREEN}已安装${NC}"
    nohup_status="${GREEN}已安装${NC}"
    if ! command -v iperf3 &> /dev/null; then iperf3_status="${RED}未安装${NC}"; fi
    if ! command -v nohup &> /dev/null; then nohup_status="${RED}未安装${NC}"; fi

    # 获取TCP缓冲区大小
    wmem=$(sysctl net.ipv4.tcp_wmem | awk -F'= ' '{print $2}')
    rmem=$(sysctl net.ipv4.tcp_rmem | awk -F'= ' '{print $2}')

    printf "${GREEN}┌─ 系统状态 ───────────────────────────────────${NC}\n"
    printf "${GREEN}│${NC}  ● iperf3: %-42s ${NC}\n" "$iperf3_status"
    printf "${GREEN}│${NC}  ● nohup:  %-42s ${NC}\n" "$nohup_status"
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
    printf "${CYAN}│${NC}   ${YELLOW}1.${NC} 后台启动 iperf3\n"
    printf "${CYAN}│${NC}   ${YELLOW}2.${NC} TCP缓冲区max值设为指定值 (永久生效)\n"
    printf "${CYAN}│${NC}   ${YELLOW}3.${NC} 重置TCP缓冲区参数\n"
    printf "${CYAN}│${NC}   ${YELLOW}4.${NC} 清除TC限速\n"
    printf "${CYAN}│${NC}   ${YELLOW}0.${NC} 结束 iperf3 进程并返回主菜单\n"
    printf "${CYAN}└────────────────────────────────────────────────────${NC}\n\n"
}

# 绘制输入提示符
prompt_input() {
    printf "${GREEN}$1 ➤ ${NC}"
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

# 重置TC限速规则
reset_tc() {
    if [ -f /etc/rc.local ]; then
        > /etc/rc.local
        echo "#!/bin/bash" > /etc/rc.local
        chmod +x /etc/rc.local
        echo -e "\n${GREEN}✔ 已清空 /etc/rc.local 并添加基本脚本头部。${NC}"
    else
        echo -e "\n${YELLOW}ℹ /etc/rc.local 文件不存在，无需清理。${NC}"
    fi

    echo ""
    ip link show
    echo ""
    while true; do
        read -p "请根据以上列表输入曾被限速的网卡名称： " iface
        if ip link show "$iface" &>/dev/null; then
            break
        else
            echo -e "${RED}✘ 网卡名称无效或不存在，请重新输入。${NC}"
        fi
    done

    if command -v tc &> /dev/null; then
        tc qdisc del dev "$iface" root &>/dev/null
        tc qdisc del dev "$iface" ingress &>/dev/null
        echo -e "${GREEN}✔ 已尝试清除网卡 $iface 的 tc 限速规则。${NC}"
    else
        echo -e "${YELLOW}ℹ tc 命令不可用，未执行限速清理。${NC}"
    fi

    if ip link show ifb0 &>/dev/null; then
        tc qdisc del dev ifb0 root &>/dev/null
        ip link set dev ifb0 down
        ip link delete ifb0
        echo -e "${GREEN}✔ 已删除 ifb0 网卡。${NC}"
    else
        echo -e "${YELLOW}ℹ ifb0 网卡不存在，无需删除。${NC}"
    fi
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
if ! command -v iperf3 &> /dev/null || ! command -v nohup &> /dev/null; then
    echo "检测到依赖缺失，开始安装..."
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y iperf3 coreutils
    elif [ -f /etc/redhat-release ]; then
        yum install -y iperf3 coreutils
    else
        echo -e "${RED}✘ 自动安装依赖失败，请自行安装 iperf3 和 coreutils。${NC}"
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
    
    prompt_input "请输入方案编号"
    read choice_main

    case "$choice_main" in
        1)
            # 进入子菜单循环
            while true; do
                draw_header
                draw_submenu
                prompt_input "请输入子菜单选项"
                read sub_choice

                case "$sub_choice" in
                    1)
                        local_ip=$(wget -qO- --inet4-only http://icanhazip.com 2>/dev/null)
                        if [ -z "$local_ip" ]; then
                            local_ip=$(wget -qO- http://icanhazip.com)
                        fi
                        echo -e "\n${CYAN}您的出口IP是: ${BOLD_WHITE}$local_ip${NC}"
                        
                        while true; do
                            read -p "请输入 iperf3 端口号（默认 5201）: " iperf_port
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
                        while true; do
                            read -p "请输入TCP缓冲区max值 (单位 MiB): " tcp_value
                            if [[ "$tcp_value" =~ ^[1-9][0-9]*$ ]]; then
                                break
                            else
                                echo -e "${RED}✘ 无效输入，请输入一个正整数。${NC}"
                            fi
                        done
                        
                        value=$((tcp_value * 1024 * 1024))
                        echo -e "\n${CYAN}正在设置TCP缓冲区max值为 ${BOLD_WHITE}$tcp_value MiB ($value bytes)...${NC}"
                        clear_conf
                        echo "net.ipv4.tcp_wmem=4096 16384 $value" >> /etc/sysctl.conf
                        echo "net.ipv4.tcp_rmem=4096 87380 $value" >> /etc/sysctl.conf
                        sysctl -p >/dev/null
                        echo -e "${GREEN}✔ 设置已永久保存到 /etc/sysctl.conf，重启后依然生效。${NC}"
                        ;;
                    3)
                        reset_tcp
                        ;;
                    4)
                        reset_tc
                        ;;
                    0)
                        echo -e "\n${CYAN}停止 iperf3 进程...${NC}"
                        pkill iperf3 &>/dev/null
                        echo -e "${GREEN}✔ 已停止。正在返回主菜单...${NC}"
                        sleep 1
                        break # 跳出子菜单循环
                        ;;
                    *)
                        echo -e "\n${RED}✘ 无效选择，请输入0-4之间的数字。${NC}"
                        ;;
                esac
                echo ""
                read -p "按回车键继续..."
            done
            ;;
        2)
            echo -e "\n${CYAN}执行调整复原...${NC}"
            reset_tcp
            reset_tc
            echo -e "\n${GREEN}✔ 复原已完成。${NC}"
            read -p "按回车键返回主菜单..."
            ;;
        0)
            echo -e "\n${CYAN}感谢使用，退出脚本。${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}✘ 无效选择，请输入0-2之间的数字。${NC}"
            read -p "按回车键继续..."
            ;;
    esac
done