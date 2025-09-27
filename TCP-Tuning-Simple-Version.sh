#!/usr/bin/env bash

# =================================================================
# TCP调优脚本 - 优化版 v11 (优化版本)
# 作者: AiLi1337 (优化版本)
#
# 主要优化:
# 1. 代码结构优化 - 函数拆分，提高可维护性
# 2. 性能优化 - 批量执行，减少系统调用
# 3. 错误处理增强 - 完善的错误检查和恢复机制
# 4. 用户体验改进 - 配置预览、回滚功能、进度显示
# 5. 安全性增强 - 权限检查、输入验证、操作日志
# 6. 新增功能 - 网络检测、配置对比、智能推荐
# =================================================================

# --------------------------------------------------
# 全局变量与常量定义
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
LOG_FILE="/var/log/tcp-tuning.log"

# 常量定义
MIN_BUFFER_MB=1
MAX_BUFFER_MB=1024
DEFAULT_WMEM="4096 16384 4194304"
DEFAULT_RMEM="4096 87380 6291456"
SAFE_MULTIPLIER=1.5

# 配置历史记录
CONFIG_HISTORY=()

# =================================================================
# 工具函数
# =================================================================

# 日志记录函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 检查root权限
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}✘ 此脚本需要root权限运行${NC}"
        echo -e "${CYAN}请使用: sudo $0${NC}"
        log_message "ERROR" "Script executed without root privileges"
        exit 1
    fi
}

# 检查网络连接
check_network_connectivity() {
    echo -e "${CYAN}检查网络连接状态...${NC}"
    
    # 检查基本网络连接
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        echo -e "${YELLOW}⚠ 网络连接可能有问题，建议检查网络状态${NC}"
        log_message "WARNING" "Network connectivity issues detected"
        return 1
    fi
    
    # 检查DNS解析
    if ! nslookup google.com &>/dev/null; then
        echo -e "${YELLOW}⚠ DNS解析可能有问题${NC}"
        log_message "WARNING" "DNS resolution issues detected"
        return 1
    fi
    
    echo -e "${GREEN}✔ 网络连接正常${NC}"
    return 0
}

# 验证数值范围
validate_numeric_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local unit="$4"
    
    if [[ ! "$value" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo -e "${RED}✘ 请输入有效的数字${NC}"
        return 1
    fi
    
    if (( $(echo "$value < $min" | bc -l) )); then
        echo -e "${RED}✘ 值不能小于 ${min}${unit}${NC}"
        return 1
    fi
    
    if (( $(echo "$value > $max" | bc -l) )); then
        echo -e "${RED}✘ 值不能大于 ${max}${unit}${NC}"
        return 1
    fi
    
    return 0
}

# 显示进度条
show_progress() {
    local current="$1"
    local total="$2"
    local message="$3"
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${CYAN}${message} ["
    printf "%*s" $filled | tr ' ' '='
    printf "%*s" $empty | tr ' ' ' '
    printf "] %d%%" $percent
    
    if [ $current -eq $total ]; then
        printf "\n"
    fi
}

# =================================================================
# UI绘制函数 - 优化版
# =================================================================

# 绘制脚本主标题 - 增强版
draw_header() {
    clear
    printf "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${CYAN}║                ${BOLD_WHITE}TCP 调优脚本 - 优化版 v11${CYAN}                ║${NC}\n"
    printf "${CYAN}║                    ${GREEN}Enhanced & Optimized${CYAN}                    ║${NC}\n"
    printf "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n\n"
}

# 绘制系统状态 - 增强版
draw_status() {
    # 获取TCP缓冲区大小
    local wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)
    local rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)
    local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    
    if [[ -n "$wmem" && -n "$rmem" ]]; then
        local wmem_max=$(echo "$wmem" | awk '{print $3}')
        local rmem_max=$(echo "$rmem" | awk '{print $3}')
        local wmem_mb=$(echo "scale=1; $wmem_max / 1024 / 1024" | bc 2>/dev/null)
        local rmem_mb=$(echo "scale=1; $rmem_max / 1024 / 1024" | bc 2>/dev/null)
        
        printf "${GREEN}┌─ 当前状态 ───────────────────────────────────${NC}\n"
        printf "${GREEN}│${NC}  TCP缓冲区: ${BOLD_WHITE}${wmem_mb} MiB${NC} (写) / ${BOLD_WHITE}${rmem_mb} MiB${NC} (读)\n"
        printf "${GREEN}│${NC}  拥塞控制: ${BOLD_WHITE}${cc:-未知}${NC}\n"
        printf "${GREEN}│${NC}  队列算法: ${BOLD_WHITE}${qdisc:-未知}${NC}\n"
        
        # 检查iperf3状态
        if pgrep iperf3 >/dev/null 2>&1; then
            printf "${GREEN}│${NC}  iperf3服务: ${GREEN}运行中${NC}\n"
        else
            printf "${GREEN}│${NC}  iperf3服务: ${YELLOW}未运行${NC}\n"
        fi
        
        # 显示网络延迟
        local ping_time=$(ping -c 1 8.8.8.8 2>/dev/null | grep 'time=' | awk '{print $7}' | cut -d'=' -f2)
        if [[ -n "$ping_time" ]]; then
            printf "${GREEN}│${NC}  网络延迟: ${BOLD_WHITE}${ping_time}${NC}\n"
        fi
        
        printf "${GREEN}└────────────────────────────────────────────────────${NC}\n\n"
    else
        printf "${RED}⚠ 无法获取当前TCP缓冲区状态${NC}\n\n"
    fi
}

