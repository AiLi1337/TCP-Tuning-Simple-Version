#!/usr/bin/env bash

# =================================================================
# TCP调优脚本-简单版
# =================================================================

# 提醒使用者
echo "--------------------------------------------------"
echo "TCP调优脚本-简单版"
echo "--------------------------------------------------"
echo "请阅读以下注意事项："
echo "1. 此脚本的TCP调优操作对劣质线路无效"
echo "2. 小带宽或低延迟场景下，调优效果不显著"
echo "3. 请尽量在晚高峰进行调优"
echo "--------------------------------------------------"

# --------------------------------------------------
# 系统初始设置检查与配置
# --------------------------------------------------
current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

# 启用BBR拥塞控制算法
if [[ "$current_cc" != "bbr" ]]; then
    echo "当前TCP拥塞控制算法: ${current_cc:-未设置}，未启用BBR，尝试启用BBR..."
    sed -i '/^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=/d' /etc/sysctl.conf
    sed -i -e '$a\' /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
fi

# 启用fq队列管理
if [[ "$current_qdisc" != "fq" ]]; then
    echo "当前队列管理算法: ${current_qdisc:-未设置}，未启用fq，尝试启用fq..."
    sed -i '/^[[:space:]]*net\.core\.default_qdisc[[:space:]]*=/d' /etc/sysctl.conf
    sed -i -e '$a\' /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
fi

# 一次性应用所有配置变更
if [[ "$current_cc" != "bbr" || "$current_qdisc" != "fq" ]]; then
    sysctl -p >/dev/null 2>&1
    echo "BBR和FQ配置已生效。"
fi

# --------------------------------------------------
# 依赖软件检查与安装
# --------------------------------------------------
# 检查iperf3是否已安装
if ! command -v iperf3 &> /dev/null; then
    echo "iperf3未安装，开始安装iperf3..."
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y iperf3
    elif [ -f /etc/redhat-release ]; then
        yum install -y iperf3
    else
        echo "安装iperf3失败，请自行安装"
        exit 1
    fi
else
    echo "iperf3已安装，跳过安装过程。"
fi

# 检查 nohup 是否已安装 (coreutils)
if ! command -v nohup &> /dev/null; then
    echo "nohup 未安装，正在安装coreutils..."
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y coreutils
    elif [ -f /etc/redhat-release ]; then
        yum install -y coreutils
    else
        echo "安装nohup失败，请自行安装"
        exit 1
    fi
else
    echo "nohup已安装，跳过安装过程。"
fi

# --------------------------------------------------
# 功能函数定义
# --------------------------------------------------

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
    sysctl -w net.ipv4.tcp_wmem="4096 16384 4194304"
    sysctl -w net.ipv4.tcp_rmem="4096 87380 6291456"
    echo "已将TCP缓冲区(wmem/rmem)重置为默认值。"
}

# 重置TC限速规则
reset_tc() {
    if [ -f /etc/rc.local ]; then
        > /etc/rc.local
        echo "#!/bin/bash" > /etc/rc.local
        chmod +x /etc/rc.local
        echo "已清空 /etc/rc.local 并添加基本脚本头部。"
    else
        echo "/etc/rc.local 文件不存在，无需清理。"
    fi

    echo "当前网卡列表："
    ip link show
    while true; do
        read -p "请根据以上列表输入曾被限速的网卡名称： " iface
        if ip link show "$iface" &>/dev/null; then
            break
        else
            echo "网卡名称无效或不存在，请重新输入。"
        fi
    done

    if command -v tc &> /dev/null; then
        tc qdisc del dev "$iface" root &>/dev/null
        tc qdisc del dev "$iface" ingress &>/dev/null
        echo "已尝试清除网卡 $iface 的 tc 限速规则。"
    else
        echo "tc 命令不可用，未执行限速清理。"
    fi

    if ip link show ifb0 &>/dev/null; then
        tc qdisc del dev ifb0 root &>/dev/null
        ip link set dev ifb0 down
        ip link delete ifb0
        echo "已删除 ifb0 网卡。"
    else
        echo "ifb0 网卡不存在，无需删除。"
    fi
}

