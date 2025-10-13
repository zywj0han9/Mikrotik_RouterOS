# =========================================================
# RouterOS v7.20.1 v5.3.1
# =========================================================

:log info "=== 启动：v7.20.1 初始化脚本 v5.3.1 ==="
:put "=== 启动：v7.20.1 初始化脚本 v5.3.1 ==="

# ---------- 全局参数（保持不变）----------
:global lanInterface "Lan"
:global wan1Interface "Wan1"
:global wan2Interface "Wan2"
:global lanSubnet "192.168.2.0/24"
:global lanGateway "192.168.2.1"
:global lanDhcpPool "192.168.2.10-192.168.2.200"
:global dnsA "192.168.2.3"
:global dnsB "192.168.2.254"
:global wan1PPPoEUser ""
:global wan1PPPoEPass ""
:global wan2PPPoEUser ""
:global wan2PPPoEPass ""
:global probeWan1 "8.8.8.8"
:global probeWan2 "1.1.1.1"
:global knockWindow "60s"
:global mgmtAllowMinutes 30
:global debounceThreshold 3
:global wgListenPort 51820
:global wgAllowList "wg-allow"
:global lanV6GW "fd00::1"
:global pbrList "PBR_WAN2"
:global conntrackMax 524288
:global backupSecretKey "backup.password"
:global backupPassword ""
:global backupMaxKeep 40
:global backupExportRsc false
:global dropLogPrefix "SEC-DROP"

# 读取备份口令（若在 /system script environment 中预置）
:local envSecret [/system script environment find where name=$backupSecretKey]
:if ([:len $envSecret] > 0) do={
  :set backupPassword [/system script environment get $envSecret value-name=value]
}

# ---------- 工具函数 ----------
:global ReplaceAll do={
  :local s [:tostr $1]
  :local from [:tostr $2]
  :local to [:tostr $3]
  :local out ""
  :local p 0
  :while ([:len $s] > 0) do={
    :set p [:find $s $from]
    :if ($p = nil) do={
      :set out ($out . $s)
      :set s ""
    } else={
      :set out ($out . [:pick $s 0 $p] . $to)
      :set s [:pick $s ($p + [:len $from]) [:len $s]]
    }
  }
  :return $out
}

# ---------- 接口列表（幂等创建）----------
:log info "创建接口列表 WAN / LAN（幂等）"
:put "创建接口列表 WAN / LAN（幂等）"

:if ([:len [/interface/list find where name=WAN]] = 0) do={ /interface/list add name=WAN }
:if ([:len [/interface/list find where name=LAN]] = 0) do={ /interface/list add name=LAN }
/interface/list/member remove [find list=WAN]
/interface/list/member remove [find list=LAN]
/interface/list/member add list=WAN interface=$wan1Interface
/interface/list/member add list=WAN interface=$wan2Interface
/interface/list/member add list=LAN interface=$lanInterface

# ---------- 【修复】清理旧防火墙与地址列表 ----------
:log info "彻底清理旧配置"
:put "彻底清理旧配置"

:foreach i in=[/ip firewall filter find where !dynamic] do={ :do { /ip firewall filter remove $i } on-error={} }
:foreach i in=[/ip firewall mangle find where !dynamic] do={ :do { /ip firewall mangle remove $i } on-error={} }
:foreach i in=[/ip firewall nat find where !dynamic] do={ :do { /ip firewall nat remove $i } on-error={} }
:foreach i in=[/ip firewall raw find where !dynamic] do={ :do { /ip firewall raw remove $i } on-error={} }

:foreach i in=[/ip firewall address-list find where !dynamic] do={ :do { /ip firewall address-list remove $i } on-error={} }
/ip firewall layer7-protocol remove [find]

:foreach i in=[/ipv6 firewall filter find where !dynamic] do={ :do { /ipv6 firewall filter remove $i } on-error={} }
:foreach i in=[/ipv6 firewall raw find where !dynamic] do={ :do { /ipv6 firewall raw remove $i } on-error={} }
:foreach i in=[/ipv6 firewall address-list find where !dynamic] do={ :do { /ipv6 firewall address-list remove $i } on-error={} }

# ---------- LAN IPv4 与 DHCP ----------
:log info "配置 LAN IPv4 与 DHCP"
:put "配置 LAN IPv4 与 DHCP"

/ip address remove [find where interface=$lanInterface]
/ip address add address=($lanGateway . "/24") interface=$lanInterface comment="AUTO-LAN-GW"

