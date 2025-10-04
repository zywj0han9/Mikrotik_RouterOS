# ========================================
# MikroTik RouterOS 双WAN防火墙完整配置脚本
# 版本: 3.2 Optimized + Topic
# 亮点：
# - ✅ 支持把 Telegram 消息发到“带话题的群组”（Forum Topic）
# - ✅ 通过 message_thread_id 精确投递到指定话题
# - ✅ 其他与 v3.2 Optimized 相同的安全/路由/GeoIP/备份特性
# 使用前准备：
# 1) telegramBotToken 设为你的 Bot Token
# 2) telegramChatID 设为目标群组 chat_id（超级群通常以 -100 开头）
# 3) telegramTopicID 设为目标话题的 message_thread_id（话题ID）
#    - 可在该话题里 @RawDataBot 或用 Bot API 获取
# ========================================

:log info "=== 开始执行防火墙配置脚本 v3.2 Optimized + Topic ==="

# ========================================
# 配置参数区（★ 按需修改 ★）
# ========================================

# LAN
:global lanInterface "Lan"  # 默认 LAN 接口名
:global lanSubnet "192.168.2.0/24"
:global lanSubnetV6 "fd00::/64"
:global adminPublicIP "203.0.113.100"

# WAN
:global wan1Interface "Wan1"
:global wan2Interface "Wan2"
:global wan1Gateway "10.0.0.1"
:global wan2Gateway "10.0.1.1"
:global wan1CheckHost "8.8.8.8"
:global wan2CheckHost "1.1.1.1"

# SSH（路由器自身端口 与 映射端口分离）
:global sshPort 22022
:global mappedSSHPort 2222
:global mappedSSHTarget "192.168.2.16"

# 端口敲门（三段式）
:global knockPort1 7000
:global knockPort2 8000
:global knockPort3 9000
:global knockTimeout 30

# WinBox
:global winboxPort 8291
:global winboxAllowedIPs "203.0.113.100,203.0.113.101"

# Telegram（群组 + 话题）
:global telegramBotToken "YOUR_BOT_TOKEN_HERE"
# 目标群组 chat_id（超级群通常是负数，如 -1001234567890）
:global telegramChatID "-1001234567890"
# 目标“话题” ID（message_thread_id；不用话题可留空 "" 或 0）
:global telegramTopicID 123456

# 是否尝试把备份“文件本体”也发到 TG（通过 transfer.sh 中转，填 "yes" 或 "no"）
:global tgSendFiles "no"

# GeoIP（允许国家，逗号分隔；为空则不启用）
:global geoipAllowedCountries "KR,CN"
:global geoipDataSource "https://lists.mikrotik.help/by-country"

# Syslog
:global syslogServer "192.168.2.10"

# SYN Flood（INPUT 限速，包/秒）
:global synFloodLimit 20

# IPv6 开关（yes/no）
:global enableIPv6 yes

# 占位IP提醒
:if ([:find $adminPublicIP "203.0.113."] = 0) do={
  :log warning "⚠️  adminPublicIP 为 TEST-NET（203.0.113.0/24），白名单/映射不会命中真实IP！"
}

# ========================================
# 预置：创建 Telegram 发送脚本（支持群组话题）
# ========================================
# 用法：
#   :global tg_text "你的消息"
#   /system script run tg_send
# 可选文档发送：
#   :global tg_doc_url "https://..."
#   /system script run tg_senddoc

/system script add name=tg_send policy=read,write,test,ftp,sensitive source={
    :global telegramBotToken
    :global telegramChatID
    :global telegramTopicID
    :global tg_text

    :if ($telegramBotToken = "YOUR_BOT_TOKEN_HERE" || [:len $tg_text] = 0) do={ :return }

    # 简单 URL 编码（空格/换行/常见符号）
    :local raw $tg_text
    :local enc ""
    :for i from=0 to=([:len $raw]-1) do={
        :local ch [:pick $raw $i ($i+1)]
        :if ($ch="\n") do={ :set enc ($enc . "%0A") } else={
        :if ($ch=" ")  do={ :set enc ($enc . "%20") } else={
        :if ($ch="%")  do={ :set enc ($enc . "%25") } else={
        :if ($ch="#")  do={ :set enc ($enc . "%23") } else={
        :if ($ch="&")  do={ :set enc ($enc . "%26") } else={
        :if ($ch="?")  do={ :set enc ($enc . "%3F") } else={
        :if ($ch="+")  do={ :set enc ($enc . "%2B") } else={
        :if ($ch="=")  do={ :set enc ($enc . "%3D") } else={
            :set enc ($enc . $ch)
        }}}}}}}}
    }

    :local base ("https://api.telegram.org/bot" . $telegramBotToken . "/sendMessage?chat_id=" . $telegramChatID . "&text=" . $enc)
    :if ([:len $telegramTopicID] > 0 && $telegramTopicID != 0) do={
        :set base ($base . "&message_thread_id=" . $telegramTopicID)
    }

    :do { /tool fetch url=$base keep-result=no check-certificate=no } on-error={ :log warning "tg_send: 发送失败" }
}

