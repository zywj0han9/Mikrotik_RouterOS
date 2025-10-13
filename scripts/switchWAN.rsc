#=========================================================================================
#           双网口切换脚本
#   Version: 4.0.0
#   Changelog:
#   1. 使用TG bot 进行通知
#   2. 双网口一主一备，主网口断网，切换到备用网口
#   3. 通过定时运行，优先保证网络可用
#   4. 运行逻辑：
#           (1). 使用双网口进行网络测试
#           (2). 如果主网口断网，同时备用网口也断网，进行DHCP client的release，renew
#                如果还是无效，就重启interface
#           (3). 如果主网口断网，但是备用网口有网，就修改routes 默认路由到备用网口
#           (4). 如果主网口有网，不进行任何操作
#=========================================================================================

# 主网口
:local primWAN "Wan1"
# 备用网口
:local backWAN "Wan2"


#===========================================================
#
#                       功能函数
#
#===========================================================
# Telegram bot 发送信息
:global sendmsg do={
    :global notifyMsg $1
    /system/script run NotifyTG
}

# 网口连通性测试
:local checklink do={
    :local iface $1
    # 测试IP
    :local testIP1 "1.1.1.1"
    :local testIP2 "8.8.8.8"
    # 断网判断
    # ping 包数量
    :local pingCount 4

    # 执行 ping 命令并解析输出
    :local pingResults [/ping $testIP1 count=$pingCount interval=1s interface=$iface]
    :put $pingResults
    :return $pingResults
}

# 切换默认路由
:local switchRoute do={
    :local targetInterface $1
    :local routeID  [/ip route find comment="dual-wan-failover"]
    :if ([:len $routeID] = 0) do={
        :log error "未找到默认路由"
        :return false
    }
    /ip route set $routeID gateway=$targetInterface
    :return true
}

#===========================================================
#
#                       主逻辑
#
#===========================================================
:local status [$checklink $primWAN]
# 如果主网口没有网，优先切换备用网口，不管是否有网
if ($status > 0) do={
    :log info ("primWAN is onLine")
    :error "primWAN is onLine"
} else={
    :log error ("primWAN is offline")
    $sendmsg "主网口离线"
    $switchRoute $backWAN
    $sendmsg "⚠️ 网络切换: 备用线路已激活"
    :log info "切换到备用网口"
    /ip/dhcp-client/ release $primWAN
    /ip/dhcp-client/ renew $primWAN
    $sendmsg "主网口已经释放并重新获取IP"
}

# 再次测试主网口是否有网
# 如果没有网，就重启网卡
:set status  [$checklink $primWAN]
if ($status != 0) do={
    :log info ("primWAN is onLine")
    $switchRoute $primWAN
} else={
    :log error ("primWAN is offline")
    $sendmsg "主网口还是没有网，尝试重启设备"
    :log info "主网口还是没有网，尝试重启设备"
    /interface/ disable $primWAN
    /interface/ enable $primWAN
    $sendmsg "主网口完成重启设备"
    :log info "主网口完成重启设备"
}

:set status  [$checklink $primWAN]
# 再次测试主网口是否有网
# 一般来讲这次会有网，
if ($status > 0) do={
    :log info ("primWAN is onLine")
    $switchRoute $primWAN
    $sendmsg "✅ 网络恢复: 主线路已启用"

} else={
    :log error ("primWAN is offline")
    $sendmsg "主网口依旧离线，请检查"
}
