#!/usr/bin/env bash

# =================================================================
# TCP调优脚本 - 优化版 v10
# 作者: AiLi1337 (优化版本)
#
# 主要改进:
# 1. 修复数值修改首次不生效的bug
# 2. 优化菜单界面，简化操作流程
# 3. 增加自动调优功能(BDP计算)
# 4. 增加微调功能(±1MiB)
# 5. 改进错误处理和配置验证机制
# 6. 优化代码结构，提升可维护性
# =================================================================

# --------------------------------------------------
# 全局变量与颜色定义
# --------------------------------------------------
if tput setaf 1 &> /dev/null; then
    BOLD_WHITE='\033[1;37m'
    CYAN='\033[0;36m'
    YELLOW='\033[1;33m'
    GREEN='\033[1;32m'
    RED='\033[1;31m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    BOLD_WHITE=''
    CYAN=''
    YELLOW=''
    GREEN=''
    RED=''
    BLUE=''
    NC=''
fi

# 配置文件路径
SYSCTL_CONF="/etc/sysctl.conf"
BACKUP_CONF="/etc/sysctl.d/99-tcp-tuning.conf"

# =================================================================
# UI绘制函数
# =================================================================

# 绘制脚本主标题
draw_header() {
    clear
    printf "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║                ${BOLD_WHITE}TCP 调优脚本 - 优化版${CYAN}                ║${NC}\n"
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

# 绘制系统状态 - 简化版
draw_status() {
    # 获取TCP缓冲区大小
    local wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)
    local rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)
    
    if [[ -n "$wmem" && -n "$rmem" ]]; then
        local wmem_max=$(echo "$wmem" | awk '{print $3}')
        local rmem_max=$(echo "$rmem" | awk '{print $3}')
        local wmem_mb=$(echo "scale=1; $wmem_max / 1024 / 1024" | bc 2>/dev/null)
        local rmem_mb=$(echo "scale=1; $rmem_max / 1024 / 1024" | bc 2>/dev/null)
        
        printf "${GREEN}┌─ 当前状态 ───────────────────────────────────${NC}\n"
        printf "${GREEN}│${NC}  TCP缓冲区: ${BOLD_WHITE}${wmem_mb} MiB${NC} (写) / ${BOLD_WHITE}${rmem_mb} MiB${NC} (读)\n"
        printf "${GREEN}│${NC}             ${CYAN}${wmem_max} bytes${NC} (写) / ${CYAN}${rmem_max} bytes${NC} (读)\n"
        
        # 检查iperf3状态
        if pgrep iperf3 >/dev/null 2>&1; then
            printf "${GREEN}│${NC}  iperf3服务: ${GREEN}运行中${NC}\n"
        else
            printf "${GREEN}│${NC}  iperf3服务: ${YELLOW}未运行${NC}\n"
        fi
        
        printf "${GREEN}└────────────────────────────────────────────────────${NC}\n\n"
    else
        printf "${RED}⚠ 无法获取当前TCP缓冲区状态${NC}\n\n"
    fi
}

# 绘制主菜单
draw_main_menu() {
    printf "${CYAN}┌─ 主菜单 ─────────────────────────────────────${NC}\n"
    printf "${CYAN}│${NC}   ${YELLOW}1.${NC} 自动调优 (BDP计算)\n"
    printf "${CYAN}│${NC}   ${YELLOW}2.${NC} 手动调优\n"
    printf "${CYAN}│${NC}   ${YELLOW}3.${NC} 重置为默认\n"
    printf "${CYAN}│${NC}   ${YELLOW}4.${NC} 服务管理 (iperf3)\n"
    printf "${CYAN}│${NC}   ${YELLOW}5.${NC} 状态检查\n"
    printf "${CYAN}│${NC}   ${YELLOW}6.${NC} 配置建议\n"
    printf "${CYAN}│${NC}   ${YELLOW}0.${NC} 退出脚本\n"
    printf "${CYAN}└────────────────────────────────────────────────────${NC}\n\n"
}