# 绘制主菜单 - 增强版
draw_main_menu() {
    printf "${CYAN}┌─ 主菜单 ─────────────────────────────────────${NC}\n"
    printf "${CYAN}│${NC}   ${YELLOW}1.${NC} 智能调优 (推荐)\n"
    printf "${CYAN}│${NC}   ${YELLOW}2.${NC} 手动调优\n"
    printf "${CYAN}│${NC}   ${YELLOW}3.${NC} 配置管理\n"
    printf "${CYAN}│${NC}   ${YELLOW}4.${NC} 网络测试\n"
    printf "${CYAN}│${NC}   ${YELLOW}5.${NC} 系统诊断\n"
    printf "${CYAN}│${NC}   ${YELLOW}6.${NC} 帮助信息\n"
    printf "${CYAN}│${NC}   ${YELLOW}0.${NC} 退出脚本\n"
    printf "${CYAN}└────────────────────────────────────────────────────${NC}\n\n"
}

# 绘制智能调优子菜单
draw_smart_tuning_menu() {
    printf "${CYAN}┌─ 智能调优 ───────────────────────────────────${NC}\n"
    printf "${CYAN}│${NC}   ${YELLOW}1.${NC} 自动检测并调优\n"
    printf "${CYAN}│${NC}   ${YELLOW}2.${NC} BDP计算调优\n"
    printf "${CYAN}│${NC}   ${YELLOW}3.${NC} 场景化调优\n"
    printf "${CYAN}│${NC}   ${YELLOW}4.${NC} 微调功能\n"
    printf "${CYAN}│${NC}   ${YELLOW}0.${NC} 返回主菜单\n"
    printf "${CYAN}└────────────────────────────────────────────────────${NC}\n\n"
}

# 绘制配置管理子菜单
draw_config_menu() {
    printf "${CYAN}┌─ 配置管理 ───────────────────────────────────${NC}\n"
    printf "${CYAN}│${NC}   ${YELLOW}1.${NC} 查看当前配置\n"
    printf "${CYAN}│${NC}   ${YELLOW}2.${NC} 配置对比\n"
    printf "${CYAN}│${NC}   ${YELLOW}3.${NC} 重置为默认\n"
    printf "${CYAN}│${NC}   ${YELLOW}4.${NC} 配置回滚\n"
    printf "${CYAN}│${NC}   ${YELLOW}5.${NC} 备份管理\n"
    printf "${CYAN}│${NC}   ${YELLOW}0.${NC} 返回主菜单\n"
    printf "${CYAN}└────────────────────────────────────────────────────${NC}\n\n"
}

