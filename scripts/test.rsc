# ========================================
# Telegram 深度诊断脚本
# 请将完整输出截图或复制给我
# ========================================

:put "=========================================="
:put "  Telegram 深度诊断开始"
:put "=========================================="
:put ""

# -------------------- 配置检查 --------------------
:put "【1/7】配置检查"
:put "----------------------------------------"

:global tgToken "7333641003:AAH_Ws8nlBmtChp7XQQD55e4hTeqeO0Va2k"
:global tgChatId "-1002953925037"
:global tgTopicId "8"

:put ("Token 长度: " . [:len $tgToken])
:put ("Token 前10位: " . [:pick $tgToken 0 10])
:put ("ChatId: " . $tgChatId)
:put ("ChatId 类型: " . [:typeof $tgChatId])
:put ("TopicId: " . $tgTopicId)
:put ""

# -------------------- DNS 检查 --------------------
:put "【2/7】DNS 检查"
:put "----------------------------------------"
:put "当前 DNS 服务器:"
/ip dns print
:put ""

:put "测试 DNS 解析 api.telegram.org..."
:do {
  :local resolved [/ping api.telegram.org count=1 as-value]
  :put ("✓ DNS 解析成功")
  :put ("  响应时间: " . $resolved->"avg-rtt")
} on-error={
  :put "✗ DNS 解析失败"
  :put "  尝试手动设置 DNS:"
  :put "  /ip dns set servers=8.8.8.8,1.1.1.1"
}
:put ""

# -------------------- 网络连通性检查 --------------------
:put "【3/7】网络连通性检查"
:put "----------------------------------------"

# 测试 ICMP
:put "测试 ICMP (ping api.telegram.org)..."
:do {
  :local result [/ping api.telegram.org count=3 as-value]
  :put ("✓ ICMP 通: " . $result->"avg-rtt")
} on-error={
  :put "✗ ICMP 不通（可能被防火墙阻止）"
}
:put ""

# 测试 HTTPS 443
:put "测试 HTTPS 端口 443..."
:do {
  /tool fetch url="https://api.telegram.org" mode=https keep-result=no
  :put "✓ HTTPS 端口可达"
} on-error={
  :put "✗ HTTPS 端口不可达"
}
:put ""

# -------------------- 防火墙检查 --------------------
:put "【4/7】防火墙 OUTPUT 链检查"
:put "----------------------------------------"
:local outputRules [/ip firewall filter find where chain=output]
:if ([:len $outputRules] = 0) do={
  :put "✓ 无 OUTPUT 链规则（允许所有出站）"
} else={
  :put ("发现 " . [:len $outputRules] . " 条 OUTPUT 规则:")
  :foreach rid in=$outputRules do={
    :local action [/ip firewall filter get $rid action]
    :local comment [/ip firewall filter get $rid comment]
    :put ("  - Action: " . $action . " | Comment: " . $comment)
  }
  :put ""
  :put "建议：如果有 drop 规则，请添加允许 HTTPS 出站:"
  :put "/ip firewall filter add chain=output protocol=tcp dst-port=443 action=accept place-before=0"
}
:put ""

# -------------------- Telegram API 基础测试 --------------------
:put "【5/7】Telegram API 基础测试 (getMe)"
:put "----------------------------------------"
:local apiUrl ("https://api.telegram.org/bot" . $tgToken . "/getMe")
:put ("测试 URL: https://api.telegram.org/bot<hidden>/getMe")
:do {
  :local result [/tool fetch url=$apiUrl mode=https output=user as-value]
  :put ("HTTP Status: " . $result->"status")
  :put ("Response: " . $result->"data")
  
  :if ($result->"data" ~ "\"ok\":true") do={
    :put "✓ Bot Token 有效"
  } else={
    :put "✗ Bot Token 无效或 API 返回错误"
  }
} on-error={
  :put "✗ 请求失败（网络或 Token 问题）"
}
:put ""

# -------------------- 证书检查 --------------------
:put "【6/7】SSL 证书检查"
:put "----------------------------------------"
:put "已安装的证书:"
/certificate print detail where name~"Telegram|telegram|TG|tg"
:if ([:len [/certificate find]] = 0) do={
  :put "警告：未安装任何证书"
  :put "尝试导入 Let's Encrypt 证书..."
  :do {
    /tool fetch url="https://letsencrypt.org/certs/lets-encrypt-r3.pem" mode=https dst-path=le-r3.pem
    :delay 2s
    /certificate import file-name=le-r3.pem passphrase=""
    :put "✓ 证书导入成功"
  } on-error={
    :put "✗ 证书导入失败"
  }
}
:put ""

# -------------------- 完整消息发送测试 --------------------
:put "【7/7】完整消息发送测试"
:put "----------------------------------------"

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

:local testMsg "RouterOS TG Test"
:local m [$ReplaceAll $testMsg " " "%20"]
:local sendUrl ("https://api.telegram.org/bot" . $tgToken . "/sendMessage")
:local sendData ("chat_id=" . $tgChatId . "&text=" . $m)

:put ("发送 URL: https://api.telegram.org/bot<hidden>/sendMessage")
:put ("ChatID: " . $tgChatId)
:put ("消息: " . $testMsg)
:put ""

:put "尝试发送（3次重试）..."
:local retry 3
:local lastError ""
:while ($retry > 0) do={
  :put ("第 " . (4 - $retry) . " 次尝试...")
  :do {
    :local result [/tool fetch url=$sendUrl http-method=post http-data=$sendData mode=https output=user as-value]
    :put ("  HTTP Status: " . $result->"status")
    :put ("  Response Data: " . $result->"data")
    
    :if ($result->"data" ~ "\"ok\":true") do={
      :put ""
      :put "✓✓✓ 消息发送成功！✓✓✓"
      :put "请检查你的 Telegram 是否收到消息"
      :set retry 0
    } else={
      :set lastError $result->"data"
      :if ($retry > 1) do={
        :put "  ✗ 发送失败，2秒后重试..."
        :delay 2s
      }
      :set retry ($retry - 1)
    }
  } on-error={
    :set lastError "Network error or timeout"
    :put ("  ✗ 网络错误: " . $lastError)
    :if ($retry > 1) do={
      :put "  2秒后重试..."
      :delay 2s
    }
    :set retry ($retry - 1)
  }
}

:if ([:len $lastError] > 0) do={
  :put ""
  :put "✗✗✗ 最终发送失败 ✗✗✗"
  :put ("最后错误: " . $lastError)
}

:put ""
:put "=========================================="
:put "  诊断完成"
:put "=========================================="
:put ""
:put "如果仍有问题，请提供以下信息:"
:put "1. 完整的诊断输出（截图或文字）"
:put "2. RouterOS 版本"
:put "3. 路由器所在地区（是否在中国大陆）"
:put "4. Token 获取方式（BotFather）"
:put "5. ChatID 获取方式（私聊/群组/话题）"