/ip pool remove [find where name="LAN-POOL"]
/ip pool add name="LAN-POOL" ranges=$lanDhcpPool

/ip dhcp-server remove [find where interface=$lanInterface]
/ip dhcp-server add name="LAN-DHCP" interface=$lanInterface address-pool="LAN-POOL" lease-time=12h authoritative=after-2sec-delay
/ip dhcp-server network remove [find where gateway=$lanGateway]
/ip dhcp-server network add address=$lanSubnet gateway=$lanGateway dns-server=($dnsA . "," . $dnsB) comment="AUTO-LAN-NET"
/ip dhcp-server enable "LAN-DHCP"

/ip dns set servers=($dnsA . "," . $dnsB) allow-remote-requests=no use-doh-server="" verify-doh-cert=no

# ---------- WAN 获取：DHCP 优先 + 可选 PPPoE ----------
:log info "创建 WAN DHCP client"
:put "创建 WAN DHCP client"

/ip dhcp-client remove [find where interface=$wan1Interface]
/ip dhcp-client remove [find where interface=$wan2Interface]
/ip dhcp-client add interface=$wan1Interface add-default-route=no use-peer-dns=no use-peer-ntp=no comment="AUTO-DHCP-WAN1"
/ip dhcp-client add interface=$wan2Interface add-default-route=no use-peer-dns=no use-peer-ntp=no comment="AUTO-DHCP-WAN2"

:if ([:len $wan1PPPoEUser] > 0) do={
  :log info "创建 PPPoE-WAN1"
  /interface pppoe-client remove [find where name="pppoe-wan1"]
  /interface pppoe-client add name="pppoe-wan1" interface=$wan1Interface user=$wan1PPPoEUser password=$wan1PPPoEPass add-default-route=no use-peer-dns=no
  /interface/list/member add list=WAN interface=pppoe-wan1
}
:if ([:len $wan2PPPoEUser] > 0) do={
  :log info "创建 PPPoE-WAN2"
  /interface pppoe-client remove [find where name="pppoe-wan2"]
  /interface pppoe-client add name="pppoe-wan2" interface=$wan2Interface user=$wan2PPPoEUser password=$wan2PPPoEPass add-default-route=no use-peer-dns=no
  /interface/list/member add list=WAN interface=pppoe-wan2
}

# ---------- 路由表 + 递归主备 ----------
:log info "创建路由表与递归主备"
:put "创建路由表与递归主备"

:foreach rt in=[/routing table find where name="to-wan1" or name="to-wan2"] do={ /routing table remove $rt }
/routing table add name=to-wan1 fib
/routing table add name=to-wan2 fib

:foreach r in=[/ip route find where comment~"^AUTO-"] do={ /ip route remove $r }

/ip route add dst-address=($probeWan1 . "/32") gateway=$wan1Interface routing-table=main comment="AUTO-PROBE-WAN1"
/ip route add dst-address=($probeWan2 . "/32") gateway=$wan2Interface routing-table=main comment="AUTO-PROBE-WAN2"
/ip route add dst-address=0.0.0.0/0 gateway=$probeWan1 distance=1 check-gateway=ping comment="AUTO-DEF-WAN1"
/ip route add dst-address=0.0.0.0/0 gateway=$probeWan2 distance=2 check-gateway=ping comment="AUTO-DEF-WAN2"
/ip route add dst-address=($probeWan1 . "/32") gateway=$wan1Interface routing-table=to-wan1 comment="AUTO-PBR-PROBE1"
/ip route add dst-address=($probeWan2 . "/32") gateway=$wan2Interface routing-table=to-wan2 comment="AUTO-PBR-PROBE2"
/ip route add dst-address=0.0.0.0/0 gateway=$probeWan1 routing-table=to-wan1 comment="AUTO-PBR-DEF1"
/ip route add dst-address=0.0.0.0/0 gateway=$probeWan2 routing-table=to-wan2 comment="AUTO-PBR-DEF2"

# ---------- NAT（含泛化 Hairpin）----------
:log info "配置 NAT 与泛化 Hairpin"
:put "配置 NAT 与泛化 Hairpin"

/ip firewall nat add chain=srcnat out-interface-list=WAN action=masquerade comment="AUTO-MASQ"
/ip firewall nat add chain=srcnat src-address=$lanSubnet dst-address-type=local action=masquerade comment="HAIRPIN for all port forwards"

# ---------- 【修复】RAW 全局黑名单 + 完整 Bogon 防护 ----------
:log info "配置 RAW 预过滤（含完整 Bogon）"
:put "配置 RAW 预过滤（含完整 Bogon）"