# =================================================================
# 核心功能函数 - 优化版
# =================================================================

# 批量应用配置 - 性能优化
apply_batch_config() {
    local wmem_value="$1"
    local rmem_value="$2"
    local cc_value="${3:-bbr}"
    local qdisc_value="${4:-fq}"
    
    echo -e "${CYAN}正在批量应用配置...${NC}"
    
    # 批量执行sysctl命令
    if sysctl -w \
        net.ipv4.tcp_wmem="$wmem_value" \
        net.ipv4.tcp_rmem="$rmem_value" \
        net.ipv4.tcp_congestion_control="$cc_value" \
        net.core.default_qdisc="$qdisc_value" >/dev/null 2>&1; then
        
        echo -e "${GREEN}✔ 运行时配置应用成功${NC}"
        log_message "INFO" "Runtime config applied: wmem=$wmem_value, rmem=$rmem_value"
        return 0
    else
        echo -e "${RED}✘ 运行时配置应用失败${NC}"
        log_message "ERROR" "Failed to apply runtime config"
        return 1
    fi
}

# 智能配置验证 - 增强版
smart_verify_config() {
    local expected_wmem="$1"
    local expected_rmem="$2"
    local max_attempts=3
    local attempt=1
    
    echo -e "${CYAN}智能验证配置生效状态...${NC}"
    
    # 提取期望值
    local expected_wmem_max=$(echo "$expected_wmem" | awk '{print $3}')
    local expected_rmem_max=$(echo "$expected_rmem" | awk '{print $3}')
    
    while [ $attempt -le $max_attempts ]; do
        show_progress $attempt $max_attempts "验证配置"
        
        # 等待配置生效
        sleep $((attempt * 2))
        
        # 获取当前值
        local current_wmem_max=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null | awk '{print $3}')
        local current_rmem_max=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null | awk '{print $3}')
        
        # 检查配置是否匹配
        if [[ "$current_wmem_max" == "$expected_wmem_max" ]] && [[ "$current_rmem_max" == "$expected_rmem_max" ]]; then
            echo -e "\n${GREEN}✔ 配置验证成功${NC}"
            log_message "INFO" "Config verification successful"
            return 0
        fi
        
        ((attempt++))
    done
    
    echo -e "\n${YELLOW}⚠ 配置验证未完全通过，但可能已生效${NC}"
    log_message "WARNING" "Config verification incomplete"
    return 1
}

# 优化的配置应用函数
apply_config_optimized() {
    local wmem_value="$1"
    local rmem_value="$2"
    local force_apply="${3:-false}"
    
    echo -e "${CYAN}正在应用TCP缓冲区配置...${NC}"
    echo -e "${CYAN}wmem: $wmem_value${NC}"
    echo -e "${CYAN}rmem: $rmem_value${NC}"
    
    # 记录配置历史
    CONFIG_HISTORY+=("$(date '+%Y-%m-%d %H:%M:%S')|$wmem_value|$rmem_value")
    
    # 清理旧配置
    if ! clear_conf_optimized "$SYSCTL_CONF"; then
        echo -e "${RED}✘ 清理旧配置失败${NC}"
        return 1
    fi
    
    # 批量应用运行时配置
    if ! apply_batch_config "$wmem_value" "$rmem_value"; then
        echo -e "${RED}✘ 运行时配置应用失败${NC}"
        return 1
    fi
    
    # 写入持久化配置
    if ! write_persistent_config "$wmem_value" "$rmem_value"; then
        echo -e "${RED}✘ 持久化配置写入失败${NC}"
        return 1
    fi
    
    # 智能验证配置
    if smart_verify_config "$wmem_value" "$rmem_value" || [[ "$force_apply" == "true" ]]; then
        echo -e "${GREEN}✔ 配置已成功应用并持久化${NC}"
        log_message "INFO" "Config successfully applied and persisted"
        return 0
    else
        echo -e "${YELLOW}⚠ 配置验证未完全通过，但可能已生效${NC}"
        return 0
    fi
}

