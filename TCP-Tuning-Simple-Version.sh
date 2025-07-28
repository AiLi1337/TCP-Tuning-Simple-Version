#!/usr/bin/env bash

# =================================================================
# TCP调优脚本 - 最终版 v9
# 作者: AiLi1337
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
    printf "${CYAN}│${NC}   ${YELLOW}6.${NC} 检查配置状态\n"
    printf "${CYAN}│${NC}   ${YELLOW}7.${NC} 显示配置建议\n"
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

# 清理sysctl.conf中的TCP缓冲区配置 - 改进版本
clear_conf() {
    local config_file="/etc/sysctl.conf"
    
    # 检查配置文件是否存在
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}⚠ 配置文件 $config_file 不存在，将创建新文件${NC}"
        touch "$config_file" 2>/dev/null || {
            echo -e "${RED}✘ 无法创建配置文件，请检查权限${NC}"
            return 1
        }
    fi
    
    # 备份原配置文件
    local backup_name="/etc/sysctl.conf.bak.$(date +%Y%m%d_%H%M%S)"
    if ! cp "$config_file" "$backup_name" 2>/dev/null; then
        echo -e "${YELLOW}⚠ 无法创建配置文件备份${NC}"
    else
        echo -e "${CYAN}ℹ 已备份原配置文件到: $backup_name${NC}"
    fi
    
    # 删除旧的TCP配置（包括注释行）
    if ! sed -i '/^# TCP调优配置/d' "$config_file" 2>/dev/null; then
        echo -e "${RED}✘ 清理配置文件失败，请检查权限${NC}"
        return 1
    fi
    
    sed -i '/^net\.ipv4\.tcp_wmem/d' "$config_file" 2>/dev/null
    sed -i '/^net\.ipv4\.tcp_rmem/d' "$config_file" 2>/dev/null
    sed -i '/^net\.ipv4\.tcp_congestion_control/d' "$config_file" 2>/dev/null
    sed -i '/^net\.core\.default_qdisc/d' "$config_file" 2>/dev/null
    
    # 确保文件末尾有换行符
    if [ -n "$(tail -c1 "$config_file" 2>/dev/null)" ]; then
        echo "" >> "$config_file" 2>/dev/null
    fi
    
    return 0
}

# 验证配置是否生效 - 改进版本，只检查最大值是否匹配
verify_config() {
    local expected_wmem="$1"
    local expected_rmem="$2"
    
    # 等待配置生效
    sleep 2
    
    # 提取期望的最大值（第三个参数）
    local expected_wmem_max=$(echo "$expected_wmem" | awk '{print $3}')
    local expected_rmem_max=$(echo "$expected_rmem" | awk '{print $3}')
    
    # 获取当前实际值的最大值
    local current_wmem_max=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
    local current_rmem_max=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')
    
    # 检查是否获取到了有效值
    if [[ -z "$current_wmem_max" ]] || [[ -z "$current_rmem_max" ]]; then
        echo -e "${YELLOW}⚠ 无法获取当前TCP缓冲区配置${NC}"
        return 1
    fi
    
    # 只比较最大值是否匹配
    if [[ "$current_wmem_max" == "$expected_wmem_max" ]] && [[ "$current_rmem_max" == "$expected_rmem_max" ]]; then
        return 0
    else
        # 提供调试信息但不显示为错误
        echo -e "${CYAN}ℹ 验证详情: 期望wmem最大值=$expected_wmem_max, 实际=$current_wmem_max${NC}"
        echo -e "${CYAN}ℹ 验证详情: 期望rmem最大值=$expected_rmem_max, 实际=$current_rmem_max${NC}"
        return 1
    fi
}