# 发送文档（URL 方式）
/system script add name=tg_senddoc policy=read,write,test,ftp,sensitive source={
    :global telegramBotToken
    :global telegramChatID
    :global telegramTopicID
    :global tg_doc_url

    :if ($telegramBotToken = "YOUR_BOT_TOKEN_HERE" || [:len $tg_doc_url] = 0) do={ :return }
    :local base ("https://api.telegram.org/bot" . $telegramBotToken . "/sendDocument?chat_id=" . $telegramChatID . "&document=" . $tg_doc_url)
    :if ([:len $telegramTopicID] > 0 && $telegramTopicID != 0) do={
        :set base ($base . "&message_thread_id=" . $telegramTopicID)
    }
    :do { /tool fetch url=$base keep-result=no check-certificate=no } on-error={ :log warning "tg_senddoc: 发送失败" }
}

# ========================================
# 第一阶段：清理
# ========================================
:log warning "步骤 1/18: 清理现有防火墙/计划任务..."

:foreach i in=[/ip firewall filter find] do={ /ip firewall filter remove $i }
:foreach i in=[/ip firewall nat find] do={ /ip firewall nat remove $i }
:foreach i in=[/ip firewall raw find] do={ /ip firewall raw remove $i }
:foreach i in=[/ip firewall address-list find] do={ /ip firewall address-list remove $i }

:if ($enableIPv6 = yes) do={
  :foreach i in=[/ipv6 firewall filter find] do={ /ipv6 firewall filter remove $i }
  :foreach i in=[/ipv6 firewall raw find] do={ /ipv6 firewall raw remove $i }
  :foreach i in=[/ipv6 firewall address-list find] do={ /ipv6 firewall address-list remove $i }
}

:foreach i in=[/interface list member find] do={ /interface list member remove $i }
:foreach i in=[/tool netwatch find] do={ /tool netwatch remove $i }
:foreach i in=[/system scheduler find comment~"Port-Knock|backup|cleanup|export|geoip"] do={ /system scheduler remove $i }
:foreach i in=[/system script find name~"backup_to_tg|geoip_update"] do={ /system script remove $i }

# 保留 tg_send / tg_senddoc

# ========================================
# 第二阶段：接口列表
# ========================================
:log info "步骤 2/18: 配置接口列表..."
:if ([/interface list find name=LAN] != "") do={ /interface list remove [find name=LAN] }
:if ([/interface list find name=WAN] != "") do={ /interface list remove [find name=WAN] }
/interface list add name=LAN comment="内部接口"
/interface list add name=WAN comment="外部接口"
# 如需多个 LAN 接口，可复制下一行并改用其他自定义变量
/interface list member add list=LAN interface=$lanInterface comment="主内网口"
/interface list member add list=WAN interface=$wan1Interface comment="主外网口"
/interface list member add list=WAN interface=$wan2Interface comment="备外网口"

# ========================================
# 第三阶段：地址列表（IPv4）
# ========================================
:log info "步骤 3/18: IPv4 地址列表..."
/ip firewall address-list add list=LAN_SUBNETS address=$lanSubnet comment="LAN 子网"
/ip firewall address-list add list=admin-wan address=$adminPublicIP comment="管理员公网IP"

# WinBox 白名单 CSV
:local _csv $winboxAllowedIPs
:while ([:len $_csv] > 0) do={
  :local _pos [:find $_csv ","]
  :local _ip ""
  :if ($_pos = nil) do={ :set _ip $_csv ; :set $_csv "" } else={
    :set _ip [:pick $_csv 0 $_pos]
    :set $_csv [:pick $_csv ($_pos+1) [:len $_csv]]
  }
  :if ([:len [:toip $_ip]] > 0) do={ /ip firewall address-list add list=winbox-allowed address=$_ip comment="WinBox 允许源" }
}