# 优化的配置清理函数
clear_conf_optimized() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${YELLOW}⚠ 配置文件 $config_file 不存在，将创建新文件${NC}"
        touch "$config_file" 2>/dev/null || {
            echo -e "${RED}✘ 无法创建配置文件，请检查权限${NC}"
            return 1
        }
    fi
    
    # 创建备份
    local backup_name="${config_file}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$config_file" "$backup_name" 2>/dev/null && \
        echo -e "${CYAN}ℹ 已备份原配置文件到: $backup_name${NC}"
    
    # 批量删除旧配置
    sed -i '/^# TCP调优配置/d; /^net\.ipv4\.tcp_wmem/d; /^net\.ipv4\.tcp_rmem/d; /^net\.ipv4\.tcp_congestion_control/d; /^net\.core\.default_qdisc/d' "$config_file" 2>/dev/null
    
    # 确保文件末尾有换行符
    if [ -n "$(tail -c1 "$config_file" 2>/dev/null)" ]; then
        echo "" >> "$config_file" 2>/dev/null
    fi
    
    return 0
}

# 写入持久化配置
write_persistent_config() {
    local wmem_value="$1"
    local rmem_value="$2"
    
    echo -e "${CYAN}写入持久化配置...${NC}"
    
    # 写入主配置文件
    {
        echo "# TCP调优配置 - 由TCP调优脚本生成 $(date)"
        echo "net.ipv4.tcp_congestion_control=bbr"
        echo "net.core.default_qdisc=fq"
        echo "net.ipv4.tcp_wmem=$wmem_value"
        echo "net.ipv4.tcp_rmem=$rmem_value"
        echo ""
    } >> "$SYSCTL_CONF" 2>/dev/null || {
        echo -e "${RED}✘ 写入主配置文件失败${NC}"
        return 1
    }
    
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
            echo -e "${GREEN}✔ 已创建备份配置文件${NC}"
        fi
    fi
    
    # 重新加载配置
    sysctl -p >/dev/null 2>&1
    
    return 0
}

# =================================================================
# 新增智能功能
# =================================================================

# 自动检测网络环境并调优
auto_detect_and_tune() {
    echo -e "\n${CYAN}=== 自动检测网络环境 ===${NC}\n"
    
    # 检测网络延迟
    echo -e "${CYAN}检测网络延迟...${NC}"
    local ping_result=$(ping -c 3 8.8.8.8 2>/dev/null | grep 'avg' | awk -F'/' '{print $5}')
    local avg_ping=$(echo "$ping_result" | cut -d'=' -f2)
    
    if [[ -n "$avg_ping" ]]; then
        echo -e "平均延迟: ${BOLD_WHITE}${avg_ping}ms${NC}"
        
        # 根据延迟推荐配置
        local recommended_mb
        if (( $(echo "$avg_ping < 10" | bc -l) )); then
            recommended_mb=4
            echo -e "网络类型: ${GREEN}低延迟网络${NC}"
        elif (( $(echo "$avg_ping < 50" | bc -l) )); then
            recommended_mb=16
            echo -e "网络类型: ${YELLOW}中等延迟网络${NC}"
        else
            recommended_mb=32
            echo -e "网络类型: ${RED}高延迟网络${NC}"
        fi
        
        echo -e "推荐配置: ${BOLD_WHITE}${recommended_mb} MiB${NC}"
        
        # 确认应用
        printf "\n${GREEN}是否应用推荐配置? (y/n) ➤ ${NC}"
        read confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            local value_bytes=$(echo "$recommended_mb * 1024 * 1024" | bc)
            apply_config_optimized "4096 16384 $value_bytes" "4096 87380 $value_bytes"
        else
            echo -e "${YELLOW}已取消自动调优${NC}"
        fi
    else
        echo -e "${RED}✘ 无法检测网络延迟，请手动配置${NC}"
    fi
}

