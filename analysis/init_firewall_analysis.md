# `scripts/init.rsc` 防火墙与安全优化复盘

本文对更新后的 `scripts/init.rsc` 初始化脚本进行复盘，聚焦于 RAW → Filter → NAT → Mangle 的分层防御逻辑、服务面加固、IPv6 策略与运维自动化改进。所有结论均基于脚本最新版本的静态审阅与逻辑推演。

## 架构概览
- **RAW 前置阻断。** 在进入连接跟踪前即丢弃全局黑名单、RFC1918 与 Bogon 源，同时新增 `connection-state=invalid` 快速丢弃，压缩 conntrack 压力。【F:scripts/init.rsc†L161-L179】
- **敲门 + 管理面速率控制。** 敲门三段加入 `limit` 与日志前缀，成功后再通过 RAW/Filter 双层放行 Winbox，防止口令枚举。【F:scripts/init.rsc†L188-L223】
- **WireGuard 智能防护。** 若启用监听端口，则依序放行 EST/REL、白名单地址、速率受控的 NEW 报文，溢出流量自动拉黑并记录日志，避免 UDP 暴力敲门。【F:scripts/init.rsc†L202-L211】
- **输入/转发链硬化。** 引入 SYN Flood 连接计数封禁、ICMP 严格限速、默认丢弃前日志上报，并维持端口扫描 PSD 黑名单机制。【F:scripts/init.rsc†L217-L248】
- **服务面收敛。** SSH 仅允许 `lanSubnet`，其他远程服务全部禁用且启用强加密；MAC 服务与邻居发现仅开放在 LAN。【F:scripts/init.rsc†L262-L279】
- **IPv6 完整基线。** 新增 IPv6 Bogon 地址表、ICMPv6 限速与默认丢弃日志，结合 link-local 过滤实现与 IPv4 对等的前置阻断。【F:scripts/init.rsc†L307-L325】
- **运维自动化。** conntrack `max-entries` 与超时一次性配置，备份任务可选生成 `.rsc`，并通过环境变量自动加载备份口令，最终汇总信息同步 Telegram。【F:scripts/init.rsc†L444-L542】

## 核心优化成果
1. **WireGuard 暴露面收紧。** 通过白名单 + 速率限制 + 黑名单联动实现外网访问的最小权限，满足之前高风险整改要求。【F:scripts/init.rsc†L202-L211】
2. **SYN/端口泛洪拦截。** 在 INPUT/FORWARD 链对 SYN 半连接计数并直接黑名单，配合 NEW 非 SYN 丢弃与 PSD 检测强化拒绝服务能力。【F:scripts/init.rsc†L224-L248】
3. **IPv6 地址伪造防护。** 补齐 `::/128`、`::1/128`、`::ffff:0:0/96`、`fc00::/7` 等 IPv6 Bogon 列表，在 RAW 层丢弃，确保双栈一致性。【F:scripts/init.rsc†L307-L315】
4. **备份与密钥管理。** 默认仅保留受保护的 `.backup` 文件，按需开启 `.rsc` 导出，并支持从 `/system script environment` 动态装载备份口令，杜绝脚本内硬编码。【F:scripts/init.rsc†L21-L34】【F:scripts/init.rsc†L458-L512】
5. **可观测性增强。** 敲门、WireGuard 异常、SYN Flood 与默认丢弃全部携带日志前缀，可与 `NotifyTG` 协作完成实时告警。【F:scripts/init.rsc†L190-L232】【F:scripts/init.rsc†L241-L248】【F:scripts/init.rsc†L320-L325】

## 安全优势清单
| 维度 | 优势 | 细节 |
| --- | --- | --- |
| 分层防御 | RAW + Filter 双段阻断 | 黑名单、RFC1918、Bogon、INVALID 在进入 conntrack 之前被清理，节省 CPU。【F:scripts/init.rsc†L161-L179】 |
| 管理面 | 敲门 + 限速续期 | 三段敲门带日志，Winbox 新建速率异常直接黑名单，合法连接自动续期。【F:scripts/init.rsc†L190-L223】 |
| VPN 防护 | WireGuard 黑白名单 | 白名单优先，NEW 报文限速，溢出流量黑名单并记录前缀 `WG-FLOOD`。【F:scripts/init.rsc†L202-L211】 |
| 攻击识别 | SYN/PSD 联动 | TCP SYN 连接数触顶或端口扫描行为均在 INPUT/FORWARD 链中被拉黑。【F:scripts/init.rsc†L224-L248】 |
| 服务面 | 最小暴露 | SSH 限定 `lanSubnet`，其它敏感服务完全关闭，SSH 强加密与禁转发并行。【F:scripts/init.rsc†L262-L275】 |
| IPv6 | 完整 Bogon + 日志 | IPv6 RAW 阶段过滤保留段，并对默认丢弃打日志，补齐双栈基线。【F:scripts/init.rsc†L307-L325】 |