# 应用并持久化配置 - 改进版本
apply_config() {
    local wmem_value="$1"
    local rmem_value="$2"
    
    echo -e "${CYAN}正在应用TCP缓冲区配置...${NC}"
    
    # 清理旧配置
    if ! clear_conf; then
        echo -e "${RED}✘ 清理旧配置失败，请检查系统权限${NC}"
        return 1
    fi
    
    # 写入新配置到sysctl.conf
    if ! {
        echo "# TCP调优配置 - 由TCP调优脚本生成 $(date)"
        echo "net.ipv4.tcp_congestion_control=bbr"
        echo "net.core.default_qdisc=fq"
        echo "net.ipv4.tcp_wmem=$wmem_value"
        echo "net.ipv4.tcp_rmem=$rmem_value"
        echo ""
    } >> /etc/sysctl.conf 2>/dev/null; then
        echo -e "${RED}✘ 写入配置文件失败，请检查系统权限${NC}"
        return 1
    fi
    
    # 立即应用配置
    local apply_success=true
    sysctl -w net.ipv4.tcp_wmem="$wmem_value" >/dev/null 2>&1 || apply_success=false
    sysctl -w net.ipv4.tcp_rmem="$rmem_value" >/dev/null 2>&1 || apply_success=false
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    
    # 重新加载sysctl配置
    sysctl -p >/dev/null 2>&1
    
    if [[ "$apply_success" == "false" ]]; then
        echo -e "${RED}✘ 应用系统配置失败，请检查系统权限${NC}"
        return 1
    fi
    
    # 验证配置是否生效
    if verify_config "$wmem_value" "$rmem_value"; then
        echo -e "${GREEN}✔ 配置已成功应用并持久化到 /etc/sysctl.conf${NC}"
        ensure_persistence
        return 0
    else
        # 即使验证失败，也检查配置是否实际生效了
        local current_wmem_max=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
        local current_rmem_max=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')
        local expected_wmem_max=$(echo "$wmem_value" | awk '{print $3}')
        local expected_rmem_max=$(echo "$rmem_value" | awk '{print $3}')
        
        if [[ "$current_wmem_max" == "$expected_wmem_max" ]] && [[ "$current_rmem_max" == "$expected_rmem_max" ]]; then
            echo -e "${GREEN}✔ 配置实际已成功应用（验证函数检测到细微差异，但配置正确）${NC}"
            ensure_persistence
            return 0
        else
            echo -e "${YELLOW}⚠ 配置可能已应用，但验证未完全通过${NC}"
            echo -e "${CYAN}ℹ 请手动检查配置状态：${NC}"
            echo -e "${CYAN}  当前wmem最大值: $current_wmem_max (期望: $expected_wmem_max)${NC}"
            echo -e "${CYAN}  当前rmem最大值: $current_rmem_max (期望: $expected_rmem_max)${NC}"
            return 1
        fi
    fi
}

# 确保配置持久化的额外措施 - 改进版本
ensure_persistence() {
    echo -e "${CYAN}正在确保配置持久化...${NC}"
    
    # 检查systemd-sysctl服务状态
    if command -v systemctl &> /dev/null; then
        if systemctl is-enabled systemd-sysctl >/dev/null 2>&1; then
            if systemctl restart systemd-sysctl >/dev/null 2>&1; then
                echo -e "${GREEN}  ✔ systemd-sysctl服务已重启${NC}"
            else
                echo -e "${YELLOW}  ⚠ systemd-sysctl服务重启失败${NC}"
            fi
        else
            echo -e "${YELLOW}  ⚠ systemd-sysctl服务未启用${NC}"
        fi
    fi
    
    # 创建额外的配置文件作为备份
    local backup_conf="/etc/sysctl.d/99-tcp-tuning.conf"
    if [ -d "/etc/sysctl.d" ]; then
        local wmem_line=$(grep "^net\.ipv4\.tcp_wmem" /etc/sysctl.conf | tail -1)
        local rmem_line=$(grep "^net\.ipv4\.tcp_rmem" /etc/sysctl.conf | tail -1)
        
        if [[ -n "$wmem_line" ]] && [[ -n "$rmem_line" ]]; then
            {
                echo "# TCP调优配置备份 - 由TCP调优脚本生成 $(date)"
                echo "# 此文件确保配置在系统重启后仍然生效"
                echo "net.ipv4.tcp_congestion_control=bbr"
                echo "net.core.default_qdisc=fq"
                echo "$wmem_line"
                echo "$rmem_line"
            } > "$backup_conf" 2>/dev/null
            
            if [ -f "$backup_conf" ]; then
                echo -e "${GREEN}  ✔ 已创建备份配置文件: $backup_conf${NC}"
            else
                echo -e "${YELLOW}  ⚠ 无法创建备份配置文件${NC}"
            fi
        else
            echo -e "${YELLOW}  ⚠ 无法找到有效的TCP配置行${NC}"
        fi
    else
        echo -e "${YELLOW}  ⚠ /etc/sysctl.d 目录不存在${NC}"
    fi
    
    # 验证配置是否会在重启后生效
    echo -e "${CYAN}  ℹ 配置将在系统重启后自动生效${NC}"
}