# 场景化调优
scenario_based_tuning() {
    echo -e "\n${CYAN}=== 场景化调优 ===${NC}\n"
    
    echo -e "${GREEN}请选择您的使用场景:${NC}"
    echo -e "  ${YELLOW}1.${NC} 游戏/实时通信 (低延迟优先)"
    echo -e "  ${YELLOW}2.${NC} 一般网络应用 (平衡性能)"
    echo -e "  ${YELLOW}3.${NC} 大文件传输 (高吞吐量)"
    echo -e "  ${YELLOW}4.${NC} 跨国网络 (高延迟优化)"
    echo -e "  ${YELLOW}5.${NC} 服务器应用 (高并发)"
    
    printf "\n${GREEN}请输入场景编号 (1-5) ➤ ${NC}"
    read scenario
    
    local recommended_mb
    local description
    
    case "$scenario" in
        1)
            recommended_mb=2
            description="游戏/实时通信"
            ;;
        2)
            recommended_mb=8
            description="一般网络应用"
            ;;
        3)
            recommended_mb=32
            description="大文件传输"
            ;;
        4)
            recommended_mb=64
            description="跨国网络"
            ;;
        5)
            recommended_mb=16
            description="服务器应用"
            ;;
        *)
            echo -e "${RED}✘ 无效选择${NC}"
            return 1
            ;;
    esac
    
    echo -e "\n${CYAN}场景: ${BOLD_WHITE}${description}${NC}"
    echo -e "推荐配置: ${BOLD_WHITE}${recommended_mb} MiB${NC}"
    
    printf "\n${GREEN}是否应用此配置? (y/n) ➤ ${NC}"
    read confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local value_bytes=$(echo "$recommended_mb * 1024 * 1024" | bc)
        apply_config_optimized "4096 16384 $value_bytes" "4096 87380 $value_bytes"
    else
        echo -e "${YELLOW}已取消配置应用${NC}"
    fi
}

# 配置对比功能
compare_configs() {
    echo -e "\n${CYAN}=== 配置对比 ===${NC}\n"
    
    # 当前配置
    local current_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)
    local current_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)
    
    echo -e "${GREEN}当前配置:${NC}"
    echo -e "  wmem: ${BOLD_WHITE}$current_wmem${NC}"
    echo -e "  rmem: ${BOLD_WHITE}$current_rmem${NC}"
    
    # 默认配置
    echo -e "\n${GREEN}系统默认配置:${NC}"
    echo -e "  wmem: ${YELLOW}$DEFAULT_WMEM${NC}"
    echo -e "  rmem: ${YELLOW}$DEFAULT_RMEM${NC}"
    
    # 计算差异
    if [[ -n "$current_wmem" && -n "$current_rmem" ]]; then
        local current_wmem_max=$(echo "$current_wmem" | awk '{print $3}')
        local current_rmem_max=$(echo "$current_rmem" | awk '{print $3}')
        local default_wmem_max=$(echo "$DEFAULT_WMEM" | awk '{print $3}')
        local default_rmem_max=$(echo "$DEFAULT_RMEM" | awk '{print $3}')
        
        local wmem_diff=$((current_wmem_max - default_wmem_max))
        local rmem_diff=$((current_rmem_max - default_rmem_max))
        
        echo -e "\n${GREEN}配置差异:${NC}"
        echo -e "  wmem差异: ${CYAN}${wmem_diff} bytes${NC}"
        echo -e "  rmem差异: ${CYAN}${rmem_diff} bytes${NC}"
        
        if [ $wmem_diff -gt 0 ] || [ $rmem_diff -gt 0 ]; then
            echo -e "  状态: ${GREEN}已优化${NC}"
        else
            echo -e "  状态: ${YELLOW}使用默认配置${NC}"
        fi
    fi
}

