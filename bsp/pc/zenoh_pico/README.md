# zenoh-pico PC 侧装配与主机回归

这里放 zenoh-pico 1.9.0 的 **PC 专有**部分：可选装配靠 `bsp/pc/xmake.lua` 里的
`LUAT_USE_ZENOH_PICO=y` 开关，主机回归脚本/真实对端/官方 unix 后端在本目录。
固件用的组件（配置头、Lua 绑定、generic 系统/TCP 适配、裁剪后的核心源码）在
`components/zenoh_pico`，本目录内容不进固件。

| 文件 | 用途 |
|------|------|
| `run_host.py` | 主机回归入口：编译并运行 host 桥 + 真实 peer，可选接 zenohd 1.9.0 跑互通 |
| `host_main.c` | 主机侧模拟固件的 C 入口（替换 RTOS/网络适配层） |
| `host_port.c` | 主机侧端口：真实 POSIX socket → 模块 generic TCP 接口；有限网络通知模型 |
| `host_transport_test.c` | Unix 专用的独立发送接纳/通知合同测试，不进默认装配 |
| `peer.c` | 官方 zenoh-pico 客户端对端（用 unix 后端），验证 Pub/Sub 与 Get/Queryable |
| `host_test.lua` / `host_get_test.lua` / `host_get_race.lua` | 三套 Lua 回归脚本 |
| `TEST_RESULTS.md` | 主机回归的实际证据与限制说明 |
| `unix_backend/` | Unix系统/网络源码及其专用头，上游逐字节副本，只给 peer 用 |

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

默认基础套件为17项：原16项加真实握手半帧失败。故障用例保留完整error/closed序列，比较首错快照和原SDK错误码，核失败后停止写入、显式重开和资源回收。Get19项和两项关闭交错分别运行，不将两种选择参数混用。

`unix_backend/include/zenoh-pico/system/common/system_error.h`和`utils/mutex.h`补齐Unix peer编译所需头；它们与上游1.9.0提交`e83d39b4415f6897e8d6c3b3b651ca88a05f4a17`同路径`include/`原文逐字节一致，保留原文许可信息，沿用组件的[第三方许可](../../../components/zenoh_pico/THIRD_PARTY.md)。只在现有PC peer include路径使用，不添加至目标固件源表。此前默认vendored构建缺这两文件而失败；用外部完整SDK偶然绕过缺头不能作为默认路径已修复的证据。

## 发送接纳与通知合同回归（Unix，独立入口）

`_z_send_tcp` 使用 `network_tx(..., timeout=0)`，合法返回0/1时只推进实际接纳字节；
100ms是一次SDK写入的总接纳截止，不再在每个短写中等待TCP完成/ACK。
Pico专用worker以零等待、每次最多16条消费network状态机已处理的通知副本；
迟到旧通知不直接改变新socket状态，未知事件ID显式记首错。目标BSP仍须核实同一API合同。

从仓库根目录手工运行（产物目录放在源码树外；不修改默认装配）：

```sh
mkdir -p ../pico-transport-build
clang -std=c11 -Wall -Wextra -Werror -O1 -g \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  -DZENOH_GENERIC -DZENOH_C_STANDARD=11 -DZENOH_COMPILER_CLANG \
  -Icomponents/zenoh_pico/include -Icomponents/zenoh_pico/zenoh-pico/include \
  -Iluat/include -Icomponents/common -Icomponents/network/adapter \
  components/zenoh_pico/src/zenoh_luatos_tcp.c \
  bsp/pc/zenoh_pico/host_transport_test.c -o ../pico-transport-build/transport
python3 -c 'import subprocess; subprocess.run(["../pico-transport-build/transport"], check=True, timeout=15)'
```

判断通过看 `TRANSPORT_CONTRACT_DONE checks=13 failures=0` 和真实退出0。测试用真实非阻塞
socketpair核对4096B内容，模型覆盖rc0/1、17B短接纳、完成延迟、零进展总截止、
部分失败不重复发送、非法返回/计数、16槽通知溢出反例、RX消费和重开迟到旧通知。
它不产生真实目标RTOS或TCP ACK；PC完整SDK互通也不能替代191D原4096B Get验收。
修改这三份C后，完整重编17项，再用同一二进制分别跑19 Get与2交错；不要沿用旧binary。

## 有界接收进展与原1800ms场景（Unix，独立入口）

`_z_read_tcp` 在一次调用中合并最多16次已有数据的正数短读，无数据立即返回已有前缀，
不等待凑包、不扩大载荷/缓冲/查询期限。发生错误立即冻结首错；此前已确认的前缀先交SDK，
下一次I/O直接失败。每次至多16个非阻塞API调用，不代表已验证目标RTOS最坏执行时间。

独立合同沿用上节全部编译参数，将末尾 `host_transport_test.c` 改为 `host_rx_test.c`、
输出名改为 `../pico-transport-build/rx`。运行该产物应同时看到
`TRANSPORT_CONTRACT_DONE checks=13 failures=0`、`RX_CONTRACT_DONE checks=5 failures=0`
及真实退出0。真实非阻塞socketpair核4096字节守恒、16次上限、空读、前缀后空读、
前缀后错误与错误后停止；不是目标驱动的硬件验证。

原Get回归使用5000ms；它不能代替4096B/1800ms原场景。先显式指定产物目录完整重编，再在三个终端按顺序运行以下独立用例（从仓库根；端口须空闲）：

```sh
python3 bsp/pc/zenoh_pico/run_host.py --lua-root /path/to/lua-prefix \
  --build-dir ../pico-transport-build --sanitize
# 终端1：本机隔离router
/path/to/zenohd --listen tcp/127.0.0.1:17447 --no-multicast-scouting \
  --adminspace-permissions none --cfg scouting/gossip/enabled:false --cfg plugins:{}
# 终端2：原PC对端，使用同一前缀
../pico-transport-build/zenoh_peer tcp/127.0.0.1:17447 test/pico-g08 --get
# 终端3：直接公共API，不经过业务Lua适配器
../pico-transport-build/zenoh_host_test bsp/pc/zenoh_pico/host_get_1800.lua \
  tcp/127.0.0.1:17447 test/pico-g08
```

以 `run_host.py --help` 的实际build目录为准；不要复用修改前二进制。
两轮分别4096B PUT精确回显→4096B Query/source=lua/1800ms→两份原值回复和唯一completed，
再核短PUT、原peer反向Query双回复/Final和关闭。通过标志
`G08_HOST_PASS rounds=2 payload=4096 timeout_ms=1800 scope=host_not_target`，
host/peer均应正常退出0；结束本次自有router。PC桥固定短读7B/短写17B，目标效果仍须原板验证。
