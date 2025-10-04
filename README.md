# Mikrotik_RouterOS

## 项目概览
Mikrotik_RouterOS 是一组可直接导入 MikroTik RouterOS 的自动化脚本，涵盖了双 WAN 初始化、防火墙安全基线、Cloudflare DDNS 与 Telegram 通知等常见需求，帮助你在最短时间内完成企业或家庭网关的加固与运维自动化。

## 目录结构
- `scripts/`：RouterOS 脚本集合。
  - `init.rsc`：双 WAN 初始化与安全基线脚本。
  - `ddns_cf.rsc`：Cloudflare 动态 DNS 更新脚本。
  - `notify.rsc`：Telegram 通知脚本。
- `firewall.md`：防火墙与安全加固的图文说明，可作为脚本执行前的手工核对表。

## 导入脚本前的安全加固
在导入任何自动化脚本之前，建议先按以下基线完成设备加固，详见《[firewall.md](firewall.md)》：
1. 创建 `LAN`、`WAN` 接口列表并将对应接口加入列表，便于后续规则统一管理。
2. 创建非 `admin` 的管理账号，并限制原始 `admin` 仅允许内网访问，以避免暴力破解风险。
3. 关闭不必要的邻居发现、带宽测试、DNS Cache、Proxy、SOCKS、UPnP、Cloud 等内建服务，减少暴露面。
4. 启用强加密的 SSH，并预先规划允许访问路由器的内网地址列表与基本防火墙策略，为脚本接管做好准备。

完成上述步骤后再上传脚本文件（`*.rsc`）到 RouterOS（可通过 Winbox/FTP/SFTP），确保环境处于可控状态。

## 双 WAN 初始化脚本（scripts/init.rsc）
该脚本会执行接口列表构建、双 WAN 负载监测、IPv4/IPv6 防火墙、GeoIP 白名单、端口敲门、Telegram 备份通知等 18 个阶段的自动化配置。

在导入前请检查并修改脚本顶部的全局变量：
- `lanInterface`、`lanSubnet`、`lanSubnetV6`：定义内部网络接口与地址范围。
- `adminPublicIP`、`winboxAllowedIPs`：白名单外网地址，用于 WinBox/SSH 管理。
- `wan1Interface`、`wan2Interface`、`wan1Gateway`、`wan2Gateway`、`wan1CheckHost`、`wan2CheckHost`：设置两个外网口与监测目标，用于链路检测与路由故障切换。
- `sshPort`、`mappedSSHPort`、`mappedSSHTarget`、`knockPort1-3`：自定义 SSH 管理端口与端口敲门流程。
- `telegramBotToken`、`telegramChatID`、`telegramTopicID`、`tgSendFiles`：配置 Telegram Bot 令牌、群组与话题，用于日志与备份通知。
- `geoipAllowedCountries`、`geoipDataSource`、`syslogServer`、`synFloodLimit`、`enableIPv6`：地理白名单、外部日志服务器、SYN Flood 防护与 IPv6 开关等附加功能。

**执行顺序建议：**
1. 上传并修改脚本变量。
2. 在 RouterOS 上执行 `/import file-name=scripts/init.rsc` 或通过 Winbox「System → Scripts → Import」导入脚本。
3. 脚本运行后，按日志提示确认 WAN 探测、地址列表与防火墙是否正确生成。
4. 若需自定义策略，可在脚本末尾追加自定义片段或通过 `/system script edit` 进行二次调整。

## Cloudflare DDNS（scripts/ddns_cf.rsc）
该脚本会监测指定接口的公网 IP 变化，并调用 Cloudflare API 更新 A 记录。

参数说明：
- `TOKEN`：Cloudflare API Token，最小权限需包含 `Zone → Zone → Read` 与 `Zone → DNS → Edit`。
- `ZONEID`：目标 Zone 的唯一 ID，可在 Cloudflare 仪表盘「概览」页面获取。
- `RECORDID`：待更新 DNS 记录的 ID，可通过 API 或控制台获取。
- `RECORDNAME`：需要自动更新的主机记录（例如 `vpn.example.com`）。
- `WANIF`：RouterOS 上用于获取公网 IP 的接口名称，脚本会从该接口的地址中抽取 IPv4。

**调度器示例：**
```shell
/system scheduler add name=cf-ddns interval=5m on-event="/system script run cf-ddns" comment="Cloudflare DDNS"
```
创建前请确保已将脚本保存为 `cf-ddns` 并授予 `read,write,test,policy` 权限，同时 RouterOS 需信任 Cloudflare 证书或在脚本中允许 `check-certificate=no`。

## Telegram 通知（scripts/notify.rsc）
该脚本提供一个 `sendNotify` 函数，可在 RouterOS 内部脚本或计划任务中调用。

参数说明：
- `TGBOTTOKEN`：Telegram Bot Token，需在 BotFather 创建后填入。
- `TGUSERID`：接收通知的用户或群组 ID，群组 ID 通常以 `-100` 开头。
- `TGAPIHOST`：Telegram API 访问域名，默认为 `https://api.telegram.org`，可用于自建反代场景。

**测试示例：**
```shell
/system script run sendNotify message="RouterOS 通知测试"
```
如未收到消息，请先在 Telegram 与 Bot 发起对话，或检查 RouterOS 的 DNS/HTTPS 访问能力。

## 常见问题 / 故障排查
- **脚本导入报错 `expected end of command`**：确认 RouterOS 版本 ≥ 7.6，并确保上传过程中文件未被转换为 Windows 回车符。
- **Cloudflare DDNS 无法更新**：检查 Token 权限、`WANIF` 接口是否运行，以及 RouterOS 是否能访问 `api.cloudflare.com`。
- **Telegram 无法发送**：确认 `TGBOTTOKEN` 与 `TGUSERID` 正确无误，RouterOS 能解析 DNS 并访问 Telegram API；必要时将 `TGAPIHOST` 指向可达的反向代理。

## 许可证
本仓库暂未附带独立的许可证文件，默认作者保留所有权利。若需在商业环境中使用，请与仓库维护者联系或遵循原始脚本头部的授权声明。

## 参考资料
- [Mikrotik RouterOS Help](https://help.mikrotik.com/docs/)
- 官方 RouterOS 文档与论坛，可获取最新的安全与部署最佳实践。