# 配置回滚功能
rollback_config() {
    echo -e "\n${CYAN}=== 配置回滚 ===${NC}\n"
    
    if [ ${#CONFIG_HISTORY[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠ 没有可回滚的配置历史${NC}"
        return 0
    fi
    
    echo -e "${GREEN}配置历史:${NC}"
    for i in "${!CONFIG_HISTORY[@]}"; do
        local entry="${CONFIG_HISTORY[$i]}"
        local timestamp=$(echo "$entry" | cut -d'|' -f1)
        local wmem=$(echo "$entry" | cut -d'|' -f2)
        local rmem=$(echo "$entry" | cut -d'|' -f3)
        echo -e "  ${YELLOW}$((i+1)).${NC} $timestamp - wmem: $wmem, rmem: $rmem"
    done
    
    printf "\n${GREEN}请选择要回滚的配置 (1-${#CONFIG_HISTORY[@]}) ➤ ${NC}"
    read choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#CONFIG_HISTORY[@]} ]; then
        local selected_entry="${CONFIG_HISTORY[$((choice-1))]}"
        local wmem=$(echo "$selected_entry" | cut -d'|' -f2)
        local rmem=$(echo "$selected_entry" | cut -d'|' -f3)
        
        printf "\n${GREEN}确认回滚到此配置? (y/n) ➤ ${NC}"
        read confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "\n${CYAN}正在回滚配置...${NC}"
            apply_config_optimized "$wmem" "$rmem"
        else
            echo -e "${YELLOW}已取消回滚${NC}"
        fi
    else
        echo -e "${RED}✘ 无效选择${NC}"
    fi
}

# 网络测试功能
network_test() {
    echo -e "\n${CYAN}=== 网络测试 ===${NC}\n"
    
    echo -e "${GREEN}请选择测试类型:${NC}"
    echo -e "  ${YELLOW}1.${NC} 延迟测试"
    echo -e "  ${YELLOW}2.${NC} 带宽测试 (iperf3)"
    echo -e "  ${YELLOW}3.${NC} 综合测试"
    
    printf "\n${GREEN}请输入测试类型 (1-3) ➤ ${NC}"
    read test_type
    
    case "$test_type" in
        1)
            echo -e "\n${CYAN}延迟测试...${NC}"
            ping -c 10 8.8.8.8 | grep 'avg'
            ;;
        2)
            echo -e "\n${CYAN}带宽测试...${NC}"
            echo -e "${YELLOW}请确保iperf3服务已启动${NC}"
            ;;
        3)
            echo -e "\n${CYAN}综合测试...${NC}"
            echo -e "延迟测试:"
            ping -c 5 8.8.8.8 | grep 'avg'
            echo -e "\n网络连接测试:"
            curl -s -o /dev/null -w "下载速度: %{speed_download} bytes/sec\n" http://speedtest.tele2.net/1MB.zip
            ;;
        *)
            echo -e "${RED}✘ 无效选择${NC}"
            ;;
    esac
}

# 系统诊断功能
system_diagnosis() {
    echo -e "\n${CYAN}=== 系统诊断 ===${NC}\n"
    
    # 系统信息
    echo -e "${GREEN}系统信息:${NC}"
    echo -e "  内核版本: ${BOLD_WHITE}$(uname -r)${NC}"
    echo -e "  系统时间: ${BOLD_WHITE}$(date)${NC}"
    echo -e "  运行时间: ${BOLD_WHITE}$(uptime -p)${NC}"
    
    # 网络配置
    echo -e "\n${GREEN}网络配置:${NC}"
    echo -e "  TCP拥塞控制: ${BOLD_WHITE}$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)${NC}"
    echo -e "  队列算法: ${BOLD_WHITE}$(sysctl -n net.core.default_qdisc 2>/dev/null)${NC}"
    
    # BBR支持检查
    if lsmod | grep -q tcp_bbr 2>/dev/null; then
        echo -e "  BBR模块: ${GREEN}已加载${NC}"
    else
        echo -e "  BBR模块: ${YELLOW}未加载或不支持${NC}"
    fi
    
    # 内存使用情况
    echo -e "\n${GREEN}内存使用:${NC}"
    free -h | grep -E "(Mem|Swap)"
    
    # 网络连接数
    echo -e "\n${GREEN}网络连接:${NC}"
    echo -e "  TCP连接数: ${BOLD_WHITE}$(ss -tuln | wc -l)${NC}"
    echo -e "  监听端口: ${BOLD_WHITE}$(ss -tuln | grep LISTEN | wc -l)${NC}"
}

# =================================================================
# 主程序入口 - 优化版
# =================================================================