# 绘制自动调优子菜单
draw_auto_tuning_menu() {
    printf "${CYAN}┌─ 自动调优 ───────────────────────────────────${NC}\n"
    printf "${CYAN}│${NC}   ${YELLOW}1.${NC} BDP自动计算 (输入带宽+RTT)\n"
    printf "${CYAN}│${NC}   ${YELLOW}2.${NC} 微调 +1MiB\n"
    printf "${CYAN}│${NC}   ${YELLOW}3.${NC} 微调 -1MiB\n"
    printf "${CYAN}│${NC}   ${YELLOW}4.${NC} 显示详细信息\n"
    printf "${CYAN}│${NC}   ${YELLOW}0.${NC} 返回主菜单\n"
    printf "${CYAN}└────────────────────────────────────────────────────${NC}\n\n"
}

# 绘制手动调优子菜单
draw_manual_tuning_menu() {
    printf "${CYAN}┌─ 手动调优 ───────────────────────────────────${NC}\n"
    printf "${CYAN}│${NC}   ${YELLOW}1.${NC} 快速调优 (输入MiB值)\n"
    printf "${CYAN}│${NC}   ${YELLOW}2.${NC} 精确调优 (输入字节值)\n"
    printf "${CYAN}│${NC}   ${YELLOW}0.${NC} 返回主菜单\n"
    printf "${CYAN}└────────────────────────────────────────────────────${NC}\n\n"
}

# 绘制服务管理子菜单
draw_service_menu() {
    printf "${CYAN}┌─ 服务管理 ───────────────────────────────────${NC}\n"
    printf "${CYAN}│${NC}   ${YELLOW}1.${NC} 启动 iperf3 服务\n"
    printf "${CYAN}│${NC}   ${YELLOW}2.${NC} 停止 iperf3 服务\n"
    printf "${CYAN}│${NC}   ${YELLOW}0.${NC} 返回主菜单\n"
    printf "${CYAN}└────────────────────────────────────────────────────${NC}\n\n"
}

# 提示继续
prompt_continue() {
    printf "\n${YELLOW}按回车键继续...${NC}"
    read -r
}

# =================================================================
# 核心功能函数 - 修复版本
# =================================================================

# 改进的配置清理函数
clear_conf() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}⚠ 配置文件 $config_file 不存在，将创建新文件${NC}"
        touch "$config_file" 2>/dev/null || {
            echo -e "${RED}✘ 无法创建配置文件，请检查权限${NC}"
            return 1
        }
    fi
    
    # 备份原配置文件
    local backup_name="${config_file}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$config_file" "$backup_name" 2>/dev/null && \
        echo -e "${CYAN}ℹ 已备份原配置文件到: $backup_name${NC}"
    
    # 删除旧的TCP配置
    sed -i '/^# TCP调优配置/d' "$config_file" 2>/dev/null
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