:if ([:len [/ip firewall address-list find where list=global_blacklist and address=0.0.0.0]] = 0) do={
  /ip firewall address-list add list=global_blacklist address=0.0.0.0 comment="占位符-勿删"
}
/ip firewall raw add chain=prerouting in-interface-list=WAN src-address-list=global_blacklist action=drop comment="[最优先] 全局黑名单"
/ip firewall raw add chain=prerouting connection-state=invalid action=drop comment="RAW 预丢 INVALID"

:if ([:len [/ip firewall address-list find where list=RFC1918 and address=10.0.0.0/8]] = 0) do={ /ip firewall address-list add list=RFC1918 address=10.0.0.0/8 }
:if ([:len [/ip firewall address-list find where list=RFC1918 and address=172.16.0.0/12]] = 0) do={ /ip firewall address-list add list=RFC1918 address=172.16.0.0/12 }
:if ([:len [/ip firewall address-list find where list=RFC1918 and address=192.168.0.0/16]] = 0) do={ /ip firewall address-list add list=RFC1918 address=192.168.0.0/16 }

:local bogonList {"0.0.0.0/8"="本机网络";"100.64.0.0/10"="运营商级NAT";"127.0.0.0/8"="回环地址";"169.254.0.0/16"="链路本地";"192.0.2.0/24"="测试网段1";"198.18.0.0/15"="基准测试";"198.51.100.0/24"="测试网段2";"203.0.113.0/24"="测试网段3";"224.0.0.0/4"="组播";"240.0.0.0/4"="保留段";"255.255.255.255/32"="广播地址"}
:foreach addr,desc in=$bogonList do={
:if ([:len [/ip firewall address-list find where list=BOGON and address=$addr]] = 0) do={
    /ip firewall address-list add list=BOGON address=$addr comment=$desc
  }
}

/ip firewall raw add chain=prerouting in-interface-list=WAN src-address-list=RFC1918 action=drop comment="私网源自 WAN 直丢"
/ip firewall raw add chain=prerouting in-interface-list=WAN src-address-list=BOGON action=drop comment="Bogon 源自 WAN 直丢"

# ---------- SSH 管理（无端口转发）----------
:log info "取消 SSH 端口转发，保留敲门白名单"
:put "取消 SSH 端口转发，保留敲门白名单"

:if ([:len [/ip firewall address-list find where list=knock1 and address=0.0.0.0]] = 0) do={ /ip firewall address-list add list=knock1 timeout=$knockWindow address=0.0.0.0 comment="占位符-勿删" }
:if ([:len [/ip firewall address-list find where list=knock2 and address=0.0.0.0]] = 0) do={ /ip firewall address-list add list=knock2 timeout=$knockWindow address=0.0.0.0 comment="占位符-勿删" }
:if ([:len [/ip firewall address-list find where list=mgmt-allow and address=0.0.0.0]] = 0) do={ /ip firewall address-list add list=mgmt-allow timeout=($mgmtAllowMinutes . "m") address=0.0.0.0 comment="占位符-勿删" }
:if ([:len [/ip firewall address-list find where list=$wgAllowList and address=0.0.0.0]] = 0) do={ /ip firewall address-list add list=$wgAllowList timeout=none address=0.0.0.0 comment="占位符-勿删" }

/ip firewall filter add chain=input protocol=tcp dst-port=30000 in-interface-list=WAN limit=5/1m,10 log=yes log-prefix="KNOCK1 " action=add-src-to-address-list address-list=knock1 address-list-timeout=$knockWindow comment="Knock 1"
/ip firewall filter add chain=input protocol=tcp dst-port=31000 in-interface-list=WAN src-address-list=knock1 limit=5/1m,10 log=yes log-prefix="KNOCK2 " action=add-src-to-address-list address-list=knock2 address-list-timeout=$knockWindow comment="Knock 2"
/ip firewall filter add chain=input protocol=tcp dst-port=32000 in-interface-list=WAN src-address-list=knock2 limit=5/1m,10 log=yes log-prefix="KNOCK3 " action=add-src-to-address-list address-list=mgmt-allow address-list-timeout=($mgmtAllowMinutes . "m") comment="Knock 3 => mgmt-allow"

# ---------- WAN Winbox（敲门放行）----------
:log info "配置 WAN Winbox"
:put "配置 WAN Winbox"

