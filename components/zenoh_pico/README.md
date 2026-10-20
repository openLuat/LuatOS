# zenoh-pico：可选原生 TCP client（Draft）

为 LuatOS 提供外置官方 zenoh-pico 1.9.0 的最小原生 Lua 绑定。默认关闭；独立库名 `zenohpico`，不替换已有 Lua `zenoh` 实现。

本贡献含 generic 系统/TCP 适配、Lua 绑定、PC 可选装配、独立真实对端与最小 demo。本贡献实现Get发起和Queryable应答；当前实际证据见 [TEST_RESULTS.md](TEST_RESULTS.md)。我们负责继续完成目标测试和修复，目标构建需要对应BSP环境；主机测试不代表设备已可运行。

## 固定依赖

- zenoh-pico **1.9.0**：`e83d39b4415f6897e8d6c3b3b651ca88a05f4a17`。
- 测试 router：zenohd **1.9.0**。
- 原第三方核心源码不修改、不整仓复制；两个派生公共头保留原版权和许可，见 [THIRD_PARTY.md](THIRD_PARTY.md)。

```sh
git clone --branch 1.9.0 https://github.com/eclipse-zenoh/zenoh-pico.git ../zenoh-pico
git -C ../zenoh-pico checkout --detach e83d39b4415f6897e8d6c3b3b651ca88a05f4a17
```

1.9.0 的裁剪限制：保持 `Z_RUNTIME_MAX_TASKS=64`，否则 executor.c 的默认容量与 runtime.h 的结构布局不一致。保留上游默认 `BATCHING=1`，Lua 不提供 batching API；`INTEREST=0` 避开该版本不完整的 MATCHING/多播组合。不要混用1.10的头或平台入口。

## API与结果语义

目标LuatOS通过内建注册表提供全局`zenohpico`；使用`rawget(_G, "zenohpico")`检查实际成员。部分目标的内建库不写`package.loaded`，直接`require("zenohpico")`会报文件模块不存在，不能据此判库缺失。`socket`/`wlan`可能是可索引rotable userdata，应按所需函数和常量检查，不强制容器类型为table。PC测试VM的标准加载行为不替代此目标合同。

所有函数从唯一 Lua VM 调用。`open` 返回句柄或 `nil, code`；其余命令返回本地命令/订阅 ID 或 `nil, code`。成功入队、`published`、对端实收是三个不同阶段。

```lua
local z = assert(rawget(_G, "zenohpico"), "目标未注册zenohpico内建库")
local h, err = z.open("tcp/127.0.0.1:17447", adapter, function(handle, event)
    -- opened / published / subscribed / unsubscribed / error / closed
    -- event.id：命令ID；event.code：0或错误码
end)
local sub = z.subscribe(h, "demo/in/**", function(handle, sample)
    -- sample.kind == "sample"
    -- sample.operation == "put" 或 "delete"，空PUT与DELETE不同
    -- sample.key / sample.payload（二进制Lua string）/ sample.subscriber
end)
local id = z.publish(h, "demo/out", "hello\0world")
z.unsubscribe(h, sub)
z.close(h)                         -- 幂等；异步释放由C任务完成
local state, dropped, callback_errors = z.state(h)
z.poll()                           -- VM主动派发，单次最多8个结果
```

仅 `opened`/`state == z.ONLINE` 后可发送命令。`state` 为0关闭、1打开中、2在线、3关闭中、4失败（失败可能很快进入终态关闭）；导出 `CLOSED` 和 `ONLINE`。运行状态和 `dropped` 可轮询；结果队列满时不保证每条完成回调。用户回调错误由受保护调用捕获并计入第三个返回值，不跨线程抛入 VM。

|本地错误码|含义|
|---|---|
|-2|参数或key不合法|
|-3|分配/初始化失败|
|-4|未知/过期订阅、请求或query token|
|-5|订阅/Get/Queryable有限槽上限|
|-6|随机源失败|
|-7|传输故障|
|-8|已有session、未在线或已关闭|
|-9|generation/ID耗尽|
|-10|命令队列满，未接纳|
|-11|Get收到错误回复（另看kind/operation）|
|-12|Get或incoming query超时|
|-13|Get本地取消|

