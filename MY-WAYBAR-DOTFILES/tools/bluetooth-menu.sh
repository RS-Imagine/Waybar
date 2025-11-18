#!/bin/bash

# --- 辅助函数：使用 Fuzzel 来显示消息 ---
# 和 Wi-Fi 脚本一样，这个函数用于显示操作结果和提示信息。
show_message() {
    local message="$1"
    echo -e "$message" | fuzzel --dmenu --prompt="[信息] 蓝牙设置" --layer=overlay
}

# --- 步骤 1: 获取蓝牙设备信息 ---
# 获取当前已连接的设备信息。
connected_device=$(bluetoothctl devices Connected | cut -d ' ' -f 2-)
connected_mac=$(echo "$connected_device" | cut -d ' ' -f 1)

# 获取所有已配对的设备列表，并排除已连接的设备。
# "bluetoothctl devices Paired" 列出所有配对过的设备。
# "grep -v "$connected_mac"" 会过滤掉 (移除) 当前已连接的设备那一行。
paired_devices=$(bluetoothctl devices Paired | grep -v "$connected_mac" | cut -d ' ' -f 2-)

# --- 步骤 2: 创建 Fuzzel 菜单列表 ---
# 初始化菜单，添加一个固定的“扫描”选项。
menu="[扫描] 扫描新设备\n"

# 检查是否有设备已连接。
if [ -n "$connected_device" ]; then
    # 如果有，菜单顶部会显示已连接的设备，并添加一个“断开连接”的选项。
    menu="${menu}[已连接] $connected_device\n"
    menu="${menu}[断开] 断开 $connected_device\n"
else
    # 如果没有，显示一个“未连接”的状态。
    menu="${menu}[未连接]\n"
fi

# 将所有已配对但未连接的设备添加到菜单中。
menu="${menu}${paired_devices}"

# --- 步骤 3: 显示 Fuzzel 菜单并获取用户选择 ---
chosen_option=$(echo -e "$menu" | fuzzel --dmenu --prompt="选择蓝牙设备" --layer=overlay)

# --- 步骤 4: 处理用户的选择 ---
# 如果用户按 Esc 取消，则退出。
if [ -z "$chosen_option" ]; then
    exit 0
fi

# 提取选择的类型（如 [扫描], [断开]）和纯设备信息。
chosen_type=$(echo "$chosen_option" | awk -F ']' '{print $1}' | sed 's/\[//')
chosen_device_info=$(echo "$chosen_option" | cut -d ' ' -f 2-)
chosen_mac=$(echo "$chosen_device_info" | cut -d ' ' -f 1)

# 使用 "case" 语句来根据用户的选择执行不同的操作。
case "$chosen_type" in
    "扫描")
        # 如果用户选择扫描...
        show_message "正在扫描新设备 (持续 3 秒)..."
        # "scan on" 会持续扫描，我们让它在后台运行，3秒后关闭它。
        bluetoothctl scan on > /dev/null &
        sleep 3
        bluetoothctl scan off > /dev/null
        show_message "扫描完成！"
        # 使用 "exec" 重新运行此脚本，以刷新设备列表。
        exec "$0"
        ;;
    "断开")
        # 如果用户选择断开...
        if bluetoothctl disconnect "$connected_mac"; then
            show_message "已断开与 $connected_device 的连接"
        else
            show_message "断开连接失败"
        fi
        ;;
    "已连接" | "未连接")
        # 如果用户点击的是状态信息，则什么也不做。
        exit 0
        ;;
    *)
        # 默认情况：用户选择了一个设备进行连接。
        # 首先，如果已经有设备连接着，先断开它。
        if [ -n "$connected_mac" ]; then
            bluetoothctl disconnect "$connected_mac"
            sleep 1 # 等待一秒确保断开完成
        fi
        
        # 尝试连接到新选择的设备。
        if bluetoothctl connect "$chosen_mac"; then
            show_message "成功连接到 $chosen_device_info"
        else
            show_message "无法连接到 $chosen_device_info"
        fi
        ;;
esac
