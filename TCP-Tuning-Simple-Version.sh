#!/usr/bin/env bash  

# 提醒使用者
echo "--------------------------------------------------"
echo "TCP调优脚本-简单版"
echo "--------------------------------------------------"
echo "请阅读以下注意事项："
echo "1. 此脚本的TCP调优操作对劣质线路无效"
echo "2. 小带宽或低延迟场景下，调优效果不显著"
echo "3. 请尽量在晚高峰进行调优"
echo "--------------------------------------------------"

current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)

# 启用BBR拥塞控制算法 [cite: 1, 2]
if [[ "$current_cc" != "bbr" ]];
then
    echo "当前TCP拥塞控制算法: ${current_cc:-未设置}，未启用BBR，尝试启用BBR..." [cite: 2]
    sed -i '/^[[:space:]]*net\.ipv4\.tcp_congestion_control[[:space:]]*=/d' /etc/sysctl.conf [cite: 2]
    sed -i -e '$a\' /etc/sysctl.conf [cite: 2]
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf [cite: 2]
fi

# 启用fq队列管理 [cite: 3]
if [[ "$current_qdisc" != "fq" ]];
then
    echo "当前队列管理算法: ${current_qdisc:-未设置}，未启用fq，尝试启用fq..." [cite: 3]
    sed -i '/^[[:space:]]*net\.core\.default_qdisc[[:space:]]*=/d' /etc/sysctl.conf [cite: 3]
    sed -i -e '$a\' /etc/sysctl.conf [cite: 3]
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf [cite: 3]
fi

# 一次性应用所有配置变更 [cite: 4]
if [[ "$current_cc" != "bbr" || "$current_qdisc" != "fq" ]]; then
    sysctl -p >/dev/null 2>&1 [cite: 4]
    echo "配置已生效。" [cite: 4]
fi

# 检查iperf3是否已安装 [cite: 5]
if ! command -v iperf3 &> /dev/null; then
    echo "iperf3未安装，开始安装iperf3..." [cite: 5]
    if [ -f /etc/debian_version ];
then
        apt-get update && apt-get install -y iperf3 [cite: 6]
    elif [ -f /etc/redhat-release ];
then
        yum install -y iperf3 [cite: 7]
    else
        echo "安装iperf3失败，请自行安装" [cite: 7]
        exit 1
    fi
else
    echo "iperf3已安装，跳过安装过程" [cite: 5]
fi

# 检查 nohup 是否已安装 [cite: 8]
if ! command -v nohup &> /dev/null; then
    echo "nohup 未安装，正在安装..." [cite: 8]
    if [ -f /etc/debian_version ];
then
        apt-get update && apt-get install -y coreutils [cite: 9]
    elif [ -f /etc/redhat-release ];
then
        yum install -y coreutils [cite: 10]
    else
        echo "安装nohup失败，请自行安装" [cite: 10]
        exit 1
    fi
else
    echo "nohup已安装，跳过安装过程" [cite: 8]
fi

# 查询并输出当前的TCP缓冲区参数大小
echo "--------------------------------------------------"
echo "当前TCP缓冲区参数大小如下："
sysctl net.ipv4.tcp_wmem
sysctl net.ipv4.tcp_rmem
echo "--------------------------------------------------"

clear_conf() {
    sed -i '/^net\.ipv4\.tcp_wmem/d' /etc/sysctl.conf
    sed -i '/^net\.ipv4\.tcp_rmem/d' /etc/sysctl.conf
    if [ -n "$(tail -c1 /etc/sysctl.conf)" ];
then
        echo "" >> /etc/sysctl.conf [cite: 11]
    fi
}

reset_tcp() {
    clear_conf
    sysctl -w net.ipv4.tcp_wmem="4096 16384 4194304" [cite: 50]
    sysctl -w net.ipv4.tcp_rmem="4096 87380 6291456" [cite: 50]
    echo "已将 net.ipv4.tcp_wmem 和 net.ipv4.tcp_rmem 重置为默认值" [cite: 50]
}

reset_tc() {
    if [ -f /etc/rc.local ];
then
      > /etc/rc.local [cite: 51]
      echo "#!/bin/bash" > /etc/rc.local [cite: 51]
      chmod +x /etc/rc.local [cite: 51]
      echo "已清空 /etc/rc.local 并添加基本脚本头部" [cite: 51]
    else
      echo "/etc/rc.local 文件不存在，无需清理" [cite: 51]
    fi

    echo "当前网卡列表："
    ip link show
    while true; do
      read -p "请根据以上列表输入被限速的网卡名称： " iface [cite: 52]
      if ip link show $iface &>/dev/null;
then
        break [cite: 53]
      else
        echo "网卡名称无效或不存在，请重新输入" [cite: 53]
      fi
    done

    if command -v tc &> /dev/null;
then
      tc qdisc del dev $iface root 2>/dev/null [cite: 54]
      tc qdisc del dev $iface ingress 2>/dev/null [cite: 54]
      echo "已尝试清除网卡 $iface 的 tc 限速规则" [cite: 54]
    else
      echo "tc 命令不可用，未执行限速清理" [cite: 54]
    fi

    if ip link show ifb0 &>/dev/null;
then
      tc qdisc del dev ifb0 root 2>/dev/null [cite: 55]
      ip link set dev ifb0 down [cite: 55]
      ip link delete ifb0 [cite: 55]
      echo "已删除 ifb0 网卡" [cite: 55]
    else
      echo "ifb0 网卡不存在，无需删除" [cite: 55]
    fi
}