/ip service set winbox address=0.0.0.0/0
/ip firewall raw add chain=prerouting in-interface-list=WAN src-address-list=mgmt-allow protocol=tcp dst-port=8291 action=accept comment="WAN Winbox 敲门 RAW"
/ip firewall raw add chain=prerouting in-interface-list=WAN protocol=tcp dst-port=8291 action=drop comment="WAN Winbox 未授权 RAW 预丢"

# ---------- WireGuard 入口防护（可选）----------
:if ($wgListenPort > 0) do={
  :log info ("配置 WireGuard 端口防护（" . $wgListenPort . ")")
  :put ("配置 WireGuard 端口防护（" . $wgListenPort . ")")

  /ip firewall filter add chain=input in-interface-list=WAN protocol=udp dst-port=$wgListenPort connection-state=established,related action=accept comment="WireGuard EST/REL"
  /ip firewall filter add chain=input in-interface-list=WAN protocol=udp dst-port=$wgListenPort src-address-list=$wgAllowList action=accept comment="WireGuard 白名单"
  /ip firewall filter add chain=input in-interface-list=WAN protocol=udp dst-port=$wgListenPort connection-state=new limit=20/5s,40 action=accept comment="WireGuard 新建速率限制"
  /ip firewall filter add chain=input in-interface-list=WAN protocol=udp dst-port=$wgListenPort action=add-src-to-address-list address-list=global_blacklist address-list-timeout=1h log=yes log-prefix="WG-FLOOD " comment="WireGuard Flood -> 黑名单"
}

# ---------- Filter：INPUT 基线 + NEW非SYN硬化 ----------
:log info "配置 Filter 规则与 IDS"
:put "配置 Filter 规则与 IDS"

/ip firewall filter add chain=input connection-state=established,related action=accept comment="INPUT EST/REL"
/ip firewall filter add chain=input in-interface-list=LAN action=accept comment="LAN -> Router"
/ip firewall filter add chain=input protocol=icmp limit=5,10 action=accept comment="INPUT ICMP limit"

/ip firewall filter add chain=input in-interface-list=WAN protocol=tcp dst-port=8291 src-address-list=mgmt-allow action=add-src-to-address-list address-list=mgmt-allow address-list-timeout=($mgmtAllowMinutes . "m") comment="WAN Winbox 续期"
/ip firewall filter add chain=input in-interface-list=WAN protocol=tcp dst-port=8291 src-address-list=mgmt-allow action=accept comment="WAN Winbox 放行"
/ip firewall filter add chain=input in-interface-list=WAN protocol=tcp dst-port=8291 connection-state=new limit=5/10s,10 action=add-src-to-address-list address-list=global_blacklist address-list-timeout=1d comment="WAN Winbox 新建速率异常"
/ip firewall filter add chain=input in-interface-list=WAN protocol=tcp tcp-flags=syn connection-state=new connection-limit=50,32 action=add-src-to-address-list address-list=global_blacklist address-list-timeout=1d log=yes log-prefix="SYN-FLOOD " comment="SYN Flood -> 黑名单"

/ip firewall filter add chain=input in-interface-list=WAN protocol=tcp connection-state=new tcp-flags=!syn action=drop comment="WAN INPUT：丢弃 NEW 非 SYN"

/ip firewall filter add chain=input protocol=tcp psd=21,3s,3,1 action=add-src-to-address-list address-list=global_blacklist address-list-timeout=1d comment="端口扫描到黑名单"
/ip firewall filter add chain=input src-address-list=global_blacklist action=drop comment="INPUT 全局黑名单"
/ip firewall filter add chain=input connection-state=invalid action=drop comment="INPUT INVALID"
/ip firewall filter add chain=input in-interface-list=WAN action=log log-prefix=($dropLogPrefix . " INPUT ") limit=10/1m,20 comment="INPUT 默认丢弃日志"
/ip firewall filter add chain=input in-interface-list=WAN action=drop comment="INPUT 默认丢弃 WAN"

# ---------- Filter：FORWARD ----------
/ip firewall filter add chain=forward in-interface-list=WAN protocol=tcp connection-state=new tcp-flags=!syn action=drop comment="WAN FORWARD：丢弃 NEW 非 SYN"

/ip firewall filter add chain=forward connection-state=established,related connection-mark=pbr-conn action=accept comment="PBR EST/REL 不FastTrack"
/ip firewall filter add chain=forward connection-state=established,related connection-mark=!pbr-conn connection-nat-state=!dstnat connection-bytes=0-1048576 action=fasttrack-connection comment="FASTTRACK（跳过DSTNAT）"
/ip firewall filter add chain=forward connection-state=established,related action=accept comment="FWD EST/REL 兜底"