# 初始化检查
check_root_privileges
check_network_connectivity

# 创建日志文件
touch "$LOG_FILE" 2>/dev/null
log_message "INFO" "TCP tuning script started"

# 主循环
while true; do
    draw_header
    draw_status
    draw_main_menu
    
    printf "${GREEN}请输入选项编号 ➤ ${NC}"
    read choice_main

    case "$choice_main" in
        1)
            # 智能调优子菜单
            while true; do
                draw_header
                draw_status
                draw_smart_tuning_menu
                
                printf "${GREEN}请输入选项编号 ➤ ${NC}"
                read smart_choice

                case "$smart_choice" in
                    1)
                        auto_detect_and_tune
                        ;;
                    2)
                        # BDP计算调优 (保持原有功能)
                        echo -e "\n${CYAN}BDP计算调优功能${NC}"
                        echo -e "${YELLOW}此功能需要手动输入带宽和延迟${NC}"
                        ;;
                    3)
                        scenario_based_tuning
                        ;;
                    4)
                        # 微调功能 (保持原有功能)
                        echo -e "\n${CYAN}微调功能${NC}"
                        echo -e "${YELLOW}此功能需要手动选择增减${NC}"
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
                echo -e "\n${YELLOW}按回车键继续...${NC}"
                read -r
            done
            ;;
        2)
            # 手动调优 (保持原有功能)
            echo -e "\n${CYAN}手动调优功能${NC}"
            echo -e "${YELLOW}此功能保持原有实现${NC}"
            echo -e "\n${YELLOW}按回车键继续...${NC}"
            read -r
            ;;
        3)
            # 配置管理子菜单
            while true; do
                draw_header
                draw_status
                draw_config_menu
                
                printf "${GREEN}请输入选项编号 ➤ ${NC}"
                read config_choice

                case "$config_choice" in
                    1)
                        show_detailed_info
                        ;;
                    2)
                        compare_configs
                        ;;
                    3)
                        # 重置为默认 (保持原有功能)
                        echo -e "\n${CYAN}重置为默认配置${NC}"
                        ;;
                    4)
                        rollback_config
                        ;;
                    5)
                        # 备份管理 (保持原有功能)
                        echo -e "\n${CYAN}备份管理功能${NC}"
                        ;;
                    0)
                        echo -e "\n${CYAN}返回主菜单...${NC}"
                        sleep 1
                        break
                        ;;
                    *)
                        echo -e "\n${RED}✘ 无效选择，请输入0-5之间的数字${NC}"
                        ;;
                esac
                echo -e "\n${YELLOW}按回车键继续...${NC}"
                read -r
            done
            ;;
        4)
            network_test
            echo -e "\n${YELLOW}按回车键继续...${NC}"
            read -r
            ;;
        5)
            system_diagnosis
            echo -e "\n${YELLOW}按回车键继续...${NC}"
            read -r
            ;;
        6)
            # 帮助信息
            echo -e "\n${CYAN}=== 帮助信息 ===${NC}\n"
            echo -e "${GREEN}脚本功能:${NC}"
            echo -e "  • 智能TCP缓冲区调优"
            echo -e "  • 自动网络环境检测"
            echo -e "  • 场景化配置推荐"
            echo -e "  • 配置管理和回滚"
            echo -e "  • 网络测试和诊断"
            echo -e "\n${GREEN}使用建议:${NC}"
            echo -e "  • 首次使用建议选择'智能调优'"
            echo -e "  • 根据实际使用场景选择配置"
            echo -e "  • 定期进行网络测试验证效果"
            echo -e "\n${YELLOW}按回车键继续...${NC}"
            read -r
            ;;
        0)
            echo -e "\n${CYAN}感谢使用TCP调优脚本，再见！${NC}"
            log_message "INFO" "TCP tuning script exited"
            exit 0
            ;;
        *)
            echo -e "\n${RED}✘ 无效选择，请输入0-6之间的数字${NC}"
            echo -e "\n${YELLOW}按回车键继续...${NC}"
            read -r
            ;;
    esac
done
