# zenoh-pico 主机回归与测试结果

上一版 Air8000 固件的连接、发布订阅及 4096B Get 基础测试已经通过。下表记录本 PR 修复后的主机结果。构建基于 2026-11-16 核对的 master 22920c0，使用 LuatOS Lua 5.3/64、zenohd 1.9.0 和 ASan/UBSan。

| 范围 | 实测结果 |
|---|---|
| 基础互通 | 发布订阅、二进制收发、连续短读写及显式关闭后重连通过 |
| 查询 | 22 项 Get 生命周期检查通过，含连续 375 次 4096B Get。双 owner 中最后一个释放时发送 Final；本地取消只产生一个业务终态，随后收到的真实 Final 可单独查询 |
| 大包与资源 | 22 项大包回归通过，覆盖最高 256KiB 的发布订阅、请求和应答、超限拒绝、关闭重开与额度回收 |
| 关闭与竞态 | 队列满并遇到一次 Lua 构表失败后，关闭回执仍只回调一次。打开与关闭、命令接纳与关闭交错的测试通过 |
| 认证 | 匿名、正确凭据、128 字节边界、错误用户名、错误密码、缺凭据及缺挑战共七个场景均符合预期；SHA3/HMAC 的31组向量通过 |
| 会话健康 | 对端租期为6秒、20秒时，实际采用6秒、10秒；空闲时能看到真实 KeepAlive，关闭后旧连接的收包记录失效 |

七组回归的启动程序均退出 0。另有 21 条查询资源路径和 10 条分片路径通过。用本机原生回显测六种载荷，每种预热8次、正式64次并逐字节校验。固定每次最多读取257B、写入511B，4KiB、64KiB、256KiB 的往返中位数分别为41.8ms、459ms、1.787s。目标 BSP 的 RAM、任务栈和实机长稳待新固件复测。

复验方式（每次使用新的run目录；不要同时占用17447）：

```sh
python3 bsp/pc/zenoh_pico/run_host.py --lua-root /path/to/luatos-lua53-prefix --build-dir /tmp/zp-build --sanitize
python3 bsp/pc/zenoh_pico/run_host.py --lua-root /path/to/luatos-lua53-prefix --build-dir /tmp/zp-build --sanitize --skip-build --router /path/to/zenohd --run-dir /tmp/zp-base
# 逐项增加 --get-tests / --payload-tests / --final-tests / --race-tests both / --open-race-tests
python3 bsp/pc/zenoh_pico/run_auth.py --build-dir /tmp/zp-build --router /path/to/zenohd --out /tmp/zp-auth
```

固件配置见 [Air8000 出包要求](../../../components/zenoh_pico/AIR8000_PROFILE_REQUEST.md)。
