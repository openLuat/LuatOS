# 日志口用户自定义指令 demo

通过日志口扩展用户指令,由 Lua 脚本实现文件系统操作,无需额外 UART。
本 demo 展示:写 4K 文件、读回校验、枚举根目录、建目录、删目录。

## 组成

- `main.lua` — 设备端,`log.set_usercmd_cb` 注册指令处理
- `host/test_usercmd.py` — 上位机测试脚本(pyserial)

## 协议

PC→设备:0xA5 帧,`cmd=SOC_CMD_USER_CMD(19)`,`address`=子指令号,payload 见下表。

| address | 功能 | payload | 回复 |
|---|---|---|---|
| 1 | WRITE_BEGIN | path | `UC\|1\|ok/err` |
| 2 | WRITE_CHUNK | 4B LE offset + ≤64B 数据 | `UC\|2\|ok/err` |
| 3 | WRITE_END | 空 | `UC\|3\|ok/err\|<size>` |
| 4 | READ | path | `UC\|4\|b\|<total>` + N 行 `UC\|4\|h\|<hex>` + `UC\|4\|e` |
| 5 | LS | path | `UC\|5\|ok/err\|<逗号分隔条目>` |
| 6 | MKDIR | path | `UC\|6\|ok/err` |
| 7 | RMDIR | path | `UC\|7\|ok/err` |

设备→PC:统一文本行 `UC|<子指令>|...`,经 `log.usercmd_write` 以 LTOS 日志帧发出。

RX 单帧 payload 上限 102 字节,故写文件分块下发;回复为文本行,不受 4 对齐填充影响。

## 使用

```bash
# 刷机(固件 + 本 demo 脚本)
luatos-cli flash run --soc <LuatOS-SoC_*.soc> --port COM6 --script . --tail-log-secs 8
# 看到 "usercmd demo ready" 即成功

# 跑测试
python host/test_usercmd.py --port COM6
```