# bogon & 非全局
/ip firewall address-list add list=bogon address=127.0.0.0/8
/ip firewall address-list add list=bogon address=192.0.2.0/24
/ip firewall address-list add list=bogon address=198.51.100.0/24
/ip firewall address-list add list=bogon address=203.0.113.0/24
/ip firewall address-list add list=bogon address=240.0.0.0/4

/ip firewall address-list add list=not_global_ipv4 address=0.0.0.0/8
/ip firewall address-list add list=not_global_ipv4 address=10.0.0.0/8
/ip firewall address-list add list=not_global_ipv4 address=100.64.0.0/10
/ip firewall address-list add list=not_global_ipv4 address=169.254.0.0/16
/ip firewall address-list add list=not_global_ipv4 address=172.16.0.0/12
/ip firewall address-list add list=not_global_ipv4 address=192.168.0.0/16
/ip firewall address-list add list=not_global_ipv4 address=198.18.0.0/15
/ip firewall address-list add list=not_global_ipv4 address=255.255.255.255/32

# 端口映射白名单
/ip firewall address-list add list=pf-ssh-allowed address=$adminPublicIP

# ========================================
# 第三阶段B：地址列表（IPv6）
# ========================================
:if ($enableIPv6 = yes) do={
  :log info "步骤 3B/18: IPv6 地址列表..."
  /ipv6 firewall address-list add list=bad_ipv6 address=::/128
  /ipv6 firewall address-list add list=bad_ipv6 address=::1
  /ipv6 firewall address-list add list=bad_ipv6 address=fec0::/10
  /ipv6 firewall address-list add list=bad_ipv6 address=::ffff:0:0/96
  /ipv6 firewall address-list add list=bad_ipv6 address=::/96
  /ipv6 firewall address-list add list=bad_ipv6 address=100::/64
  /ipv6 firewall address-list add list=bad_ipv6 address=2001:db8::/32
  /ipv6 firewall address-list add list=bad_ipv6 address=2001:10::/28
  /ipv6 firewall address-list add list=bad_ipv6 address=3ffe::/16
}

# ========================================
# 第四阶段：GeoIP 自动导入
# ========================================
:log info "步骤 4/18: GeoIP 自动导入..."

:if ([:len $geoipAllowedCountries] > 0) do={
  /system script add name=geoip_update policy=read,write,test,ftp,sensitive source={
    :global geoipAllowedCountries
    :global geoipDataSource
    :log info "==== GeoIP 更新 ===="
    :local countries [:toarray ""]
    :local temp ""
    :for i from=0 to=([:len $geoipAllowedCountries]) do={
        :local c ""
        :if ($i < [:len $geoipAllowedCountries]) do={ :set c [:pick $geoipAllowedCountries $i ($i+1)] }
        :if ($c = "," || $i = [:len $geoipAllowedCountries]) do={
            :if ([:len $temp] > 0) do={ :set ($countries->[:len $countries]) [:tolower $temp]; :set temp "" }
        } else={ :set temp ($temp . $c) }
    }
    :foreach i in=[/ip firewall address-list find list=geoip-allowed] do={ /ip firewall address-list remove $i }
    :local totalImported 0; :local totalFailed 0
    :foreach cc in=$countries do={
        :local f ($cc . ".rsc"); :local url ($geoipDataSource . "/" . $cc . ".rsc")
        :do {
            /tool fetch url=$url mode=https dst-path=$f check-certificate=no
            :delay 1s
            :if ([/file find name=$f] != "") do={
                /import file-name=$f
                :local ren 0
                :foreach r in=[/ip firewall address-list find list=$cc] do={ /ip firewall address-list set $r list=geoip-allowed; :set ren ($ren+1) }
                :set totalImported ($totalImported + $ren)
                /file remove $f
                :log info ("✓ " . [:toupper $cc] . " -> " . $ren)
            } else={ :set totalFailed ($totalFailed + 1) }
        } on-error={ :set totalFailed ($totalFailed + 1) }
        :delay 500ms
    }
    :log info ("GeoIP 完成: 成功 " . $totalImported . " 失败 " . $totalFailed)

    :if ($totalImported > 0) do={
        :local geoRule [/ip firewall raw find where comment="RAW: GeoIP drop"]
        :if ($geoRule = "") do={
            /ip firewall raw add chain=prerouting in-interface-list=WAN src-address-list=!geoip-allowed action=drop log=yes log-prefix="geoip_drop" limit=10,10:packet comment="RAW: GeoIP drop"
            :log info "  - GeoIP RAW 规则已创建"
        } else={
            /ip firewall raw set $geoRule disabled=no
            :log info "  - GeoIP RAW 规则已启用"
        }
    }

    # 投递到话题群
    :global tg_text ("[GeoIP 更新]\n成功: " . $totalImported . "\n失败: " . $totalFailed)
    /system script run tg_send
  }

  /system scheduler add name=geoip-auto-update interval=7d start-time=04:00:00 on-event="/system script run geoip_update" comment="每周自动更新 GeoIP"
  :log info "  - 已创建 geoip_update（周日 04:00 自动）"
  :log info "  - 首次请手动运行：/system script run geoip_update"
} else={
  :log info "  - 未启用（geoipAllowedCountries 为空）"
}