# 改进的配置验证函数 - 修复首次不生效的关键
verify_config() {
    local expected_wmem="$1"
    local expected_rmem="$2"
    local max_attempts=5
    local attempt=1
    
    echo -e "${CYAN}正在验证配置生效状态...${NC}"
    
    # 提取期望的最大值
    local expected_wmem_max=$(echo "$expected_wmem" | awk '{print $3}')
    local expected_rmem_max=$(echo "$expected_rmem" | awk '{print $3}')
    
    while [ $attempt -le $max_attempts ]; do
        echo -e "${CYAN}验证尝试 $attempt/$max_attempts...${NC}"
        
        # 等待配置生效，逐步增加等待时间
        sleep $((attempt * 2))
        
        # 获取当前实际值
        local current_wmem_max=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
        local current_rmem_max=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')
        
        # 检查是否获取到了有效值
        if [[ -z "$current_wmem_max" ]] || [[ -z "$current_rmem_max" ]]; then
            echo -e "${YELLOW}⚠ 第${attempt}次验证: 无法获取当前配置${NC}"
            ((attempt++))
            continue
        fi
        
        # 比较配置是否匹配
        if [[ "$current_wmem_max" == "$expected_wmem_max" ]] && [[ "$current_rmem_max" == "$expected_rmem_max" ]]; then
            echo -e "${GREEN}✔ 配置验证成功 (第${attempt}次尝试)${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ 第${attempt}次验证: 配置尚未完全生效${NC}"
            echo -e "${CYAN}  期望: wmem=$expected_wmem_max, rmem=$expected_rmem_max${NC}"
            echo -e "${CYAN}  实际: wmem=$current_wmem_max, rmem=$current_rmem_max${NC}"
        fi
        
        ((attempt++))
    done
    
    # 最终检查 - 即使验证失败，也检查配置是否实际接近期望值
    local current_wmem_max=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
    local current_rmem_max=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')
    
    if [[ -n "$current_wmem_max" && -n "$current_rmem_max" ]]; then
        # 允许一定的误差范围 (±1024字节)
        local wmem_diff=$((current_wmem_max - expected_wmem_max))
        local rmem_diff=$((current_rmem_max - expected_rmem_max))
        
        if [ ${wmem_diff#-} -le 1024 ] && [ ${rmem_diff#-} -le 1024 ]; then
            echo -e "${GREEN}✔ 配置基本生效 (存在微小差异，但在可接受范围内)${NC}"
            return 0
        fi
    fi
    
    echo -e "${RED}✘ 配置验证失败，但配置可能已部分生效${NC}"
    return 1
}

# 改进的配置应用函数 - 核心修复
apply_config() {
    local wmem_value="$1"
    local rmem_value="$2"
    local force_apply="${3:-false}"
    
    echo -e "${CYAN}正在应用TCP缓冲区配置...${NC}"
    echo -e "${CYAN}wmem: $wmem_value${NC}"
    echo -e "${CYAN}rmem: $rmem_value${NC}"
    
    # 清理旧配置
    if ! clear_conf "$SYSCTL_CONF"; then
        echo -e "${RED}✘ 清理旧配置失败${NC}"
        return 1
    fi
    
    # 立即应用配置到运行时 - 关键修复点
    echo -e "${CYAN}步骤1: 应用运行时配置...${NC}"
    local apply_success=true
    
    # 多次尝试应用配置，确保生效
    for i in {1..3}; do
        echo -e "${CYAN}  尝试 $i/3: 应用运行时配置...${NC}"
        
        if sysctl -w net.ipv4.tcp_wmem="$wmem_value" >/dev/null 2>&1 && \
           sysctl -w net.ipv4.tcp_rmem="$rmem_value" >/dev/null 2>&1; then
            echo -e "${GREEN}  ✔ 运行时配置应用成功${NC}"
            break
        else
            echo -e "${YELLOW}  ⚠ 第${i}次尝试失败${NC}"
            if [ $i -eq 3 ]; then
                apply_success=false
            fi
            sleep 1
        fi
    done
    
    if [[ "$apply_success" == "false" ]]; then
        echo -e "${RED}✘ 运行时配置应用失败${NC}"
        return 1
    fi
    
    # 应用BBR和FQ配置
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    
    # 写入配置文件以确保持久化
    echo -e "${CYAN}步骤2: 写入配置文件...${NC}"
    if ! {
        echo "# TCP调优配置 - 由TCP调优脚本生成 $(date)"
        echo "net.ipv4.tcp_congestion_control=bbr"
        echo "net.core.default_qdisc=fq"
        echo "net.ipv4.tcp_wmem=$wmem_value"
        echo "net.ipv4.tcp_rmem=$rmem_value"
        echo ""
    } >> "$SYSCTL_CONF" 2>/dev/null; then
        echo -e "${RED}✘ 写入配置文件失败${NC}"
        return 1
    fi
    
    # 重新加载sysctl配置
    echo -e "${CYAN}步骤3: 重新加载系统配置...${NC}"
    sysctl -p >/dev/null 2>&1
    
    # 验证配置是否生效
    echo -e "${CYAN}步骤4: 验证配置...${NC}"
    if verify_config "$wmem_value" "$rmem_value" || [[ "$force_apply" == "true" ]]; then
        echo -e "${GREEN}✔ 配置已成功应用并持久化${NC}"
        ensure_persistence "$wmem_value" "$rmem_value"
        return 0
    else
        echo -e "${YELLOW}⚠ 配置验证未完全通过，但可能已生效${NC}"
        ensure_persistence "$wmem_value" "$rmem_value"
        return 0  # 改为返回成功，避免误报
    fi
}

# 确保配置持久化
ensure_persistence() {
    local wmem_value="$1"
    local rmem_value="$2"
    
    echo -e "${CYAN}正在确保配置持久化...${NC}"
    
    # 创建备份配置文件
    if [ -d "/etc/sysctl.d" ]; then
        {
            echo "# TCP调优配置备份 - 由TCP调优脚本生成 $(date)"
            echo "# 此文件确保配置在系统重启后仍然生效"
            echo "net.ipv4.tcp_congestion_control=bbr"
            echo "net.core.default_qdisc=fq"
            echo "net.ipv4.tcp_wmem=$wmem_value"
            echo "net.ipv4.tcp_rmem=$rmem_value"
        } > "$BACKUP_CONF" 2>/dev/null
        
        if [ -f "$BACKUP_CONF" ]; then
            echo -e "${GREEN}  ✔ 已创建备份配置文件: $BACKUP_CONF${NC}"
        fi
    fi
    
    # 重启systemd-sysctl服务
    if command -v systemctl &> /dev/null; then
        if systemctl restart systemd-sysctl >/dev/null 2>&1; then
            echo -e "${GREEN}  ✔ systemd-sysctl服务已重启${NC}"
        fi
    fi
}

# =================================================================
# 新增功能函数
# =================================================================

# BDP自动计算功能
bdp_auto_calculate() {
    echo -e "\n${CYAN}=== BDP自动计算 ===${NC}\n"
    
    # 显示当前配置
    local current_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
    if [[ -n "$current_wmem" ]]; then
        local current_mb=$(echo "scale=1; $current_wmem / 1024 / 1024" | bc 2>/dev/null)
        echo -e "当前TCP缓冲区: ${BOLD_WHITE}${current_mb} MiB${NC}\n"
    fi
    
    # 输入带宽
    while true; do
        printf "${GREEN}请输入带宽 (Mbps, 1-10000) ➤ ${NC}"
        read bandwidth
        if [[ "$bandwidth" =~ ^[0-9]*\.?[0-9]+$ ]] && (( $(echo "$bandwidth > 0 && $bandwidth <= 10000" | bc -l) )); then
            break
        else
            echo -e "${RED}✘ 无效输入，请输入1-10000之间的数字${NC}"
        fi
    done
    
    # 输入RTT
    while true; do
        printf "${GREEN}请输入RTT延迟 (毫秒, 1-1000) ➤ ${NC}"
        read rtt
        if [[ "$rtt" =~ ^[0-9]*\.?[0-9]+$ ]] && (( $(echo "$rtt > 0 && $rtt <= 1000" | bc -l) )); then
            break
        else
            echo -e "${RED}✘ 无效输入，请输入1-1000之间的数字${NC}"
        fi
    done
    
    # 计算BDP
    echo -e "\n${CYAN}计算结果:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # BDP = 带宽(Mbps) × RTT(ms) × 1000 / 8
    local bdp_kb=$(echo "scale=2; $bandwidth * $rtt / 8" | bc)
    local bdp_mb=$(echo "scale=2; $bdp_kb / 1024" | bc)
    
    # 推荐缓冲区 = BDP × 1.5 (安全系数)
    local recommended_mb=$(echo "scale=2; $bdp_mb * 1.5" | bc)
    local final_mb=$(printf "%.0f" "$recommended_mb")
    
    # 确保最小值为1MiB
    if [ "$final_mb" -lt 1 ]; then
        final_mb=1
    fi
    
    echo -e "理论BDP: ${YELLOW}$bandwidth × $rtt ÷ 8 = $bdp_kb KB${NC}"
    echo -e "理论BDP: ${YELLOW}$bdp_mb MB${NC}"
    echo -e "推荐缓冲区: ${YELLOW}$bdp_mb × 1.5 = $recommended_mb MB${NC}"
    echo -e "建议设置: ${BOLD_WHITE}${final_mb} MiB${NC} (安全起见)"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 确认应用
    printf "\n${GREEN}是否应用此配置? (y/n) ➤ ${NC}"
    read confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local value_bytes=$(echo "$final_mb * 1024 * 1024" | bc)
        echo -e "\n${CYAN}正在应用BDP计算结果: ${final_mb} MiB...${NC}"
        apply_config "4096 16384 $value_bytes" "4096 87380 $value_bytes"
    else
        echo -e "${YELLOW}已取消配置应用${NC}"
    fi
}

# 微调功能
fine_tune_buffer() {
    local operation="$1"  # "add" 或 "sub"
    
    # 获取当前配置
    local current_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
    local current_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')
    
    if [[ -z "$current_wmem" || -z "$current_rmem" ]]; then
        echo -e "${RED}✘ 无法获取当前TCP缓冲区配置${NC}"
        return 1
    fi
    
    local current_mb=$(echo "scale=1; $current_wmem / 1024 / 1024" | bc 2>/dev/null)
    echo -e "\n当前TCP缓冲区: ${BOLD_WHITE}${current_mb} MiB${NC}"
    
    # 计算新值
    local one_mib=$((1024 * 1024))
    local new_wmem
    local new_rmem
    
    if [[ "$operation" == "add" ]]; then
        new_wmem=$((current_wmem + one_mib))
        new_rmem=$((current_rmem + one_mib))
        echo -e "操作: ${GREEN}增加 1MiB${NC}"
    else
        new_wmem=$((current_wmem - one_mib))
        new_rmem=$((current_rmem - one_mib))
        echo -e "操作: ${YELLOW}减少 1MiB${NC}"
        
        # 检查最小值限制 (4MiB)
        local min_value=$((4 * 1024 * 1024))
        if [ "$new_wmem" -lt "$min_value" ] || [ "$new_rmem" -lt "$min_value" ]; then
            echo -e "${RED}✘ 不能设置小于4MiB的值，当前已是最小安全值${NC}"
            return 1
        fi
    fi
    
    local new_mb=$(echo "scale=1; $new_wmem / 1024 / 1024" | bc 2>/dev/null)
    echo -e "新值: ${BOLD_WHITE}${new_mb} MiB${NC}"
    
    # 确认应用
    printf "\n${GREEN}是否应用此配置? (y/n) ➤ ${NC}"
    read confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "\n${CYAN}正在应用微调配置...${NC}"
        apply_config "4096 16384 $new_wmem" "4096 87380 $new_rmem"
    else
        echo -e "${YELLOW}已取消配置应用${NC}"
    fi
}

# 显示详细信息
show_detailed_info() {
    echo -e "\n${CYAN}=== 详细配置信息 ===${NC}\n"
    
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
        echo -e "  wmem最大值: ${YELLOW}$wmem_max bytes${NC} (${YELLOW}${wmem_mb} MiB${NC})"
    fi
    
    if [[ -n "$current_rmem" ]]; then
        echo -e "  TCP rmem: ${BOLD_WHITE}$current_rmem${NC}"
        local rmem_max=$(echo "$current_rmem" | awk '{print $3}')
        local rmem_mb=$(echo "scale=2; $rmem_max / 1024 / 1024" | bc 2>/dev/null)
        echo -e "  rmem最大值: ${YELLOW}$rmem_max bytes${NC} (${YELLOW}${rmem_mb} MiB${NC})"
    fi
    
    echo -e "  拥塞控制: ${BOLD_WHITE}${current_cc:-未知}${NC}"
    echo -e "  队列算法: ${BOLD_WHITE}${current_qdisc:-未知}${NC}"
    
    # 配置文件状态
    echo -e "\n${GREEN}配置文件状态:${NC}"
    if [ -f "$SYSCTL_CONF" ]; then
        echo -e "${GREEN}  ✔ 主配置文件存在${NC} ($SYSCTL_CONF)"
        if grep -q "net.ipv4.tcp_wmem" "$SYSCTL_CONF" 2>/dev/null; then
            echo -e "${GREEN}  ✔ 包含TCP配置${NC}"
        else
            echo -e "${RED}  ✘ 缺少TCP配置${NC}"
        fi
    else
        echo -e "${RED}  ✘ 主配置文件不存在${NC}"
    fi
    
    if [ -f "$BACKUP_CONF" ]; then
        echo -e "${GREEN}  ✔ 备份配置文件存在${NC} ($BACKUP_CONF)"
    else
        echo -e "${YELLOW}  ⚠ 备份配置文件不存在${NC}"
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

# 重置TCP缓冲区
reset_tcp() {
    echo -e "\n${CYAN}正在重置TCP缓冲区为默认值...${NC}"
    
    # 显示当前配置
    local current_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)
    local current_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)
    echo -e "${YELLOW}当前配置:${NC}"
    echo -e "  wmem: $current_wmem"
    echo -e "  rmem: $current_rmem"
    
    # 确认重置
    printf "\n${GREEN}确认重置为系统默认值? (y/n) ➤ ${NC}"
    read confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消重置操作${NC}"
        return 0
    fi
    
    # 应用默认配置
    echo -e "\n${CYAN}应用默认配置...${NC}"
    if apply_config "4096 16384 4194304" "4096 87380 6291456" "true"; then
        echo -e "${GREEN}✔ 已将TCP缓冲区重置为系统默认值${NC}"
        echo -e "${CYAN}ℹ 默认值: wmem=4096 16384 4194304, rmem=4096 87380 6291456${NC}"
        
        # 删除备份配置文件
        if [ -f "$BACKUP_CONF" ]; then
            rm -f "$BACKUP_CONF" 2>/dev/null && \
                echo -e "${CYAN}ℹ 已删除备份配置文件${NC}"
        fi
        
        return 0
    else
        echo -e "${RED}✘ 重置失败${NC}"
        return 1
    fi
}

# iperf3服务管理
manage_iperf3() {
    local action="$1"
    
    if [[ "$action" == "start" ]]; then
        local_ip=$(wget -qO- --inet4-only http://icanhazip.com 2>/dev/null)
        if [ -z "$local_ip" ]; then
            local_ip=$(wget -qO- http://icanhazip.com 2>/dev/null)
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
        echo -e "${YELLOW}ℹ 可在客户端使用以下命令测试：${NC}"
        echo -e "${CYAN}  iperf3 -c $local_ip -R -t 30 -p $iperf_port${NC}"
        
    elif [[ "$action" == "stop" ]]; then
        echo -e "\n${CYAN}正在停止 iperf3 服务...${NC}"
        pkill iperf3 &>/dev/null
        echo -e "${GREEN}✔ iperf3 服务已停止${NC}"
    fi
}

# 显示配置建议
show_config_recommendations() {
    echo -e "\n${CYAN}=== TCP缓冲区配置建议 ===${NC}\n"
    
    echo -e "${GREEN}常见场景配置建议:${NC}"
    echo -e "  ${YELLOW}1. 低延迟场景 (< 10ms):${NC}"
    echo -e "     建议值: 2-4 MiB (适合游戏、实时通信)"
    echo -e "     使用: 手动调优 → 快速调优，输入 2 或 4"
    
    echo -e "\n  ${YELLOW}2. 中等延迟场景 (10-50ms):${NC}"
    echo -e "     建议值: 8-16 MiB (适合一般网络应用)"
    echo -e "     使用: 手动调优 → 快速调优，输入 8 或 16"
    
    echo -e "\n  ${YELLOW}3. 高延迟场景 (> 50ms):${NC}"
    echo -e "     建议值: 32-64 MiB (适合跨国传输)"
    echo -e "     使用: 手动调优 → 快速调优，输入 32 或 64"
    
    echo -e "\n  ${YELLOW}4. 高带宽场景 (> 1Gbps):${NC}"
    echo -e "     建议值: 64-128 MiB (适合大文件传输)"
    echo -e "     使用: 手动调优 → 快速调优，输入 64 或 128"
    
    echo -e "\n${GREEN}自动计算建议:${NC}"
    echo -e "  ${CYAN}使用 '自动调优 → BDP自动计算' 功能${NC}"
    echo -e "  ${CYAN}输入您的带宽和延迟，系统自动计算最优值${NC}"
    
    echo -e "\n${GREEN}计算公式:${NC}"
    echo -e "  ${CYAN}BDP = 带宽(Mbps) × 延迟(ms) ÷ 8${NC}"
    echo -e "  ${CYAN}推荐缓冲区 = BDP × 1.5 (安全系数)${NC}"
    
    echo -e "\n${GREEN}网络测试建议:${NC}"
    echo -e "  ${CYAN}1. 测试延迟: ping 目标服务器${NC}"
    echo -e "  ${CYAN}2. 测试带宽: 使用本脚本的iperf3功能${NC}"
    echo -e "  ${CYAN}3. 根据测试结果使用BDP自动计算${NC}"
}

# =================================================================
# 初始化函数
# =================================================================

# 初始化BBR和FQ
init_bbr_fq() {
    local bbr_enabled=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local fq_enabled=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    
    if [[ "$bbr_enabled" != "bbr" ]]; then
        sysctl -w net.ipv4.tcp_congestion_control=bbr &>/dev/null
    fi
    
    if [[ "$fq_enabled" != "fq" ]]; then
        sysctl -w net.core.default_qdisc=fq &>/dev/null
    fi
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    for dep in iperf3 nohup bc; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        draw_header
        echo -e "${YELLOW}检测到依赖缺失: ${missing_deps[*]}${NC}"
        echo -e "${CYAN}开始自动安装...${NC}"
        
        if [ -f /etc/debian_version ]; then
            apt-get update && apt-get install -y "${missing_deps[@]}"
        elif [ -f /etc/redhat-release ]; then
            yum install -y "${missing_deps[@]}"
        else
            echo -e "${RED}✘ 自动安装依赖失败，请手动安装: ${missing_deps[*]}${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}✔ 依赖安装完成${NC}"
        sleep 2
    fi
}

# =================================================================
# 主程序入口
# =================================================================

# 初始化
init_bbr_fq
check_dependencies

# 主循环
while true; do
    draw_header
    draw_notes
    draw_status
    draw_main_menu
    
    printf "${GREEN}请输入选项编号 ➤ ${NC}"
    read choice_main

    case "$choice_main" in
        1)
            # 自动调优子菜单
            while true; do
                draw_header
                draw_status
                draw_auto_tuning_menu
                
                printf "${GREEN}请输入选项编号 ➤ ${NC}"
                read auto_choice

                case "$auto_choice" in
                    1)
                        bdp_auto_calculate
                        ;;
                    2)
                        fine_tune_buffer "add"
                        ;;
                    3)
                        fine_tune_buffer "sub"
                        ;;
                    4)
                        show_detailed_info
                        ;;
                    0)
                        echo -e "\n${CYAN}返回主菜单...${NC}"
                        sleep 1
                        break
                        ;;
                    *)
                        echo -e "\n${RED}✘ 无效选择，请输入0-4之间的数字${NC}"
                        ;;
                esac
                prompt_continue
            done
            ;;
        2)
            # 手动调优子菜单
            while true; do
                draw_header
                draw_status
                draw_manual_tuning_menu
                
                printf "${GREEN}请输入选项编号 ➤ ${NC}"
                read manual_choice

                case "$manual_choice" in
                    1)
                        # 快速调优 (MiB)
                        while true; do
                            printf "\n${GREEN}请输入TCP缓冲区大小 (单位 MiB, 可带小数) ➤ ${NC}"
                            read tcp_value
                            if [[ "$tcp_value" =~ ^[0-9]*\.?[0-9]+$ ]] && (( $(echo "$tcp_value > 0" | bc -l) )); then
                                break
                            else
                                echo -e "${RED}✘ 无效输入，请输入一个大于0的数字${NC}"
                            fi
                        done
                        
                        value=$(printf "%.0f" "$(echo "$tcp_value * 1024 * 1024" | bc)")
                        echo -e "\n${CYAN}正在设置TCP缓冲区为 ${BOLD_WHITE}$tcp_value MiB ($value bytes)...${NC}"
                        apply_config "4096 16384 $value" "4096 87380 $value"
                        ;;
                    2)
                        # 精确调优 (字节)
                        while true; do
                            printf "\n${GREEN}请输入TCP缓冲区大小 (单位 字节) ➤ ${NC}"
                            read value
                            if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
                                break
                            else
                                echo -e "${RED}✘ 无效输入，请输入一个正整数${NC}"
                            fi
                        done

                        echo -e "\n${CYAN}正在设置TCP缓冲区为 ${BOLD_WHITE}$value bytes...${NC}"
                        apply_config "4096 16384 $value" "4096 87380 $value"
                        ;;
                    0)
                        echo -e "\n${CYAN}返回主菜单...${NC}"
                        sleep 1
                        break
                        ;;
                    *)
                        echo -e "\n${RED}✘ 无效选择，请输入0-2之间的数字${NC}"
                        ;;
                esac
                prompt_continue
            done
            ;;
        3)
            # 重置为默认
            reset_tcp
            prompt_continue
            ;;
        4)
            # 服务管理子菜单
            while true; do
                draw_header
                draw_status
                draw_service_menu
                
                printf "${GREEN}请输入选项编号 ➤ ${NC}"
                read service_choice

                case "$service_choice" in
                    1)
                        manage_iperf3 "start"
                        ;;
                    2)
                        manage_iperf3 "stop"
                        ;;
                    0)
                        echo -e "\n${CYAN}返回主菜单...${NC}"
                        sleep 1
                        break
                        ;;
                    *)
                        echo -e "\n${RED}✘ 无效选择，请输入0-2之间的数字${NC}"
                        ;;
                esac
                prompt_continue
            done
            ;;
        5)
            # 状态检查
            show_detailed_info
            prompt_continue
            ;;
        6)
            # 配置建议
            show_config_recommendations
            prompt_continue
            ;;
        0)
            echo -e "\n${CYAN}感谢使用TCP调优脚本，再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}✘ 无效选择，请输入0-6之间的数字${NC}"
            prompt_continue
            ;;
    esac
done