/ip firewall filter add chain=forward protocol=icmp limit=20,40 action=accept comment="FWD ICMP limit"
/ip firewall filter add chain=forward in-interface-list=WAN protocol=tcp tcp-flags=syn connection-state=new connection-limit=80,32 action=add-src-to-address-list address-list=global_blacklist address-list-timeout=1d log=yes log-prefix="FWD-SYN " comment="FWD SYN Flood -> 黑名单"
/ip firewall filter add chain=forward connection-state=invalid action=drop comment="FWD INVALID"
/ip firewall filter add chain=forward in-interface-list=LAN out-interface-list=WAN action=accept comment="LAN -> WAN"
/ip firewall filter add chain=forward in-interface-list=WAN out-interface-list=LAN connection-nat-state=dstnat action=accept comment="端口转发回流"
/ip firewall filter add chain=forward in-interface-list=LAN out-interface-list=LAN connection-nat-state=dstnat action=accept comment="Hairpin LAN↔LAN"
/ip firewall filter add chain=forward action=log log-prefix=($dropLogPrefix . " FWD ") limit=10/1m,20 comment="FWD 默认丢弃日志"
/ip firewall filter add chain=forward action=drop comment="FWD 默认丢弃"

# ---------- Mangle：PBR + MSS ----------
:log info "配置 Mangle（PBR + MSS）"
:put "配置 Mangle（PBR + MSS）"

/ip firewall mangle add chain=prerouting src-address-list=$pbrList connection-state=new action=mark-connection new-connection-mark=pbr-conn passthrough=yes comment="PBR 连接标记"
/ip firewall mangle add chain=prerouting connection-mark=pbr-conn action=mark-routing new-routing-mark=to-wan2 passthrough=yes comment="PBR 路由标记"
/ip firewall mangle add chain=forward protocol=tcp tcp-flags=syn action=change-mss new-mss=clamp-to-pmtu comment="MSS Clamp"

# ---------- 服务面加固 ----------
:log info "加固 RouterOS 服务面"
:put "加固 RouterOS 服务面"

/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set www-ssl disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set ssh address=$lanSubnet
/ip firewall service-port set sip disabled=yes
/ip firewall service-port set ftp disabled=yes
/ip firewall service-port set tftp disabled=yes
/ip firewall service-port set pptp disabled=yes

/ip ssh set strong-crypto=yes forwarding-enabled=no always-allow-password-login=no host-key-size=4096

/tool mac-server set allowed-interface-list=LAN
/tool mac-server mac-winbox set allowed-interface-list=LAN
/tool mac-server ping set enabled=no
/ip neighbor discovery-settings set discover-interface-list=LAN

# ---------- IPv6 基线 ----------
:log info "配置 IPv6"
:put "配置 IPv6"

/ipv6 settings set accept-redirects=no accept-router-advertisements=yes max-neighbor-entries=8192 soft-max-neighbor-entries=6144
/ipv6 address remove [find where interface=$lanInterface]
/ipv6 address add address=($lanV6GW . "/64") advertise=yes interface=$lanInterface

/ipv6 dhcp-client remove [find where interface=$wan1Interface]
/ipv6 dhcp-client remove [find where interface=$wan2Interface]
:if ([:len $wan1PPPoEUser] = 0) do={
  /ipv6 dhcp-client add interface=$wan1Interface add-default-route=yes default-route-distance=1 request=address,prefix pool-name=ipv6-wan1 pool-prefix-length=64
}
:if ([:len $wan2PPPoEUser] = 0) do={
  /ipv6 dhcp-client add interface=$wan2Interface add-default-route=yes default-route-distance=2 request=address,prefix pool-name=ipv6-wan2 pool-prefix-length=64
}

:if ([:len $wan1PPPoEUser] > 0) do={
  /ipv6 dhcp-client remove [find where interface=pppoe-wan1]
  /ipv6 dhcp-client add interface=pppoe-wan1 add-default-route=yes default-route-distance=1 request=address,prefix pool-name=ipv6-pppoe1 pool-prefix-length=64
}
:if ([:len $wan2PPPoEUser] > 0) do={
  /ipv6 dhcp-client remove [find where interface=pppoe-wan2]
  /ipv6 dhcp-client add interface=pppoe-wan2 add-default-route=yes default-route-distance=2 request=address,prefix pool-name=ipv6-pppoe2 pool-prefix-length=64
}

