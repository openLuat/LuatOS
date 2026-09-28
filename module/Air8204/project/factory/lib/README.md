# firmware/lib —— LuatOS 扩展库目录

本目录存放 Air8204 出厂固件所依赖的 LuatOS 扩展库（由 LuaTools 在烧录时按需打入脚本包）。

## 一、库清单与来源

| 库文件 | 用途 | 来源 | 状态 |
|--------|------|------|------|
| `libnet.lua` | 网络状态管理（socket 阻塞封装） | `factory/lib/libnet.lua`（Air8782 出厂固件） | ✅ 已放入 |
| `airlbs.lua` | 多基站/WiFi 定位（收费服务） | `factory/lib/airlbs.lua` | ✅ 已放入 |
| `httpplus.lua` | HTTP 客户端（excloud 文件上传依赖） | `factory/lib/httpplus.lua` | ✅ 已放入 |
| `excloud.lua` | AirCloud 云平台接入库 | `factory/lib/excloud.lua` | ⬜ 待复制 |
| `exmtn.lua` | 运维日志库（excloud 内部依赖） | `factory/lib/exmtn.lua` | ⬜ 待复制 |
| `exgnss.lua` | GNSS 扩展库（产测 GPSTEST 与出货 GNSS 定位共用） | `lib/exgnss.lua`（Air8204 产测固件） | ⬜ 待复制 |

## 二、待复制库的一键复制命令

在项目根目录（`8204出厂固件/`）下执行：

```bash
cp factory/lib/excloud.lua factory/lib/exmtn.lua firmware/lib/
cp lib/exgnss.lua firmware/lib/
```

复制完成后 `firmware/lib/` 应含 6 个库文件。

## 三、依赖关系

```
excloud.lua  ──依赖──▶  httpplus.lua、exmtn.lua
airlbs.lua   ──依赖──▶  libnet.lua
libnet.lua   ──依赖──▶  socket / sysplus（核心库，无需打包）
exgnss.lua   ──依赖──▶  libgnss（核心库，无需打包）
```

## 四、注意事项

1. **文件版本一致性**：`excloud.lua` / `exmtn.lua` / `httpplus.lua` 取自本项目的 `factory/lib/`（Air8782 出厂固件所用版本），三者版本互相匹配；请勿只替换其中某一个，以免接口不兼容。
2. **exgnss 只保留一份**：`firmware/lib/exgnss.lua` 同时服务于产测模式（`factory.lua` 的 `GPSTEST`）与出货模式（`normal.lua` 的 GNSS 定位），来自 Air8204 产测固件的 `lib/exgnss.lua`。
3. **exvib 不在本目录**：`exvib.lua` 使用 Air8204 硬件适配版（`i2cId=0`），随业务脚本放在 `firmware/code/` 目录，不放入扩展库目录。
4. **libfota3 不在本目录**：`libfota3.lua`（整机成品 FOTA 库）同样随业务脚本放在 `firmware/code/` 目录。
5. 如运行日志出现 `module 'xxx' not found`，按第一节的对应关系从 `factory/lib/` 或 `lib/` 补齐同名库文件即可。
