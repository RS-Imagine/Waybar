#!/bin/bash

# --- 辅助函数：使用 Fuzzel 来显示消息 ---
# 我们定义一个名为 "show_message" 的函数，这样就不用重复写同样的代码了。
# 这个函数的作用是接收一段文字作为输入，然后用 Fuzzel 把它弹窗显示出来。
# 用户可以通过按 Enter 或 Esc 键来关闭这个消息窗口。
show_message() {
    # 将函数的第一个参数 (也就是要显示的消息) 存储在局部变量 "message" 中。
    local message="$1"
    # 使用 "echo" 命令将消息内容通过管道符 "|" 传递给 Fuzzel。
    # --dmenu: 让 Fuzzel 以 dmenu 模式运行，只接收和显示我们传递给它的文本。
    # --prompt: 设置 Fuzzel 窗口左上角的提示符，让用户知道这是个信息提示。
    # --layer=overlay: 确保 Fuzzel 窗口在最顶层，并且在失去焦点时会自动关闭。
    echo -e "$message" | fuzzel --dmenu --prompt="[信息] WiFi 设置" --layer=overlay
}

# --- 步骤 1: 强制刷新 Wi-Fi 列表 ---
# 这个命令会告诉 NetworkManager 立即重新扫描周围的 Wi-Fi 网络。
# 这是非常关键的一步，可以确保我们接下来获取到的是最新的网络列表，而不是缓存的旧数据。
nmcli dev wifi rescan

# --- 步骤 2: 获取所有 Wi-Fi 网络 ---
# 使用 "nmcli" (NetworkManager 命令行工具) 来获取 Wi-Fi 信息。
# -t (terse): 以简洁的、用冒号分隔的格式输出，方便机器解析。
# -f (fields): 指定我们想要获取的字段，这里是 "active" (是否激活) 和 "ssid" (网络名称)。
# grep '^yes': 从列表中筛选出 "active" 字段为 "yes" 的那一行，也就是当前已连接的网络。
# cut -d: -f2: 使用冒号作为分隔符，切分出第二段内容，即已连接网络的 SSID。
connected_ssid=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)

# 获取所有可见的 Wi-Fi 列表，包含 SSID 和信号强度 (bars)。
# sed 's/\\:/-/g': `sed` 是一个流编辑器，这条命令会把 SSID 名称中可能包含的冒号 ":" 替换成连字符 "-"，避免与 nmcli 的分隔符混淆。
wifi_list=$(nmcli -t -f ssid,bars dev wifi | sed 's/\\:/-/g')

# --- 步骤 3: 格式化菜单列表 ---
# 检查 "connected_ssid" 变量是否为空。
if [ -n "$connected_ssid" ]; then
    # 如果不为空 (即当前有网络连接)，我们就创建一个特殊的菜单项来显示它。
    # 我们用 "[已连接]" 来替代之前的特殊符号，更加通用。
    current_connection="[已连接]  $connected_ssid"
    # 为了避免在菜单中重复显示，我们从扫描到的总列表中移除当前已连接的网络。
    wifi_list=$(echo "$wifi_list" | grep -v "^$connected_ssid:")
else
    # 如果为空 (即当前未连接任何网络)，就显示一个未连接的状态。
    current_connection="[未连接]"
fi

# --- 步骤 4: 显示 Fuzzel 菜单并获取用户选择 ---
# 将格式化好的 "当前连接状态" 和 "其他网络列表" 合并，并通过管道传递给 Fuzzel。
# Fuzzel 会显示这个列表，并等待用户选择。
# 用户选择的行会被存储在 "chosen_network" 变量中。
chosen_network=$(echo -e "$current_connection\n$wifi_list" | fuzzel --dmenu --prompt="选择 Wi-Fi" --layer=overlay)

# --- 步骤 5: 处理用户的选择 ---
# 如果 "chosen_network" 变量为空，说明用户按了 Esc 键取消了操作，脚本直接退出。
if [ -z "$chosen_network" ]; then
    exit 0
fi

# 从用户选择的行中，只提取出纯净的 SSID 名称。
# sed 's/...//': 这个命令会用 "sed" 删除我们之前添加的前缀，如 "[已连接]" 或 "[未连接]"，以及信号强度信息。
chosen_ssid=$(echo "$chosen_network" | sed 's/.*\[已连接\]  //;s/.*\[未连接\]//;s/:.*//')

# 如果用户再次点击了当前已连接的网络，或者点击了 "未连接" 状态，那么什么也不做，直接退出。
if [ "$chosen_ssid" = "$connected_ssid" ] || [ "$chosen_ssid" = "" ]; then
    exit 0
fi

# --- 步骤 6: 核心逻辑 - 尝试连接 ---

# 检查用户选择的网络是否是一个“已知网络”（即系统保存了它的密码）。
if nmcli con show "$chosen_ssid" > /dev/null 2>&1; then
    # 如果是已知网络，直接尝试连接。
    if nmcli con up id "$chosen_ssid"; then
        # 连接成功，弹窗提示。
        show_message "成功连接到 $chosen_ssid"
    else
        # 如果连接失败（很可能是密码被修改了），弹窗提示用户。
        show_message "无法连接到 $chosen_ssid！\n密码可能已更改，重新输入："
        # 删除系统中保存的这个旧的、错误的连接配置。
        nmcli connection delete "$chosen_ssid"
    fi
fi

# 这个 "if" 条件判断我们是否“仍然”没有连接上目标网络。
# 两种情况会进入这个代码块：
# 1. 这是一个全新的网络，之前从未连接过。
# 2. 这是一个已知网络，但因为密码错误等原因，在上一步连接失败了。
if ! nmcli con show --active | grep -q "^$chosen_ssid "; then
    
    # 设置密码输入框的初始提示文字。
    prompt_text="输入网络密码: $chosen_ssid"

    # 进入一个无限循环，直到连接成功或用户取消。
    while true; do
        # 弹出 Fuzzel 密码输入框。
        wifi_password=$(fuzzel --dmenu --password --prompt "$prompt_text" --layer=overlay)

        # 如果用户在密码输入框按了 Esc，"wifi_password" 会为空，我们就用 "break" 跳出循环。
        if [ -z "$wifi_password" ]; then
            break
        fi

        # 尝试使用用户输入的密码进行连接。
        if nmcli dev wifi connect "$chosen_ssid" password "$wifi_password"; then
            # 如果连接成功...
            show_message "成功连接到 $chosen_ssid"
            break # ...跳出循环，脚本结束。
        else
            # 如果连接失败...
            # 更新提示文字，告诉用户密码错误。
            prompt_text="密码错误! 请重试: $chosen_ssid"
            # NetworkManager 可能会在失败后留下一个坏的配置，我们把它删掉，确保下次尝试是干净的。
            nmcli connection delete "$chosen_ssid" 2>/dev/null
            # 循环会继续，再次弹出密码输入框。
        fi
    done
fi