/ipv6 firewall raw add chain=prerouting in-interface-list=WAN src-address=fe80::/10 protocol=icmpv6 action=accept comment="允许 WAN ICMPv6 link-local"
/ipv6 firewall raw add chain=prerouting in-interface-list=WAN src-address=fe80::/10 action=drop comment="丢弃 WAN 非 ICMPv6 的 link-local"
:local bogon6List {"::/128"="未指定地址";"::1/128"="回环";"::ffff:0:0/96"="IPv4映射";"fc00::/7"="ULA"}
:foreach addr,desc in=$bogon6List do={
  :if ([:len [/ipv6 firewall address-list find where list=IPV6-BOGON and address=$addr]] = 0) do={
    /ipv6 firewall address-list add list=IPV6-BOGON address=$addr comment=$desc
  }
}
/ipv6 firewall raw add chain=prerouting in-interface-list=WAN src-address-list=IPV6-BOGON action=drop comment="IPv6 Bogon 源自 WAN 直丢"

/ipv6 firewall filter add chain=input connection-state=established,related action=accept
/ipv6 firewall filter add chain=input protocol=icmpv6 limit=20,40 action=accept comment="IPv6 ICMP limit"
/ipv6 firewall filter add chain=input in-interface-list=LAN action=accept
/ipv6 firewall filter add chain=input action=log log-prefix=($dropLogPrefix . " V6-IN ") limit=5/1m,10 comment="IPv6 INPUT 默认丢弃日志"
/ipv6 firewall filter add chain=input action=drop comment="IPv6 INPUT 默认丢弃"
/ipv6 firewall filter add chain=forward connection-state=established,related action=accept
/ipv6 firewall filter add chain=forward in-interface-list=LAN out-interface-list=WAN action=accept
/ipv6 firewall filter add chain=forward action=log log-prefix=($dropLogPrefix . " V6-FWD ") limit=5/1m,10 comment="IPv6 FWD 默认丢弃日志"
/ipv6 firewall filter add chain=forward action=drop comment="IPv6 FWD 默认丢弃"

# ---------- Netwatch + 去抖健康播报 ----------
:log info "创建 Netwatch 与巡检脚本"
:put "创建 Netwatch 与巡检脚本"

/tool netwatch remove [find where host=$probeWan1]
/tool netwatch remove [find where host=$probeWan2]
/tool netwatch add host=$probeWan1 interval=00:00:15 timeout=2s up-script="/system script run AUTO-WAN-HEALTH" down-script="/system script run AUTO-WAN-HEALTH"
/tool netwatch add host=$probeWan2 interval=00:00:15 timeout=2s up-script="/system script run AUTO-WAN-HEALTH" down-script="/system script run AUTO-WAN-HEALTH"