# =================================================================
# 主程序入口
# =================================================================

# 显示当前TCP缓冲区大小
echo "--------------------------------------------------"
echo "当前TCP缓冲区参数大小如下："
sysctl net.ipv4.tcp_wmem
sysctl net.ipv4.tcp_rmem
echo "--------------------------------------------------"

# 主菜单
echo "选择方案："
echo "1. 自由调整"
echo "2. 调整复原"
echo "0. 退出脚本"
read -p "请输入方案编号: " choice_main

# 主程序逻辑
case "$choice_main" in
    1)
        while true; do
            echo ""
            echo "--------------------------------------------------"
            echo "方案一：自由调整"
            echo "--------------------------------------------------"
            echo "1. 后台启动iperf3"
            echo "2. TCP缓冲区max值设为指定值 (永久生效)"
            echo "3. 重置TCP缓冲区参数"
            echo "4. 清除TC限速"
            echo "0. 结束iperf3进程并退出"
            echo "--------------------------------------------------"

            read -p "请输入选择: " sub_choice

            case "$sub_choice" in
                1)
                    local_ip=$(wget -qO- --inet4-only http://icanhazip.com 2>/dev/null)
                    if [ -z "$local_ip" ]; then
                        local_ip=$(wget -qO- http://icanhazip.com)
                    fi
                    echo "您的出口IP是: $local_ip"
                    
                    while true; do
                        read -p "请输入用于 iperf3 的端口号（默认 5201，范围 1-65535）： " iperf_port
                        iperf_port=${iperf_port// /}
                        iperf_port=${iperf_port:-5201}
                        if [[ "$iperf_port" =~ ^[0-9]+$ ]] && [ "$iperf_port" -ge 1 ] && [ "$iperf_port" -le 65535 ]; then
                            echo "端口 $iperf_port 有效，继续执行下一步。"
                            break
                        else
                            echo "无效的端口号！请输入 1 到 65535 范围内的数字。"
                        fi
                    done
                    
                    echo "启动 iperf3 服务端，端口：$iperf_port..."
                    nohup iperf3 -s -p "$iperf_port" > /dev/null 2>&1 &
                    iperf3_pid=$!
                    echo "iperf3 服务端已启动，进程 ID：$iperf3_pid"
                    echo "可在客户端使用以下命令测试："
                    echo "iperf3 -c $local_ip -R -t 30 -p $iperf_port"
                    ;;
                2)
                    while true; do
                        read -p "请输入指定值(MiB): " tcp_value
                        if [[ "$tcp_value" =~ ^[1-9][0-9]*$ ]]; then
                            break
                        else
                            echo "无效输入，请输入一个正整数。"
                        fi
                    done
                    
                    value=$((tcp_value * 1024 * 1024))
                    echo "设置TCP缓冲区max值为 $tcp_value MiB ($value bytes)"
                    clear_conf
                    echo "net.ipv4.tcp_wmem=4096 16384 $value" >> /etc/sysctl.conf
                    echo "net.ipv4.tcp_rmem=4096 87380 $value" >> /etc/sysctl.conf
                    sysctl -p
                    echo "设置已永久保存到 /etc/sysctl.conf，重启后依然生效。"
                    ;;
                3)
                    reset_tcp
                    ;;
                4)
                    reset_tc
                    ;;
                0)
                    echo "停止iperf3服务端进程..."
                    pkill iperf3
                    echo "退出脚本。"
                    break
                    ;;
                *)
                    echo "无效选择，请输入0-4之间的数字。"
                    ;;
            esac
            echo "--------------------------------------------------"
            read -p "按回车键返回菜单..."
        done
        ;;
    2)
        echo "执行调整复原..."
        reset_tcp
        reset_tc
        echo "--------------------------------------------------"
        echo "复原已完成。"
        ;;
    0)
        echo "退出脚本。"
        exit 0
        ;;
    *)
        echo "无效选择，请输入0-2之间的数字。"
        ;;
esac