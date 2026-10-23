# zenoh-pico PC 侧装配与主机回归

这里放 zenoh-pico 1.9.0 的 **PC 专有**部分：可选装配靠 `bsp/pc/xmake.lua` 里的
`LUAT_USE_ZENOH_PICO=y` 开关，主机回归脚本/真实对端/官方 unix 后端在本目录。
固件用的组件（配置头、Lua 绑定、generic 系统/TCP 适配、裁剪后的核心源码）在
`components/zenoh_pico`，本目录内容不进固件。

| 文件 | 用途 |
|------|------|
| `run_host.py` | 主机回归入口：编译并运行 host 桥 + 真实 peer，可选接 zenohd 1.9.0 跑互通 |
| `host_main.c` | 主机侧模拟固件的 C 入口（替换 RTOS/网络适配层） |
| `host_port.c` | 主机侧端口：真实 POSIX socket → 模块 generic TCP 接口 |
| `peer.c` | 官方 zenoh-pico 客户端对端（用 unix 后端），验证 Pub/Sub 与 Get/Queryable |
| `host_test.lua` / `host_get_test.lua` / `host_get_race.lua` | 三套 Lua 回归脚本 |
| `TEST_RESULTS.md` | 主机回归的实际证据与限制说明 |
| `unix_backend/` | `src/system/unix/system.c`、`network.c` 与 `platform/unix.h`，上游逐字节副本，只给 peer 用 |

## 用法

```sh
# 只编译检查
python3 bsp/pc/zenoh_pico/run_host.py --lua-root /path/to/lua-prefix

# 连真实 router 跑互通（需要 zenohd 1.9.0）
python3 bsp/pc/zenoh_pico/run_host.py --lua-root /path/to/lua-prefix --router /path/to/zenohd

# Get/Queryable 完整回归、关闭交错回归
python3 bsp/pc/zenoh_pico/run_host.py --get-tests ...
python3 bsp/pc/zenoh_pico/run_host.py --race-tests both ...
```

默认编译 `components/zenoh_pico/zenoh-pico` 里随库入库的 1.9.0 裁剪源码（核对 `version.txt`，并打印源码清单摘要）；
需要对照另一份 1.9.0 工作树时加 `--zenoh-root ../zenoh-pico`，此时按固定提交 `e83d39b` 做 Git 来源门禁。

判断通过看 `HOST_PASS` / `HOST_EXIT 0` / `PEER_EXIT 0` / `INTEROP_PASS`；只看到 `BUILD_PASS` 说明只编译没跑互通。
