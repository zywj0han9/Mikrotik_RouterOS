#=========================================================================================
#           备用网口保证有网脚本
#   Version: 1.0.0
#   Changelog:
#        1. 每分钟运行一次
#        2. 保证备用网口一定有网,方便切换使用
#=========================================================================================

:local backWAN "Wan2"

:local checklink do={
    :local iface $1
    :local sent 0
    # 测试IP
    :local testIP1 "1.1.1.1"
    :local testIP2 "8.8.8.8"
    # 断网判断
    # ping 包数量
    :local pingCount 4
    :local received 0

    # 执行 ping 命令并解析输出
    :local pingResults [/ping $testIP1 count=$pingCount interval=1s interface=$iface as-value]
    :foreach line in=$pingOutput do={
        :if ([:find $line "bytes from"] != -1) do={
            :set received ($received + 1);
        }
        :if ([:find $line "bytes"] != -1) do={
            :set sent ($sent + 1);
        }
    }
    :local lost ($sent - $received)
    :return $lost
}

if ([$checklink $backWAN] != 0) do={
    /ip/dhcp-client/ release $primWAN
    /ip/dhcp-client/ renew $primWAN
}

if ([$checklink $backWAN] != 0) do={
    /interface/ disable $primWAN
    /interface/ enable $primWAN
}
if ([$checklink $backWAN] != 0) do={
    :log error "backWAN is offLine"
}