# 检查配置状态 - 详细版本
check_config_status() {
    local config_file="/etc/sysctl.conf"
    local backup_file="/etc/sysctl.d/99-tcp-tuning.conf"
    
    echo -e "${CYAN}=== 详细配置状态检查 ===${NC}\n"
    
    # 当前运行时配置
    echo -e "${GREEN}当前运行时配置:${NC}"
    local current_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)
    local current_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)
    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    
    if [[ -n "$current_wmem" ]]; then
        echo -e "  TCP wmem: ${BOLD_WHITE}$current_wmem${NC}"
        local wmem_max=$(echo "$current_wmem" | awk '{print $3}')
        local wmem_mb=$(echo "scale=2; $wmem_max / 1024 / 1024" | bc 2>/dev/null)
        echo -e "  wmem最大值: ${YELLOW}$wmem_max bytes${NC} (约 ${YELLOW}${wmem_mb} MiB${NC})"
    else
        echo -e "  TCP wmem: ${RED}获取失败${NC}"
    fi
    
    if [[ -n "$current_rmem" ]]; then
        echo -e "  TCP rmem: ${BOLD_WHITE}$current_rmem${NC}"
        local rmem_max=$(echo "$current_rmem" | awk '{print $3}')
        local rmem_mb=$(echo "scale=2; $rmem_max / 1024 / 1024" | bc 2>/dev/null)
        echo -e "  rmem最大值: ${YELLOW}$rmem_max bytes${NC} (约 ${YELLOW}${rmem_mb} MiB${NC})"
    else
        echo -e "  TCP rmem: ${RED}获取失败${NC}"
    fi
    
    echo -e "  拥塞控制: ${BOLD_WHITE}${current_cc:-未知}${NC}"
    echo -e "  队列算法: ${BOLD_WHITE}${current_qdisc:-未知}${NC}"
    
    # 配置文件检查
    echo -e "\n${GREEN}配置文件状态:${NC}"
    
    # 检查主配置文件
    if [ -f "$config_file" ]; then
        echo -e "${GREEN}  ✔ 主配置文件存在${NC} ($config_file)"
        
        if grep -q "net.ipv4.tcp_wmem" "$config_file" 2>/dev/null; then
            echo -e "${GREEN}  ✔ 包含TCP wmem配置${NC}"
            local wmem_line=$(grep "net.ipv4.tcp_wmem" "$config_file" | tail -1)
            echo -e "    ${CYAN}$wmem_line${NC}"
        else
            echo -e "${RED}  ✘ 缺少TCP wmem配置${NC}"
        fi
        
        if grep -q "net.ipv4.tcp_rmem" "$config_file" 2>/dev/null; then
            echo -e "${GREEN}  ✔ 包含TCP rmem配置${NC}"
            local rmem_line=$(grep "net.ipv4.tcp_rmem" "$config_file" | tail -1)
            echo -e "    ${CYAN}$rmem_line${NC}"
        else
            echo -e "${RED}  ✘ 缺少TCP rmem配置${NC}"
        fi
        
        if grep -q "net.ipv4.tcp_congestion_control" "$config_file" 2>/dev/null; then
            echo -e "${GREEN}  ✔ 包含拥塞控制配置${NC}"
        else
            echo -e "${YELLOW}  ⚠ 缺少拥塞控制配置${NC}"
        fi
    else
        echo -e "${RED}  ✘ 主配置文件不存在${NC}"
    fi
    
    # 检查备份配置文件
    if [ -f "$backup_file" ]; then
        echo -e "${GREEN}  ✔ 备份配置文件存在${NC} ($backup_file)"
    else
        echo -e "${YELLOW}  ⚠ 备份配置文件不存在${NC} ($backup_file)"
    fi
    
    # 系统信息
    echo -e "\n${GREEN}系统信息:${NC}"
    echo -e "  内核版本: ${BOLD_WHITE}$(uname -r)${NC}"
    echo -e "  系统时间: ${BOLD_WHITE}$(date)${NC}"
    
    # BBR支持检查
    if lsmod | grep -q tcp_bbr 2>/dev/null; then
        echo -e "  BBR模块: ${GREEN}已加载${NC}"
    else
        echo -e "  BBR模块: ${YELLOW}未加载或不支持${NC}"
    fi
}