/system script remove [find where name="AUTO-WAN-HEALTH"]
/system script add name="AUTO-WAN-HEALTH" policy=read,write,test source={
  :global NotifyTG
  :global wan1Interface
  :global wan2Interface
  :global probeWan1
  :global probeWan2
  :global lastActiveWan
  :global debounceTarget
  :global debounceCount
  :global debounceThreshold
  :if ([:typeof $lastActiveWan] = "nothing") do={ :set lastActiveWan "" }
  :if ([:typeof $debounceTarget] = "nothing") do={ :set debounceTarget "" }
  :if ([:typeof $debounceCount] = "nothing") do={ :set debounceCount 0 }

  :local nowD [/system clock get date]
  :local nowT [/system clock get time]

  :local a1 [/ip route get [find where comment="AUTO-DEF-WAN1"] value-name=active]
  :local a2 [/ip route get [find where comment="AUTO-DEF-WAN2"] value-name=active]

  :local act "UNKNOWN"
  :if ($a1 = true && $a2 != true) do={ :set act "WAN1" }
  :if ($a1 != true && $a2 = true) do={ :set act "WAN2" }
  :if ($a1 = true && $a2 = true) do={ :set act "WAN1" }

  :local ip1 ""; :local ip2 ""
  :local id1 [/ip address find where interface=$wan1Interface]
  :if ([:len $id1] > 0) do={ :set ip1 [/ip address get $id1 value-name=address] }
  :local id2 [/ip address find where interface=$wan2Interface]
  :if ([:len $id2] > 0) do={ :set ip2 [/ip address get $id2 value-name=address] }

  :local s1 "unknown"; :local s2 "unknown"
  :local nw1 [/tool netwatch find where host=$probeWan1]
  :if ([:len $nw1] > 0) do={ :set s1 [/tool netwatch get $nw1 value-name=status] }
  :local nw2 [/tool netwatch find where host=$probeWan2]
  :if ([:len $nw2] > 0) do={ :set s2 [/tool netwatch get $nw2 value-name=status] }

  :if ($act = $lastActiveWan) do={
    :set debounceCount 0
    :set debounceTarget $act
  } else={
    :if ($debounceTarget != $act) do={
      :set debounceTarget $act
      :set debounceCount 1
    } else={
      :set debounceCount ($debounceCount + 1)
    }
    :if ($debounceCount >= $debounceThreshold) do={
      :set lastActiveWan $act
      :set debounceCount 0

      :local title ""
      :if ($act = "WAN1") do={ :set title "【WAN 切回主链路】" }
      :if ($act = "WAN2") do={ :set title "【WAN 切到备用链路】" }
      :if ($act = "UNKNOWN") do={ :set title "【WAN 状态不明】" }

      :local msg ($title . "\n当前默认出口：" . $act . "\n探测状态：WAN1(" . $probeWan1 . ")=" . $s1 . "，WAN2(" . $probeWan2 . ")=" . $s2 . "\n地址：WAN1=" . $ip1 . " | WAN2=" . $ip2 . "\n时间：" . $nowD . " " . $nowT)
      :log warning $msg
      :put $msg
      $NotifyTG $msg ""
      # 切换后的一些恢复动作
      :if ($act = "WAN2") do={
        :do { /ip dhcp-client renew [find where interface=$wan1Interface] } on-error={}
        :if ([:len [/interface pppoe-client find where name="pppoe-wan1"]] > 0) do={
          :do { /interface pppoe-client disable pppoe-wan1 } on-error={}
          :delay 1s
          :do { /interface pppoe-client enable pppoe-wan1 } on-error={}
        }
        :do { /ip dns cache flush } on-error={}
      }
      :if ($act = "WAN1") do={
        :do { /ip dhcp-client renew [find where interface=$wan2Interface] } on-error={}
        :if ([:len [/interface pppoe-client find where name="pppoe-wan2"]] > 0) do={
          :do { /interface pppoe-client disable pppoe-wan2 } on-error={}
          :delay 1s
          :do { /interface pppoe-client enable pppoe-wan2 } on-error={}
        }
      }
    }
  }
}

# ---------- PPPoE 探测网关修复 ----------
:log info "配置 PPPoE 探测网关修复"
:put "配置 PPPoE 探测网关修复"

/system script remove [find where name="FIX-PROBE-GW"]
/system script add name="FIX-PROBE-GW" source={
  :global wan1Interface
  :global wan2Interface
  :local g1 $wan1Interface
  :local g2 $wan2Interface
  :if ([:len [/interface pppoe-client find where name="pppoe-wan1" and running=yes]] > 0) do={ :set g1 "pppoe-wan1" }
  :if ([:len [/interface pppoe-client find where name="pppoe-wan2" and running=yes]] > 0) do={ :set g2 "pppoe-wan2" }
  /ip route set [find where comment="AUTO-PROBE-WAN1"] gateway=$g1
  /ip route set [find where comment="AUTO-PROBE-WAN2"] gateway=$g2
  /ip route set [find where comment="AUTO-PBR-PROBE1"] gateway=$g1
  /ip route set [find where comment="AUTO-PBR-PROBE2"] gateway=$g2
}

/system scheduler remove [find where name="AUTO-FIX-PROBE-GW"]
/system scheduler add name="AUTO-FIX-PROBE-GW" interval=10m on-event="/system script run FIX-PROBE-GW" start-time=startup

# ---------- conntrack ----------
:log info "调整连接跟踪容量"
:put "调整连接跟踪容量"

/ip firewall connection tracking set \
  max-entries=$conntrackMax \
  tcp-established-timeout=1d \
  tcp-close-wait-timeout=10s \
  tcp-fin-wait-timeout=10s \
  tcp-time-wait-timeout=10s \
  udp-timeout=30s \
  udp-stream-timeout=3m
:log warning ("conntrack max-entries = " . $conntrackMax)

# ---------- 备份：每日 + 安全轮转 ----------
:log info "生成备份脚本与计划任务"
:put "生成备份脚本与计划任务"