# ========================================
# 第五阶段：RAW 预过滤（IPv4）
# ========================================
:log info "步骤 5/18: IPv4 RAW..."
/ip firewall raw add chain=prerouting protocol=tcp dst-port=$knockPort1,$knockPort2,$knockPort3 action=accept comment="RAW: 端口敲门豁免"
#/ 基础丢弃
/ip firewall raw add chain=prerouting action=drop src-address-list=bogon comment="RAW: drop bogon src"
/ip firewall raw add chain=prerouting action=drop dst-address-list=bogon comment="RAW: drop bogon dst"
/ip firewall raw add chain=prerouting action=drop src-address-list=not_global_ipv4 in-interface-list=WAN comment="RAW: drop WAN private src"

# GeoIP（规则默认存在，仅在名单为空时禁用）
:local geoRule [/ip firewall raw find where comment="RAW: GeoIP drop"]
:if ($geoRule = "") do={
  :set geoRule [/ip firewall raw add chain=prerouting in-interface-list=WAN src-address-list=!geoip-allowed action=drop log=yes log-prefix="geoip_drop" limit=10,10:packet disabled=yes comment="RAW: GeoIP drop"]
  :log info "  - 已预创建 GeoIP RAW 规则（等待名单导入）"
}

:local _geoCount [/ip firewall address-list print count-only where list=geoip-allowed]
:if ([:len $geoipAllowedCountries] = 0) do={
  /ip firewall raw set $geoRule disabled=yes
  :log warning "  - 未配置 geoipAllowedCountries，GeoIP RAW 规则保持禁用"
} else={
  :if ($_geoCount = 0) do={
    /ip firewall raw set $geoRule disabled=yes
    :log warning "  - GeoIP 地址列表为空，GeoIP RAW 规则已禁用"
  } else={
    /ip firewall raw set $geoRule disabled=no
    :log info ("  - GeoIP RAW 规则启用（条目: " . $_geoCount . ")")
  }
}

# PSD 扫描检测
/ip firewall raw add chain=prerouting protocol=tcp psd=21,3s,3,1 action=add-src-to-address-list address-list=port-scanners address-list-timeout=2w comment="RAW: PSD"
/ip firewall raw add chain=prerouting src-address-list=port-scanners action=drop comment="RAW: drop scanners"

# ========================================
# 第五阶段B：RAW（IPv6）
# ========================================
:if ($enableIPv6 = yes) do={
  :log info "步骤 5B/18: IPv6 RAW..."
  /ipv6 firewall raw add chain=prerouting action=drop src-address-list=bad_ipv6
  /ipv6 firewall raw add chain=prerouting action=drop dst-address-list=bad_ipv6
  :do {
    /ipv6 firewall raw add chain=prerouting protocol=tcp psd=21,3s,3,1 action=add-src-to-address-list address-list=port-scanners-v6 address-list-timeout=2w comment="RAW6: PSD"
  } on-error={ :log warning "IPv6 RAW PSD 不可用，已跳过" }
  /ipv6 firewall raw add chain=prerouting src-address-list=port-scanners-v6 action=drop comment="RAW6: drop scanners"
}

# ========================================
# 第六阶段：INPUT（IPv4）
# ========================================
:log info "步骤 6/18: IPv4 INPUT..."
/ip firewall filter add chain=input action=accept connection-state=established,related,untracked
/ip firewall filter add chain=input action=drop connection-state=invalid log=yes log-prefix="drop_invalid_in" limit=5,5:packet
/ip firewall filter add chain=input action=accept in-interface-list=LAN
/ip firewall filter add chain=input action=accept protocol=icmp limit=10,5:packet
/ip firewall filter add chain=input action=accept in-interface-list=WAN protocol=udp dst-port=68