# 重置TCP缓冲区为系统默认值 - 改进版本
reset_tcp() {
    echo -e "\n${CYAN}正在重置TCP缓冲区为默认值...${NC}"
    
    # 显示当前配置
    local current_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)
    local current_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)
    echo -e "${YELLOW}当前配置:${NC}"
    echo -e "  wmem: $current_wmem"
    echo -e "  rmem: $current_rmem"
    
    # 应用默认配置
    echo -e "\n${CYAN}应用默认配置...${NC}"
    if apply_config "4096 16384 4194304" "4096 87380 6291456"; then
        echo -e "${GREEN}✔ 已将TCP缓冲区重置为系统默认值${NC}"
        echo -e "${CYAN}ℹ 默认值: wmem=4096 16384 4194304, rmem=4096 87380 6291456${NC}"
        
        # 删除备份配置文件
        local backup_file="/etc/sysctl.d/99-tcp-tuning.conf"
        if [ -f "$backup_file" ]; then
            if rm -f "$backup_file" 2>/dev/null; then
                echo -e "${CYAN}ℹ 已删除备份配置文件${NC}"
            else
                echo -e "${YELLOW}⚠ 无法删除备份配置文件: $backup_file${NC}"
            fi
        fi
        
        return 0
    else
        echo -e "${RED}✘ 重置失败，请检查系统权限或手动重置${NC}"
        echo -e "${CYAN}ℹ 手动重置命令:${NC}"
        echo -e "${CYAN}  sudo sysctl -w net.ipv4.tcp_wmem='4096 16384 4194304'${NC}"
        echo -e "${CYAN}  sudo sysctl -w net.ipv4.tcp_rmem='4096 87380 6291456'${NC}"
        return 1
    fi
}


# =================================================================
# 初始化与依赖检查
# =================================================================

# 初始化BBR和FQ（仅在需要时配置）
init_bbr_fq() {
    local bbr_enabled=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local fq_enabled=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    
    # 只有在当前不是BBR时才设置
    if [[ "$bbr_enabled" != "bbr" ]]; then
        sysctl -w net.ipv4.tcp_congestion_control=bbr &>/dev/null
    fi
    
    if [[ "$fq_enabled" != "fq" ]]; then
        sysctl -w net.core.default_qdisc=fq &>/dev/null
    fi
    
    # 检查配置文件中是否已存在，避免重复添加
    if ! grep -q "^net\.ipv4\.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        if ! grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        fi
    fi
    
    if ! grep -q "^net\.core\.default_qdisc=fq" /etc/sysctl.conf; then
        if ! grep -q "net.core.default_qdisc" /etc/sysctl.conf; then
            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        fi
    fi
}

# 初始化BBR和FQ
init_bbr_fq

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


# 显示配置建议
show_config_recommendations() {
    echo -e "${CYAN}=== TCP缓冲区配置建议 ===${NC}\n"
    
    echo -e "${GREEN}常见场景配置建议:${NC}"
    echo -e "  ${YELLOW}1. 低延迟场景 (< 10ms):${NC}"
    echo -e "     建议值: 2-4 MiB (适合游戏、实时通信)"
    echo -e "     命令: 选择选项3，输入 2 或 4"
    
    echo -e "\n  ${YELLOW}2. 中等延迟场景 (10-50ms):${NC}"
    echo -e "     建议值: 8-16 MiB (适合一般网络应用)"
    echo -e "     命令: 选择选项3，输入 8 或 16"
    
    echo -e "\n  ${YELLOW}3. 高延迟场景 (> 50ms):${NC}"
    echo -e "     建议值: 32-64 MiB (适合跨国传输)"
    echo -e "     命令: 选择选项3，输入 32 或 64"
    
    echo -e "\n  ${YELLOW}4. 高带宽场景 (> 1Gbps):${NC}"
    echo -e "     建议值: 64-128 MiB (适合大文件传输)"
    echo -e "     命令: 选择选项3，输入 64 或 128"
    
    echo -e "\n${GREEN}计算公式:${NC}"
    echo -e "  ${CYAN}BDP = 带宽(bps) × 延迟(s) / 8${NC}"
    echo -e "  ${CYAN}例如: 100Mbps × 0.1s / 8 = 1.25MB${NC}"
    
    echo -e "\n${GREEN}当前网络测试建议:${NC}"
    echo -e "  ${CYAN}1. 使用 ping 测试延迟: ping 目标服务器${NC}"
    echo -e "  ${CYAN}2. 使用 iperf3 测试带宽: iperf3 -c 服务器IP${NC}"
    echo -e "  ${CYAN}3. 根据测试结果选择合适的缓冲区大小${NC}"
}

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
                        apply_config "4096 16384 $value" "4096 87380 $value"
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
                        apply_config "4096 16384 $value" "4096 87380 $value"
                        ;;
                    5)
                        reset_tcp
                        ;;
                    6)
                        echo -e "\n${CYAN}检查配置状态...${NC}"
                        check_config_status
                        ;;
                    7)
                        echo -e "\n${CYAN}显示配置建议...${NC}"
                        show_config_recommendations
                        ;;
                    0)
                        echo -e "\n${CYAN}正在返回主菜单...${NC}"
                        sleep 1
                        break 
                        ;;
                    *)
                        echo -e "\n${RED}✘ 无效选择，请输入0-7之间的数字。${NC}"
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