/system script remove [find where name="AUTO-BACKUP-NOW"]
/system scheduler remove [find where name="AUTO-BACKUP-DAILY"]
/system script add name="AUTO-BACKUP-NOW" policy=read,write,test source={
  :global NotifyTG
  :global ReplaceAll
  :global backupPassword
  :global backupMaxKeep
  :global backupExportRsc

  :local d [/system clock get date]
  :local t [/system clock get time]
  :local dx [$ReplaceAll $d " " "-"]
  :set dx [$ReplaceAll $dx "/" "-"]
  :local tx [$ReplaceAll $t ":" ""]
  :local tag ($dx . "_" . $tx)
  :local bkName ("bk-" . $tag)

  :do {
    :if ([:len $backupPassword] > 0) do={ /system backup save name=$bkName password=$backupPassword } else={ /system backup save name=$bkName }
  } on-error={ :log error ("备份失败 .backup " . $bkName) }

  :if ($backupExportRsc = true) do={
    :do { /export file=$bkName compact } on-error={ :log error ("导出失败 .rsc " . $bkName) }
  } else={
    :log info "跳过 .rsc 导出（backupExportRsc=false）"
  }

  :local flist [/file find where name~"^bk-"]
  :local count [:len $flist]
  :if ($count > $backupMaxKeep) do={
    :local toDelete ($count - $backupMaxKeep)
    :local deleted 0
    :while ($deleted < $toDelete) do={
      :local flist [/file find where name~"^bk-"]
      :if ([:len $flist] = 0) do={ :set deleted $toDelete } else={
        :local oldestId [:pick $flist 0]
        :local oldestName [/file get $oldestId name]
        :foreach fid in=$flist do={
          :local fname [/file get $fid name]
          :if ($fname < $oldestName) do={ :set oldestName $fname; :set oldestId $fid }
        }
        :log info ("删除旧备份: " . $oldestName)
        :do { /file remove $oldestId } on-error={ :log error ("删除失败: " . $oldestName) }
        :set deleted ($deleted + 1)
      }
    }
  }

  :local includeList ".backup"
  :if ($backupExportRsc = true) do={ :set includeList ($includeList . " + .rsc") }
  :local msg ("【RouterOS 备份完成】\n名称：" . $bkName . "\n包含：" . $includeList . "\n保留数量：<=" . $backupMaxKeep)
  :log info $msg
  :put $msg
  $NotifyTG $msg ""
}
/system scheduler add name="AUTO-BACKUP-DAILY" start-time=03:30:00 interval=1d on-event="/system script run AUTO-BACKUP-NOW"

# ---------- 汇总播报 + 初始化 ----------
:log info "应用完成：开始汇总播报"
:put "应用完成：开始汇总播报"

:global lastActiveWan ""
/system script run FIX-PROBE-GW
/system script run AUTO-WAN-HEALTH
/system script run AUTO-BACKUP-NOW

:local ip1r ""; :local ip2r ""; :local lpr ""
:local id1r [/ip address find where interface=$wan1Interface]
:if ([:len $id1r] > 0) do={ :set ip1r [/ip address get $id1r value-name=address] }
:local id2r [/ip address find where interface=$wan2Interface]
:if ([:len $id2r] > 0) do={ :set ip2r [/ip address get $id2r value-name=address] }
:local idlr [/ip address find where interface=$lanInterface]
:if ([:len $idlr] > 0) do={ :set lpr [/ip address get $idlr value-name=address] }
:local wgSummary "未启用"
:if ($wgListenPort > 0) do={ :set wgSummary ("端口=" . $wgListenPort . " (限流+黑名单)") }
:local backupSummary ".backup"
:if ($backupExportRsc = true) do={ :set backupSummary ($backupSummary . "+.rsc") }

:local nowD2 [/system clock get date]
:local nowT2 [/system clock get time]
:local summary ("【初始化完成 v5.3.1-FIX】\nLAN=" . $lpr . "\nWAN1=" . $ip1r . "\nWAN2=" . $ip2r . "\nSSH转发=已取消\nSSH来源=" . $lanSubnet . "\nWireGuard=" . $wgSummary . "\n敲门放行=" . $mgmtAllowMinutes . "分钟（含限速日志）\nWAN管理：仅Winbox（8291）\nSYN/端口扫描：自动黑名单\nconntrack=" . $conntrackMax . "\n备份保留=" . $backupMaxKeep . "（包含=" . $backupSummary . "）\n去抖阈值=" . $debounceThreshold . "\nBogon防护：IPv4+IPv6 完整\nHairpin：泛化DSTNAT\n时间：" . $nowD2 . " " . $nowT2)
:log info $summary
:put $summary
:global NotifyTG
$NotifyTG $summary ""

:log info "=== 一键配置完成==="
:put "=== 一键配置完成==="