# SYN 限速（针对 SSH+WinBox）
/ip firewall filter add chain=input protocol=tcp tcp-flags=syn in-interface-list=WAN dst-port=$winboxPort,$sshPort limit=$synFloodLimit,$synFloodLimit:packet action=accept comment="IN: SYN rate"
/ip firewall filter add chain=input src-address-list=syn-flood action=drop log=yes log-prefix="syn_flood" limit=5,5:packet comment="IN: drop SYN Flood（如启用标记规则）"

# WinBox 白名单 & 拒绝
/ip firewall filter add chain=input action=accept protocol=tcp dst-port=$winboxPort src-address-list=winbox-allowed
/ip firewall filter add chain=input action=drop protocol=tcp dst-port=$winboxPort log=yes log-prefix="winbox_deny" limit=3,5:packet

# 敲门后的 SSH
/ip firewall filter add chain=input action=accept protocol=tcp dst-port=$sshPort src-address-list=port-knock-stage3
/ip firewall filter add chain=input action=drop protocol=tcp dst-port=$sshPort log=yes log-prefix="ssh_no_knock" limit=3,5:packet

# 兜底
/ip firewall filter add chain=input action=drop in-interface-list=WAN log=yes log-prefix="drop_in_wan" limit=5,5:packet
/ip firewall filter add chain=input action=drop

# ========================================
# 第六阶段B：INPUT（IPv6）
# ========================================
:if ($enableIPv6 = yes) do={
  :log info "步骤 6B/18: IPv6 INPUT..."
  /ipv6 firewall filter add chain=input action=accept connection-state=established,related,untracked
  /ipv6 firewall filter add chain=input action=drop connection-state=invalid
  /ipv6 firewall filter add chain=input action=accept protocol=icmpv6
  /ipv6 firewall filter add chain=input action=accept protocol=udp dst-port=33434-33534
  /ipv6 firewall filter add chain=input action=accept protocol=udp dst-port=546 src-address=fe80::/10
  /ipv6 firewall filter add chain=input action=accept protocol=udp dst-port=500,4500
  /ipv6 firewall filter add chain=input action=accept protocol=ipsec-ah
  /ipv6 firewall filter add chain=input action=accept protocol=ipsec-esp
  /ipv6 firewall filter add chain=input action=accept ipsec-policy=in,ipsec
  /ipv6 firewall filter add chain=input action=drop in-interface-list=!LAN log=yes log-prefix="drop_in6" limit=5,5:packet
}

# ========================================
# 第七阶段：端口敲门
# ========================================
:log info "步骤 7/18: 端口敲门..."
/ip firewall filter add chain=input in-interface-list=WAN action=add-src-to-address-list address-list=port-knock-stage1 address-list-timeout=$knockTimeout protocol=tcp dst-port=$knockPort1
/ip firewall filter add chain=input in-interface-list=WAN action=add-src-to-address-list address-list=port-knock-stage2 address-list-timeout=$knockTimeout protocol=tcp dst-port=$knockPort2 src-address-list=port-knock-stage1
/ip firewall filter add chain=input in-interface-list=WAN action=add-src-to-address-list address-list=port-knock-stage3 address-list-timeout=1h protocol=tcp dst-port=$knockPort3 src-address-list=port-knock-stage2
/ip firewall filter add chain=input in-interface-list=WAN action=drop protocol=tcp dst-port=$knockPort1,$knockPort2,$knockPort3 comment="drop knock packets"

# （上面几行若出现前导空格导致错误，请删除斜杠后的空格再执行）

# ========================================
# 第八阶段：FORWARD（IPv4）
# ========================================
:log info "步骤 8/18: IPv4 FORWARD..."
/ip firewall filter add chain=forward action=fasttrack-connection connection-state=established,related connection-nat-state=!dstnat hw-offload=yes
/ip firewall filter add chain=forward action=accept connection-state=established,related
/ip firewall filter add chain=forward action=drop connection-state=invalid log=yes log-prefix="drop_invalid_fwd" limit=5,5:packet
/ip firewall filter add chain=forward in-interface-list=LAN src-address-list=!LAN_SUBNETS action=drop log=yes log-prefix="spoof_fwd" limit=5,5:packet
/ip firewall filter add chain=forward in-interface-list=WAN dst-address-list=not_global_ipv4 connection-nat-state=!dstnat action=drop
/ip firewall filter add chain=forward in-interface-list=WAN dst-address-list=bogon connection-nat-state=!dstnat action=drop
/ip firewall filter add chain=forward protocol=tcp dst-port=22 dst-address=$mappedSSHTarget connection-nat-state=dstnat src-address-list=pf-ssh-allowed action=accept
/ip firewall filter add chain=forward protocol=tcp dst-port=22 connection-nat-state=dstnat action=drop log=yes log-prefix="ssh_pf_deny" limit=3,5:packet
/ip firewall filter add chain=forward connection-nat-state=dstnat action=accept
/ip firewall filter add chain=forward in-interface-list=WAN connection-state=new action=drop

