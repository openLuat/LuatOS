# 8783H Luatools 烧录目录

当前应用：`SIP_CC_BRIDGE_PCM`，版本 `1.1.20`。
源码目录：`D:\Air\Documents\SIP_web\8783H\sip_cc_bridge_pcm`。

## 烧录方式

## 查询当前版本

通过 TCP Tag19 下发裸文本 `version`（忽略大小写及首尾空白）。设备通过 Tag1027 返回 ASCII 字符串，类型为 3，内容为运行时 `_G.PROJECT .. "_" .. _G.VERSION`。回复保留请求流水号，不包装 JSON，也不额外返回 Tag20。通话期间可查询；队列满时记录 `VERSION_REPLY_QUEUE_FULL`，稍后重新查询。

## 远程升级（1.1.19）

- 源码 `main.lua` 的 `PRODUCT_KEY` 尚待配置，请填写该设备对应的合宙 IoT 项目 Key，再运行同步脚本。留空时不会启动升级，并返回 `fota_not_configured`。
- 必须从 `D:\Air\Git_Project\LuatOS\script\libs` 添加原版 `libfota3.lua`，同时烧录 `ota/update.lua`。扩展库不做修改。
- 首次检测及每 8 小时检测由 libfota3 管理；重启保留检测周期。
- Web JSON 指令：`{"id":"ota-001","cmd":"update"}`，也支持 `cmd="fota"`。可用字段 19 或 1281；同一 ID 不重复触发。
- 从 1.1.20 起兼容 Tag19 裸文本 `fota` / `update`（忽略首尾空白及大小写），以及 `{"type":"update"}`、`{"command":"fota"}` 等旧入口。回复走 Tag20，并保留 TCP 回复流水号。裸文本每次下发视为新的检查请求；需要去重时使用带 ID 的 JSON 指令。
- `stage=check_requested` 仅表示请求检查，最终升级结果以 `fota` 日志及重启后的版本为准。忙时返回 `device_busy`；下载或重启确认遇到忙状态时取消本轮确认，空闲后以新 ID 重试。
- 在 IoT 平台上传匹配设备的旧、新 `.soc` 量产包，配置基础版本、目标版本和单台测试 IMEI，等待升级包生成完成后下发指令。先保持设备空闲，验证下载、重启、`upgrade_success` 及 SIP/CC 通话。
- 尚未进行真机 FOTA 验收。下载及重启确认有空闲检查，但不是整个升级期间禁止新来电的互斥机制。

### 下载文件

1. 在 Luatools 中选择适配硬件及本项目 PCM 桥接接口的底层固件。本目录不含底层固件。
2. 添加根目录的 `main.lua`，以及各功能子目录中的全部脚本、音频和证书文件。不要只添加根目录文件。
3. 子目录仅用于电脑端分类，烧录后使用文件原名加载，例如 `/luadb/excloud.luac` 或 `/luadb/excloud.lua`；不要在设备内保留这些功能子目录。
4. 本目录的 `lib` 仅保留与上游不同的项目库。同版标准库已删除，使用 Luatools 自动添加依赖功能，或从 `D:\Air\Git_Project\LuatOS\script\libs` 手动添加。务必确认下载列表包含上游 `excloud.lua`；仅复制本目录剩余文件而不添加标准依赖，会再次缺库。避免重复添加同名库。
5. `README.md` 仅供阅读，不需要烧录。烧录完成后查看开机日志，确认版本为 `1.1.18`。

## 目录用途

| 目录 | 内容 |
| --- | --- |
| `sip_cc` | SIP、蜂窝通话、PCM 桥接及配置 |
| `cloud` | AirCloud 指令、状态、配置和 TCP 适配 |
| `netdrv` | 网络驱动 |
| `lib` | 与上游不同的项目扩展库 |
| `audio` | 音频资源 |
| `certs` | 证书资源 |

## 当前版本说明

- `1.1.18` 修复动态加载 excloud 时 Luatools 依赖扫描漏收库的问题。请重新添加最新脚本，确认下载列表包含 `D:\Air\Git_Project\LuatOS\script\libs\excloud.lua`，不要只沿用旧下载列表。仅电脑目录中存在文件，不代表已经烧录。

- CC 明确拨号失败后收尾回空闲；无法确认释放时等待 10 秒，超时报告 `cc_release_error`，不会强行伪造空闲。PCM/SDK 资源释放检查继续保留。
- AirCloud 仅使用 TCP；SIP 的 UDP/TCP/TLS 配置独立。
- `excloud.lua` 与指定上游原版一致，必要兼容由 `cloud/aircloud_tcp_adapter.lua` 处理。两者都必须烧录。
- 桌面测试已通过；真机仍需验证字节码加载、云端指令、无语音业务卡拨号失败收尾及正常语音卡通话。

## 重新同步

在工作区运行 `python 8783H/sip_cc_bridge_pcm/prepare_download.py`。
同步脚本更新并逐文件校验烧录内容，保留此 README；修改业务代码时请修改源码，再重新同步。说明中的版本和行为变化需同步维护。
