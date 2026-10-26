# 8784 Luatools 烧录目录

当前应用：`Air8784_Factory`，版本 `001.000.018`。
源码目录：`D:\Air\Documents\SIP_web\8784\factory\user`。

## 烧录方式

## 查询当前版本

通过 TCP Tag19 下发裸文本 `version`（忽略大小写及首尾空白）。设备通过 Tag1027 返回 ASCII 字符串，类型为 3，内容为运行时 `_G.PROJECT .. "_" .. _G.VERSION`。回复保留请求流水号，不包装 JSON，也不额外返回 Tag20。通话及播报期间可查询；队列满时记录 `VERSION_REPLY_QUEUE_FULL`，稍后重新查询。

与上游相同的本地扩展库已清理。标准依赖从 `D:\Air\Git_Project\LuatOS\script\libs` 自动或手动加入；务必确认下载列表包含原版 `excloud.lua`。本目录中的项目定制库仍需添加，不能只烧录剩余业务文件而漏掉标准依赖。

1. 在 Luatools 中选择适配本机硬件的底层固件。本目录不含底层固件；语音播报需要固件提供 `audio_v2.tts_pcm_start/read/stop` 接口。
2. 添加根目录的 `main.lua` 和所有功能子目录中的脚本及证书。不要只添加根目录文件；避免重复添加同名库。
3. 功能子目录仅用于电脑端分类，设备按文件原名加载，例如 `/luadb/excloud.luac` 或 `/luadb/excloud.lua`，不保留电脑端的功能子目录。
4. `README.md` 不需要烧录。启动后确认日志中的应用版本为 `001.000.018`。

## 目录用途

| 目录 | 内容 |
| --- | --- |
| `single` | 单 SIP 通话与音频业务 |
| `cc` | SIP 与蜂窝通话桥接 |
| `task` | 网页任务、按键、模式与任务调度 |
| `cloud` | AirCloud 指令、配置、状态和 TCP 适配 |
| `audio` | 通话、配置、开机及远程 TTS 播报 |
| `factory` | 产测与复测业务 |
| `netdrv` | 网络驱动 |
| `ota` | 固件更新业务 |
| `lib` | 扩展库 |
| `certs` | 证书资源 |

## 当前版本说明

- `001.000.018` 补齐 excloud 的静态打包依赖声明。重新添加最新脚本后，确认 Luatools 下载列表包含 `D:\Air\Git_Project\LuatOS\script\libs\excloud.lua`，避免沿用旧列表漏烧动态依赖。

- 支持远程 `play_tts`、配置保存成功提示、开机完成提示，以及首次 SIP 注册和断线恢复后的就绪提示。通话优先，周期续注册不重复播报。
- CC 失败收尾保留释放确认；释放异常、通话或音频未就绪时可能返回 `audio_busy`，可查看具体阻塞原因。
- AirCloud 仅用 TCP，不改变 SIP 的传输选择。`D:\Air\Git_Project\LuatOS\script\libs\excloud.lua` 为上游原版，必要兼容由 `cloud/aircloud_tcp_adapter.lua` 实现，两者均须烧录。
- 其他扩展库保留项目已有内容，不建议直接覆盖整个 `lib` 目录。
- 桌面测试已通过；真机仍需验证字节码加载、云端刷新/配置、通话及重启后的播报顺序。

## 重新同步

在工作区运行 `python 8784/factory/user/prepare_download.py`。
脚本更新并逐文件校验烧录内容，保留此 README。请修改源码后重新同步，避免仅修改烧录副本；版本和行为变化需同步维护本文。