# ========================================
# 第八阶段B：FORWARD（IPv6）
# ========================================
:if ($enableIPv6 = yes) do={
  :log info "步骤 8B/18: IPv6 FORWARD..."
  /ipv6 firewall filter add chain=forward action=fasttrack-connection connection-state=established,related
  /ipv6 firewall filter add chain=forward action=accept connection-state=established,related,untracked
  /ipv6 firewall filter add chain=forward action=drop connection-state=invalid
  /ipv6 firewall filter add chain=forward action=drop src-address-list=bad_ipv6
  /ipv6 firewall filter add chain=forward action=drop dst-address-list=bad_ipv6
  /ipv6 firewall filter add chain=forward action=drop protocol=icmpv6 hop-limit=equal:1
  /ipv6 firewall filter add chain=forward action=accept protocol=icmpv6
  /ipv6 firewall filter add chain=forward action=accept protocol=139
  /ipv6 firewall filter add chain=forward action=accept protocol=udp dst-port=500,4500
  /ipv6 firewall filter add chain=forward action=accept protocol=ipsec-ah
  /ipv6 firewall filter add chain=forward action=accept protocol=ipsec-esp
  /ipv6 firewall filter add chain=forward action=accept ipsec-policy=in,ipsec
  /ipv6 firewall filter add chain=forward action=accept in-interface-list=LAN out-interface-list=WAN
  /ipv6 firewall filter add chain=forward action=drop log=yes log-prefix="blocked_v6" limit=5,5:packet
}

# ========================================
# 第九阶段：NAT（含 Hairpin）
# ========================================
:log info "步骤 9/18: NAT..."
/ip firewall nat add chain=srcnat action=masquerade out-interface-list=WAN comment="masquerade WAN"
# Hairpin DSTNAT
/ip firewall nat add chain=dstnat src-address=$lanSubnet dst-address-type=local protocol=tcp dst-port=$mappedSSHPort action=dst-nat to-addresses=$mappedSSHTarget to-ports=22 comment="hairpin dstnat"
/ip firewall nat add chain=srcnat src-address=$lanSubnet dst-address=$mappedSSHTarget protocol=tcp dst-port=22 out-interface-list=LAN action=masquerade comment="hairpin srcnat"
# 外网→内网 SSH 映射（仅白名单）
/ip firewall nat add chain=dstnat in-interface-list=WAN protocol=tcp dst-port=$mappedSSHPort src-address-list=pf-ssh-allowed action=dst-nat to-addresses=$mappedSSHTarget to-ports=22

# ========================================
# 第十阶段：路由与探测
# ========================================
:log info "步骤 10/18: 路由..."
:foreach i in=[/ip route find comment~"WAN|Check Host|Default via|Backup via"] do={ /ip route remove $i }
#/ 默认路由
/ip route add dst-address=0.0.0.0/0 gateway=$wan1Gateway distance=1 comment="Default via WAN1"
/ip route add dst-address=0.0.0.0/0 gateway=$wan2Gateway distance=2 comment="Backup via WAN2"
#/ 探测主机
/ip route add dst-address=$wan1CheckHost/32 gateway=$wan1Gateway scope=10 comment="Check Host for WAN1"
/ip route add dst-address=$wan2CheckHost/32 gateway=$wan2Gateway scope=10 comment="Check Host for WAN2"
:log info "  - 请确认各 WAN DHCP Client：add-default-route=no"

# ========================================
# 第十一阶段：Netwatch 故障切换（使用话题群通知）
# ========================================
:log info "步骤 11/18: Netwatch..."
/tool netwatch add host=$wan1CheckHost interval=10s timeout=3s \
  up-script={ 
    :log info "WAN1 UP: 恢复主线路"; /ip route set [find comment="Default via WAN1"] disabled=no;
    :global tg_text "[WAN1] 线路恢复正常"; /system script run tg_send;
  } \
  down-script={ 
    :log warning "WAN1 DOWN: 切换到 WAN2"; /ip route set [find comment="Default via WAN1"] disabled=yes;
    :global tg_text "[WAN1] 线路故障，已切换到 WAN2"; /system script run tg_send;
  } \
  comment="监控 WAN1"