echo "选择方案："
echo "1. 自由调整"
echo "2. 调整复原"
echo "0. 退出脚本"

read -p "请输入方案编号: " choice_main

# 主程序
case "$choice_main" in
  1)
    while true; do
        echo "方案一：自由调整"
        echo "请选择操作："
        echo "1. 后台启动iperf3"
        echo "2. TCP缓冲区max值设为指定值 (永久生效)"
        echo "3. 重置TCP缓冲区参数" [cite: 57]
        echo "4. 清除TC限速" [cite: 57]
        echo "0. 结束iperf3进程并退出" [cite: 57]
        echo "--------------------------------------------------"

        read -p "请输入选择: " sub_choice

        case "$sub_choice" in
            1)
                # 获取本机IP地址
                 local_ip=$(wget -qO- --inet4-only http://icanhazip.com 2>/dev/null) [cite: 58]

                if [ -z "$local_ip" ];
then
                    local_ip=$(wget -qO- http://icanhazip.com) [cite: 59]
                fi

                echo "您的出口IP是: $local_ip"
                echo "--------------------------------------------------"

                while true; do
                    # 提示用户输入端口号
                    read -p "请输入用于 iperf3 的端口号（默认 5201，范围 1-65535）： " iperf_port [cite: 60]
                    iperf_port=${iperf_port// /} [cite: 60]
                    iperf_port=${iperf_port:-5201} [cite: 60]

                     # 检查端口号是否有效
                    if [[ "$iperf_port" =~ ^[0-9]+$ ]] && [ "$iperf_port" -ge 1 ] && [ "$iperf_port" -le 65535 ];
then
                        echo "端口 $iperf_port 有效，继续执行下一步" [cite: 62]
                        break [cite: 62]
                    else
                        echo "无效的端口号！请输入 1 到 65535 范围内的数字" [cite: 63]
                    fi
                done
                echo "--------------------------------------------------"

                # 启动 iperf3 服务端
                echo "启动 iperf3 服务端，端口：$iperf_port..."
                 nohup iperf3 -s -p $iperf_port > /dev/null 2>&1 & [cite: 64]
                iperf3_pid=$! [cite: 65]
                echo "iperf3 服务端启动，进程 ID：$iperf3_pid" [cite: 65]
                echo "可在客户端使用以下命令测试："
                echo "iperf3 -c $local_ip -R -t 30 -p $iperf_port"
                ;;
            2)
                while true; do
                    read -p "请输入指定值(MiB): " tcp_value [cite: 80]
                    if [[ "$tcp_value" =~ ^[1-9][0-9]*$ ]];
then
                        break [cite: 81]
                    else
                        echo "无效输入，请输入一个正整数" [cite: 81]
                    fi
             done

                value=$((tcp_value * 1024 * 1024)) [cite: 82]
                echo "设置TCP缓冲区max值为$tcp_value MiB: $value bytes"
                clear_conf
                echo "net.ipv4.tcp_wmem=4096 16384 $value" >> /etc/sysctl.conf [cite: 83]
                echo "net.ipv4.tcp_rmem=4096 87380 $value" >> /etc/sysctl.conf [cite: 83]
                sysctl -p [cite: 83]
                echo "设置已永久保存到 /etc/sysctl.conf，重启后依然生效。"
                ;;
            3)
                reset_tcp [cite: 111]
                ;;
            4)
                reset_tc [cite: 112]
                ;;
            0)
                echo "停止iperf3服务端进程..." [cite: 113]
                pkill iperf3 [cite: 113]
                echo "退出脚本" [cite: 113]
                break [cite: 113]
                ;;
            *)
                echo "无效选择，请输入0-4之间的数字" [cite: 114]
                ;;
        esac
        echo "--------------------------------------------------"
        read -p "按回车键继续..."
        echo "--------------------------------------------------"
    done
    ;;
  2)
    echo "调整复原" [cite: 116]

    reset_tcp [cite: 116]
    reset_tc [cite: 116]

    echo "--------------------------------------------------"
    echo "复原已完成" [cite: 116]
    ;;
  0)
    echo "退出脚本" [cite: 118]
    exit 0 [cite: 118]
    ;;
  *)
    echo "无效选择，请输入0-2之间的数字" [cite: 119]
    ;;
esac