异步事件还可能携带官方库原始负值。`close` 立即拒绝新命令并过滤旧样本；`closed` 表示释放终态通知。GC 同样请求关闭。重新连接应等旧会话关闭，再显式 `open`、重新声明订阅；不自动重连或切换网卡。对端重新声明/业务重放由应用决定。

关闭或传输故障会取消尚未执行的队列命令。Get包含已接纳但尚未交SDK的请求，会尝试投递一次get_done(reason=closed)；其它旧命令不保证逐条取消回调。接纳检查与入队和worker停止排空共用短队列门；已经出队且遇到close的Get也尝试closed终态。结果队列溢出仍以dropped/状态报告不完整，不能承诺未派发VM时每条终态必达。应用通过终态事件/状态处理未完成命令；发布完成仍不等于对端实收。部分TCP帧写失败后立即停止该连接的后续命令与写入，清理后由应用显式重连。

## Get与Queryable

```lua
local id = z.get(h, "demo/value", {parameters="source=lua", payload="q\0\255", timeout_ms=3000},
    function(handle, reply)
        -- get_reply；request_id/key/payload/operation/code。
        -- code=-11/operation=error是错误回复，不等于整个请求已终结。
    end,
    function(handle, done)
        -- get_done；request_id/reason/code，正常队列下每请求至多一次。
        -- reason: completed/timeout/cancelled_local/closed/error
    end)
z.cancel_get(h, id)                 -- 接纳状态，不保证网络撤销
local qid = z.queryable(h, "demo/value", function(handle, query)
    -- query.parameters/payload/key；query.query为带generation的opaque userdata。
    z.reply(handle, query.query, query.key, "value\0\255")
    z.finish_reply(handle, query.query) -- 可多次reply；显式final后token失效
end)
z.unqueryable(h, qid)
```

Get的id仅代表本地接纳，必须核实际reply及done。timeout_ms默认3000，限制100—10000；零回复completed不是实收成功。SDK closure drop后才回收其context，失败/关闭/GC/断连均清理；旧generation query token不能作用新会话。incoming query最多保留5秒，GC/finish/撤销/超时会drop owned query并结束回复。

`GET_CANCEL_MODE="local"`明确取消边界：抑制取消执行后新产生的Lua回复并给一次取消终态；此前已排队的reply仍可能先于done派发，SDK请求可能继续到其timeout/drop；退休context仍占4个槽，不提前free。未启用unstable cancellation token，不把本地取消冒充网络级撤销。队列/分配失败不推进未接纳的新命令id；回调throw由VM保护并释放请求引用。SDK错误码可能与本地负值重叠，要同时核kind/reason。

## 范围和资源

- 单session、显式 `tcp/host:port`、调用者给定一个网卡 adapter；目标适配支持IPv4/主机名，暂不支持IPv6。
- 4个订阅、4个Get（含SDK退休上下文）、4个Queryable、4个pending incoming query；命令队列8槽、结果队列8槽；key/parameters各最多255字节、payload最多4096字节；分片缓存8192、单播batch2048、executor容量64。
- 一个长期保留的C工作任务（请求栈8192字节）和两个队列首次使用时创建，关闭session后任务休眠；不按每条消息新建任务。Lua回调和句柄只由VM线程访问。
- 命令/结果拥有独立数据副本。队列满、分配失败、大于限制的远端样本显式拒绝或增加 `dropped`；失败不当成送达。
- msgbus只发唤醒，不传跨线程 userdata；弱值句柄表及generation过滤保护GC、关闭和退订。周期可用 `sys.timerLoopStart(z.poll, 10)` 保证msgbus拥堵时仍有派发机会。
- C任务每轮最多处理4条命令/4次executor推进，再让出5ms；网络非阻塞读取，短写按实际接纳长度推进；握手/写入有限总体超时。DNS/连接依赖LuatOS统一adapter的超时实现。
- 当前命令/结果结构含完整4096字节载荷。最坏积压内存需按 `(8 + 处理/入队中副本) × sizeof(struct)` 估算，并额外计官方库、网络缓存、任务栈和Lua复制；不是16KB总内存的承诺。Flash、峰值堆/栈、持续吞吐和P95延迟需目标构建/真机测量。
- Get/Queryable两套配置头均启用。仍不提供peer/listen、scouting、UDP、TLS、认证配置API、自动多网卡。测试router仅loopback无认证；不用于生产安全策略。