# WAN2 仅告警
/tool netwatch add host=$wan2CheckHost interval=10s timeout=3s \
  up-script={ :log info "WAN2 UP: 备用线路可用"; } \
  down-script={ 
    :log error "WAN2 DOWN: 备用线路故障！";
    :global tg_text "[警告] WAN2 备用线路故障！"; /system script run tg_send;
  } \
  comment="监控 WAN2"

# ========================================
# 第十二阶段：Telegram（可保留内置 tool 以便手测）
# ========================================
:log info "步骤 12/18: Telegram..."
:if ([/tool telegram bot find name=mybot] != "") do={ /tool telegram bot remove [find name=mybot] }
:if ([/tool telegram chat find name=mychannel] != "") do={ /tool telegram chat remove [find name=mychannel] }
:if ($telegramBotToken != "YOUR_BOT_TOKEN_HERE") do={
  /tool telegram bot add name=mybot token=$telegramBotToken
  /tool telegram chat add name=mychannel chat-id=$telegramChatID bot=mybot
  :log info "  - 已配置内置 Telegram（用于手动测试）；正式通知走 tg_send/tg_senddoc"
} else={ :log warning "  - 未配置 Bot Token，TG 通知将被跳过" }

# ========================================
# 第十三阶段：日志
# ========================================
:log info "步骤 13/18: 日志..."
:foreach i in=[/system logging action find name~"firewall-disk|script-disk|remote-syslog"] do={ /system logging action remove $i }
/system logging action add name=firewall-disk target=disk disk-file-name=fw.log disk-file-count=5 disk-lines-per-file=2000
/system logging action add name=script-disk target=disk disk-file-name=script.log disk-file-count=3 disk-lines-per-file=1000
:if ($syslogServer != "192.168.2.10") do={
  /system logging action add name=remote-syslog target=remote remote=$syslogServer remote-port=514 syslog-facility=local1
}
:foreach i in=[/system logging find action~"firewall-disk|script-disk|remote-syslog"] do={ /system logging remove $i }
/system logging add topics=firewall action=firewall-disk prefix="FW|"
/system logging add topics=script action=script-disk prefix="SCRIPT|"
:if ($syslogServer != "192.168.2.10") do={ /system logging add topics=error,critical action=remote-syslog }

# NTP & 时区（兼容写法）
:do { /system ntp client set enabled=yes primary-ntp=1.1.1.1 secondary-ntp=223.5.5.5 } on-error={ :do { /system/ntp/client set enabled=yes servers=1.1.1.1,223.5.5.5 } on-error={} }
 /system clock set time-zone-name=Asia/Seoul

# ========================================
# 第十四阶段：服务面
# ========================================
:log info "步骤 14/18: 服务面..."
/ip ssh set strong-crypto=yes always-allow-password-login=no
/ip service set ssh address=0.0.0.0/0 port=$sshPort disabled=no comment="SSH 由防火墙+敲门控制"
/ip service set winbox address=$winboxAllowedIPs port=$winboxPort disabled=no
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set www-ssl disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/tool mac-server set allowed-interface-list=LAN
/tool mac-server mac-winbox set allowed-interface-list=LAN