## 残余风险与后续建议
1. **WireGuard 白名单运维。** 新增地址需要人工维护 `wgAllowList` 或结合外部自动化，建议配套通知脚本提示过期条目。默认占位符地址应在部署后清理，避免误判。【F:scripts/init.rsc†L188-L211】
2. **日志速率调优。** 丢弃/告警日志已加 `limit`，但高压攻击仍可能触发大量日志，建议在生产环境按需调整速率或引入远程日志缓冲。【F:scripts/init.rsc†L190-L232】【F:scripts/init.rsc†L241-L248】
3. **备份加密深化。** `.backup` 依赖 RouterOS 内置加密，若需离线存档建议结合外部加密或在上传前走安全通道。【F:scripts/init.rsc†L475-L512】
4. **IPv6 NDP 精细策略。** 目前允许全部 ICMPv6 类型，可进一步细化为 Router Advertisement、Neighbor Solicitation/Advertisement 等必要类型。 【F:scripts/init.rsc†L317-L321】

## 性能评估
- **FastTrack 精细化。** 仅对未做策略路由且流量小于 1 MiB 的连接启用 FastTrack，兼顾安全检查与吞吐。【F:scripts/init.rsc†L237-L248】
- **MSS Clamp 与 RAW 结合。** RAW 前置过滤与 SYN 阶段 MSS 调整配合，保障低延迟与兼容性。【F:scripts/init.rsc†L161-L179】【F:scripts/init.rsc†L254-L256】
- **conntrack 容量可调。** `max-entries` 与超时一体设置，可根据设备能力在线调整，减少会话溢出风险。【F:scripts/init.rsc†L444-L452】

## 评分
| 维度 | 评分 | 说明 |
| --- | --- | --- |
| 防火墙架构 | ⭐⭐⭐⭐⭐ | RAW/Filter/NAT/Mangle 配合完备，含 IPv4/IPv6 Bogon 与 INVALID 预丢。【F:scripts/init.rsc†L161-L248】【F:scripts/init.rsc†L307-L325】 |
| 服务面加固 | ⭐⭐⭐⭐⭐ | 仅保留必要服务，SSH 限定在 LAN 并启用强加密与禁转发。【F:scripts/init.rsc†L262-L275】 |
| 攻击防护 | ⭐⭐⭐⭐⭐ | 敲门限速、WireGuard 限流、SYN/PSD 黑名单共同覆盖扫描与 DDoS 攻击面。【F:scripts/init.rsc†L190-L248】【F:scripts/init.rsc†L202-L211】 |
| 密钥与备份管理 | ⭐⭐⭐⭐☆ | 支持环境口令与可选 `.rsc` 导出，仍建议结合外部加密。【F:scripts/init.rsc†L21-L34】【F:scripts/init.rsc†L458-L512】 |
| 日志审计 | ⭐⭐⭐⭐☆ | 默认丢弃、敲门与洪水检测均记录日志，可与 Telegram 通知联动。【F:scripts/init.rsc†L190-L248】【F:scripts/init.rsc†L320-L325】 |
| 综合 | ⭐⭐⭐⭐⭐ (92/100) | 主要高风险已关闭，剩余为运维与精细化调优事项。 |

## 后续行动建议
1. **自动化白名单管理。** 结合调度脚本或外部 CMDB，定期同步 WireGuard 与管理面白名单，避免手工维护遗漏。【F:scripts/init.rsc†L188-L211】
2. **完善 IPv6 ICMP 策略。** 根据业务需求拆分必需类型与日志策略，继续提升双栈可观测性。【F:scripts/init.rsc†L317-L325】
3. **集成远程日志。** 将 `SEC-DROP` 前缀流量集中输出到 syslog/SIEM，构建长期审计能力。【F:scripts/init.rsc†L231-L248】【F:scripts/init.rsc†L320-L325】
4. **密钥全生命周期管理。** 配合外部密钥库动态刷新 `backup.password` 与 WireGuard 私钥，形成闭环。

> 以上结论基于静态脚本分析；实际部署需结合设备性能、业务流量与合规要求进行灰度验证与观察。