## 独立主机复验

需已安装 Python3、C11编译器、Lua开发库和zenohd1.9.0；工具不会自动安装依赖。宿主Lua版本在输出中记录。主机桥的网络控制API基于真实POSIX socket，固定127.0.0.1:17447，每次最多读取7字节/写入17字节，直接执行本模块的generic系统/TCP源码；对端则用官方Unix网络后端。它不代替真实LuatOS网络框架或RTOS/BSP。

```sh
python3 components/zenoh_pico/tests/run_host.py \
  --zenoh-root ../zenoh-pico --lua-root /path/to/lua-prefix \
  --router /path/to/zenohd --sanitize
```

Get完整回归使用同一命令加 `--get-tests`，选择独立peer `--get` 和 `tests/host_get_test.lua`；默认仍原16项Pub/Sub。peer可选 `--two-rounds` 会校验 `LuatOS\0zenoh-pico\255:1/2` 两个20B值，双轮后正常退出，无需stop，独立墙钟上限240秒；默认peer保原60秒及stop合同。

有pkg-config时可用 `--lua-pkg lua5.3` 代替 `--lua-root`。仅编译时不传 `--router`。输出 `HOST_PASS`、`HOST_EXIT 0`、`PEER_EXIT 0`、`INTEROP_PASS` 才是完整主机通过；只看到 `BUILD_PASS` 不算互通。端口已有占用则停止，测试结束只清理自己的子进程。`--skip-build` 仅用于测试脚本修改后的已知二进制复验，会打印实际SHA；默认始终构建。

## PC与目标BSP接入

PC新增装配由 `LUAT_USE_ZENOH_PICO=y` 显式开启，外置 `ZENOH_PICO_ROOT` 必须指向上述固定且未修改的Git依赖树。关闭时不加载组件或寻找依赖。使用原BSP helper构建：

```sh
cd bsp/pc
LUAT_USE_ZENOH_PICO=y ZENOH_PICO_ROOT=/path/to/zenoh-pico ./build_macos.sh
```

此完整PC命令尚未在本贡献环境通过：本机无xmake，现有macOS helper还固定i386；不把独立主机链接等同于PC模拟器构建。Linux/Windows同样使用各自既有helper并分别核验。

官方目标BSP需要：同一套配置头与C11/atomic支持、仅上述官方通用源码及本模块4个src文件、统一network adapter/RTOS/堆/MCU时钟/TRNG实现，以及 `luaopen_zenohpico` 注册。PC的 `bsp/pc/xmake.lua` 给出明确固定Git源码清单，组件不包含独立xmake文件；桥接头位于 `components/zenoh_pico/include/luat_zenoh_pico.h`；SDK自己的源文件表/注册表由官方提供实际路径并接入，不虚构Air8000用户C-SDK。

[最小demo](../../olddemo/demo/zenoh_pico/main.lua) 要求先配置网卡就绪、填写测试router和adapter，再启动 `zenoh_peer <router> test/zenohpico/manual` 作为真实回显对端。demo未烧录验证。

## 官方验收与回退

目标构建需核开关关闭/开启、Get+Queryable完整配置、VM位宽、注册和资源增量；我们继续负责真机二进制Pub/Sub与Get发起/应答双向、断网/重新打开、队列满/GC、持续内存及实际对端序号。目标结果完成前保持Draft，不把Get裁掉以凑空间。

回退关闭 `LUAT_USE_ZENOH_PICO`，撤销三处PC装配/声明及新增组件；不要求清空Flash、FSKV或改变现有业务配置。


确定性关闭交错回归：同一入口增加 `--race-tests both`，独立主机测试构建启用 `LUAT_ZENOH_TEST_BARRIERS`，分别暂停真实worker出队后和真实producer入队前；实际close/socket断连后核终态或拒绝，并重开与真实peer确认。目标默认构建不包含这些屏障。此回归与 `--get-tests` 分开选择。

若dropped增加而Get终态缺失，Lua请求槽/回调引用不能仅靠SDK上下文退休保证恢复；应用应将会话判为不完整并关闭/重建。当前有界队列合同不承诺每条终态必达或自动修复同会话槽位。