# ========================================
# 第十五阶段：自动备份（支持话题群通知/可选文档直发）
# ========================================
:log info "步骤 15/18: 备份..."
/system script add name=backup_to_tg policy=read,write,policy,test,ftp,sensitive source={
    :global telegramBotToken
    :global telegramChatID
    :global tgSendFiles

    :if ($telegramBotToken = "YOUR_BOT_TOKEN_HERE") do={ :log warning "未配置 TG，跳过备份通知"; :return }

    # 时间戳
    :local d [/system clock get date]; :local t [/system clock get time]
    :local stamp ($d . "_" . $t)
    :while ([:find $stamp " "] != nil) do={ :set stamp ([:pick $stamp 0 [:find $stamp " "]] . "_" . [:pick $stamp ([:find $stamp " "] + 1) [:len $stamp]]) }
    :while ([:find $stamp "/"] != nil) do={ :set stamp ([:pick $stamp 0 [:find $stamp "/"]] . "-" . [:pick $stamp ([:find $stamp "/"] + 1) [:len $stamp]]) }
    :while ([:find $stamp ":"] != nil) do={ :set stamp ([:pick $stamp 0 [:find $stamp ":"]] . "-" . [:pick $stamp ([:find $stamp ":"] + 1) [:len $stamp]]) }

    :local expFile ("export-" . $stamp . ".rsc")
    :local bakFile ("backup-" . $stamp . ".backup")

    /export terse file=$expFile
    /system backup save name=$bakFile
    :delay 3s

    :local expSize "未知"; :local bakSize "未知"
    :if ([/file find name=$expFile] != "") do={ :set expSize ([/file get $expFile size] . " 字节") }
    :if ([/file find name=$bakFile] != "") do={ :set bakSize ([/file get $bakFile size] . " 字节") }

    :global tg_text ("[RouterOS 备份完成]\n导出: " . $expFile . "（" . $expSize . "）\n备份: " . $bakFile . "（" . $bakSize . "）")
    /system script run tg_send

    :if ($tgSendFiles = "yes") do={
        :local u1f ("url-" . $expFile); :local u2f ("url-" . $bakFile)
        :local u1 ""; :local u2 ""
        :do { /tool fetch http-method=put upload=yes src-path=$expFile url=("https://transfer.sh/" . $expFile) dst-path=$u1f check-certificate=no; :set u1 [/file get $u1f contents] } on-error={ :log warning "export 上传失败" }
        :do { /tool fetch http-method=put upload=yes src-path=$bakFile url=("https://transfer.sh/" . $bakFile) dst-path=$u2f check-certificate=no; :set u2 [/file get $u2f contents] } on-error={ :log warning "backup 上传失败" }
        :if ([:len $u1]>0) do={ :global tg_doc_url $u1; /system script run tg_senddoc }
        :if ([:len $u2]>0) do={ :global tg_doc_url $u2; /system script run tg_senddoc }
        :do { /file remove $u1f; /file remove $u2f } on-error={}
    }
}

# 每周日 03:00
/system scheduler add name=backup-to-tg interval=7d start-time=03:00:00 on-event="/system script run backup_to_tg" comment="每周自动备份并发送 TG"

# 扫描器清理
/system scheduler add name=cleanup-addresslist interval=1d start-time=02:00:00 comment="清理过期扫描器地址列表" on-event={
  :local count [:len [/ip firewall address-list find list=port-scanners]]
  :if ($count > 1000) do={
    :log warning "port-scanners > 1000，开始清理"
    :foreach i in=[/ip firewall address-list find list=port-scanners] do={
      :local timeout [/ip firewall address-list get $i timeout]
      :if ($timeout < 1d) do={ /ip firewall address-list remove $i }
    }
  }
}

# ========================================
# 第十六阶段：IPv6 基础
# ========================================
:if ($enableIPv6 = yes) do={
  :log info "步骤 16/18: IPv6 基础..."
  /ipv6 settings set accept-router-advertisements=yes accept-redirects=no forward=yes
  /ipv6 firewall mangle add action=change-mss chain=forward new-mss=clamp-to-pmtu out-interface-list=WAN passthrough=yes protocol=tcp tcp-flags=syn
}

# ========================================
# 第十七阶段：连接跟踪
# ========================================
:log info "步骤 17/18: 连接跟踪..."
/ip firewall connection tracking set enabled=yes tcp-established-timeout=1d tcp-close-timeout=10s udp-timeout=10s udp-stream-timeout=3m icmp-timeout=10s generic-timeout=10m

# ========================================
# 第十八阶段：收尾与校验（发送到话题群）
# ========================================
:log info "步骤 18/18: 完成"
:local activeCount [:len [/ip route find comment="Default via WAN1" disabled=no]]
:local activeWan "WAN2 (WAN1 故障或禁用)"
:if ($activeCount > 0) do={ :set activeWan "WAN1" }

:global tg_text ("[部署完成]\n"
  . "LAN: " . $lanSubnet . "\n"
  . ($enableIPv6 = yes ? ("LANv6: " . $lanSubnetV6 . "\n") : "")
  . "SSH(路由器): " . $sshPort . "（需端口敲门）\n"
  . "SSH映射: " . $mappedSSHPort . " -> " . $mappedSSHTarget . ":22\n"
  . "WinBox: " . $winboxPort . "\n"
  . "当前活动线路: " . $activeWan . "\n"
  . (([:len $geoipAllowedCountries] > 0) ? ("GeoIP: " . $geoipAllowedCountries . "\n") : "")
  . "话题群 ChatID: " . $telegramChatID . " / TopicID: " . $telegramTopicID
)
/system script run tg_send

:put "==============================================="
:put "🎉 部署完成（支持把消息发到带话题的群组）"
:put "群组 chat_id = $telegramChatID"
:put "话题 message_thread_id = $telegramTopicID"
:put "如需修改话题，只改 telegramTopicID 即可，无需改其它逻辑。"
:put "==============================================="
