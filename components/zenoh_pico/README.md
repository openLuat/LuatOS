# zenoh-pico：可选原生 TCP client

为 LuatOS 提供官方 zenoh-pico 1.9.0 的最小原生 Lua 绑定。默认关闭；独立库名 `zenohpico`，不替换已有 Lua `zenoh` 实现。

本组件含 1.9.0 核心源码（裁剪副本）、generic 系统/TCP 适配与 Lua 绑定。PC 侧装配、真实对端与主机回归在 [bsp/pc/zenoh_pico](../../bsp/pc/zenoh_pico)。本组件实现Get发起和Queryable应答；主机测试证据见 [bsp/pc/zenoh_pico/TEST_RESULTS.md](../../bsp/pc/zenoh_pico/TEST_RESULTS.md)。目标构建需要对应BSP环境；主机测试不代表设备已可运行。

## 固定依赖

- zenoh-pico **1.9.0**：`e83d39b4415f6897e8d6c3b3b651ca88a05f4a17`，核心源码已裁剪入库在
  [zenoh-pico/](zenoh-pico)（只含嵌入式所需文件，`version.txt` 供构建期核对，说明见
  [zenoh-pico/VENDOR.md](zenoh-pico/VENDOR.md)）。
- 测试 router：zenohd **1.9.0**。
- 第三方核心源码含 VENDOR.md 逐项登记的本地补丁；新增认证使用固定来源的 XKCP SHA3-256，保留原版权和许可，见 [THIRD_PARTY.md](THIRD_PARTY.md)。

组件目录只放模组固件要用的东西：`include/`（配置头与LuatOS平台适配）、`src/`（Lua绑定与generic系统/TCP）、
`zenoh-pico/`（官方核心源码裁剪副本）。PC 专有的装配脚本、真实对端与测试脚本不在本目录。

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
|-10|命令队列或TX载荷预算满，未接纳|
|-11|Get收到错误回复（另看kind/operation）|
|-12|Get或incoming query超时|
|-13|Get本地取消|

异步事件还可能携带官方库原始负值。`close` 立即拒绝新命令并过滤旧样本；`closed` 表示释放终态通知。GC 同样请求关闭。重新连接应等旧会话关闭，再显式 `open`、重新声明订阅；不自动重连或切换网卡。对端重新声明/业务重放由应用决定。

关闭或传输故障会取消尚未执行的队列命令。Get包含已接纳但尚未交SDK的请求，会尝试投递一次get_done(reason=closed)；其它旧命令不保证逐条取消回调。接纳检查与入队和worker停止排空共用短队列门；已经出队且遇到close的Get也尝试closed终态。结果队列溢出仍以dropped/状态报告不完整，不能承诺未派发VM时每条终态必达。应用通过终态事件/状态处理未完成命令；发布完成仍不等于对端实收。部分TCP帧写失败后立即停止该连接的后续命令与写入，清理后由应用显式重连。

### 首次IO故障诊断

TCP适配故障的`error`及对应`closed`事件携带`reason="io_failure"`和`io_failure`表。
SDK已关闭但没有适配IO首错时，worker的`-7`事件标记`reason="session_closed"`。
握手失败保留SDK原始错误码，不统一改为`-7`。`closed`保留清场前首错，正常关闭不携带历史故障。

|字段|语义|
|---|---|
|`stage`|`tx_context/tx_error/tx_timeout/rx_context/rx_error/rx_exact_context/rx_exact_timeout`等首个失败位置|
|`generation`|失败所属会话代次|
|`command_id/command_op/command_bytes`|最后执行命令的上下文，握手为0；不是该命令导致故障的证明|
|`rc`|底层API原始返回；本地截止分支为0，须同时看stage|
|`requested/transferred`|发送为整次`_z_send_tcp`调用的请求/累计接纳字节；普通接收为该次读取范围，读满截止为整次`_z_read_exact_tcp`范围|
|`elapsed_ms`|发送/读满截止的耗时；普通接收错误和无有效上下文分支当前未测，填0，不代表整个Get耗时为0|
|`total_tx/total_rx`|本代网络API累计接纳/读取字节；不是对端ACK或实收证明|

首错仅由单worker写入，事件保存值副本，不包含key、payload或凭据。失败后停止该连接的后续读写。
结果队列满/分配失败仍可能丢事件，需检查`dropped/state`，本改动不保证每条终态必达。
真实主机桥覆盖POSIX短写/半帧失败，但不模拟目标RTOS的发送确认等待；不能用主机通过排除目标超时或时序问题。

## Get与Queryable

```lua
local id = z.get(h, "demo/value", {parameters="source=lua", payload="q\0\255", timeout_ms=3000},
    function(handle, reply)
        -- get_reply；request_id/key/payload/operation/code。
        -- code=-11/operation=error是错误回复，不等于整个请求已终结。
    end,
    function(handle, done)
        -- get_done；request_id/reason/code，正常队列下每请求至多一次。
        -- reason: completed/timeout/cancelled_local/closed/error/resource_limit
    end)
z.cancel_get(h, id)                 -- 接纳状态，不保证网络撤销
local qid = z.queryable(h, "demo/value", function(handle, query)
    -- query.parameters/payload/key；query.query为带generation的opaque userdata。
    z.reply(handle, query.query, query.key, "value\0\255")
    z.finish_reply(handle, query.query) -- 可多次reply；显式final后token失效
end)
z.unqueryable(h, qid)
```

Get的id仅代表本地接纳，必须核实际reply及done。timeout_ms默认3000，范围1—600000毫秒，从命令接纳时起算，交给SDK时扣除排队耗时；零回复completed不是实收成功。SDK closure drop后才回收其context，失败/关闭/GC/断连均清理；旧generation query token不能作用新会话。incoming query最多保留30秒，GC/finish/撤销/超时会drop owned query并结束回复。

`GET_CANCEL_MODE="local"`明确取消边界：抑制取消执行后新产生的Lua回复并给一次取消终态；此前已排队的reply仍可能先于done派发，SDK请求可能继续到其timeout/drop；退休context仍占4个槽，不提前free。未启用unstable cancellation token，不把本地取消冒充网络级撤销。队列/分配失败不推进未接纳的新命令id；回调throw由VM保护并释放请求引用。SDK错误码可能与本地负值重叠，要同时核kind/reason。

## 范围和资源

- 单session、显式 `tcp/host:port`、调用者给定一个网卡 adapter；目标适配支持IPv4/主机名，暂不支持IPv6。
- 16个订阅、4个Get（含SDK退休上下文）、16个Queryable、4个pending incoming query；命令队列8槽、结果队列8槽；key最多512字节、parameters最多255字节；默认单条应用payload最大256KiB（262144字节），可用LUAT_ZP_PAYLOAD_MAX调低；SDK重组上限263168字节为Key等封装留余量，单播batch仍2048、executor容量64。
- 一个长期保留的C工作任务（请求栈8192字节）和两个队列首次使用时创建，关闭session后任务休眠；不按每条消息新建任务。Lua回调和句柄只由VM线程访问。
- 命令接纳时从Lua复制一次；执行时将这份载荷所有权交给SDK，最后一个SDK引用释放才退还TX预算，不再做第二次整包复制。结果仍拥有独立副本。队列满、分配失败、大于限制的远端样本显式拒绝或增加 `dropped`；失败不当成送达。
- msgbus只发唤醒，不传跨线程 userdata；弱值句柄表及generation过滤保护GC、关闭和退订。周期可用 `sys.timerLoopStart(z.poll, 10)` 保证msgbus拥堵时仍有派发机会。
- C任务每轮最多处理4条命令/4次executor推进，再让出5ms；网络非阻塞读取，短写按实际接纳长度推进；握手/写入有限总体超时。DNS/连接依赖LuatOS统一adapter的超时实现。
- 命令/事件载荷按实际字节数独立分配，空载荷不分配。默认TX/RX各512KiB载荷预算（LUAT_ZP_TX_PAYLOAD_BUDGET/LUAT_ZP_RX_PAYLOAD_BUDGET），出队和回调执行中仍计费；owned incoming query持有的payload/attachment也计RX额度，finish/过期/撤销/关闭时退还。预算不在重开时清零，旧代待派发事件仍占用。额外的结构、SDK临时复制/重组和保留查询的编码元数据、网络缓存、任务栈、Lua字符串不属于此载荷计数；完整峰值RAM、持续吞吐和P95延迟仍需目标测量。
- Get/Queryable两套配置头均启用。仍不提供peer/listen、scouting、UDP、TLS、peer端认证和自动多网卡。支持client USRPWD认证，见下节；它不加密业务流量，网络访问策略仍需独立配置。

## 大包容量与背压

`z.payload_stats()`返回进程生命周期的`tx_bytes/rx_bytes`、`tx_peak/rx_peak`、`tx_rejected/rx_rejected`和`tx_limit/rx_limit`。快照字段分别原子读取，不承诺整表同一瞬间；统计绑定层持有的载荷字节，不是完整SDK或Lua堆。TX预算不足返回`nil,-10`，分配失败返回`nil,-3`；未接纳命令不推进ID。RX样本不能接纳时增加`dropped`。Get回复发生长度/分配/预算/队列失败时，给`resource_limit`失败终态，不能把漏掉回复当`completed`；终态队列本身仍遵守原有有限投递合同。

256KiB指完成业务编码后的单条有效payload，不含Zenoh协议头；JSON/Base64占用应计入payload。SDK自动分片，业务不需要新增分块协议。256KiB单包不代表8个最大包可同时排队，也不代表上层原有64KiB或业务源码限制被自动放开。1024KiB脚本Flash与通信RAM是独立要求。

## 独立主机复验

主机回归脚本、真实对端与 unix 后端源码都在 [bsp/pc/zenoh_pico](../../bsp/pc/zenoh_pico)，不随组件进固件。
需已安装 Python3、C11编译器、Lua开发库和zenohd1.9.0；工具不会自动安装依赖。宿主Lua版本在输出中记录。主机桥的网络控制API基于真实POSIX socket，固定127.0.0.1:17447，普通套件每次最多读取7字节/写入17字节（大包套件为257/511，仍强制短读写），直接执行本模块的generic系统/TCP源码；对端则用官方Unix网络后端。它不代替真实LuatOS网络框架或RTOS/BSP。

```sh
python3 bsp/pc/zenoh_pico/run_host.py \
  --lua-root /path/to/lua-prefix --router /path/to/zenohd --sanitize
```

默认编译库内 vendored 的 1.9.0 源码（`components/zenoh_pico/zenoh-pico`），核对 `version.txt` 并打印源码清单摘要；
如需对照另一份 1.9.0 工作树，用 `--zenoh-root ../zenoh-pico`，外部目录也必须包含本批补丁，ABI标记为20261111；构建读取本地文件，不依赖.git或下载。未修补的原版不能与当前绑定混编。

Get完整回归使用同一命令加 `--get-tests`，选择独立peer `--get` 和 `host_get_test.lua`；默认17项含原16项及握手半帧失败/首错一致性。peer可选 `--two-rounds` 会校验 `LuatOS\0zenoh-pico\255:1/2` 两个20B值，双轮后正常退出，无需stop，独立墙钟上限240秒；默认peer保原60秒及stop合同。

有pkg-config时可用 `--lua-pkg lua5.3` 代替 `--lua-root`。仅编译时不传 `--router`。输出 `HOST_PASS`、`HOST_EXIT 0`、`PEER_EXIT 0`、`INTEROP_PASS` 才是完整主机通过；只看到 `BUILD_PASS` 不算互通。端口已有占用则停止，测试结束只清理自己的子进程。`--skip-build` 会逐项核对构建时的源码、头、测试脚本、Lua库与二进制摘要；任一输入变化必须重编，不能用旧二进制替代修后验证。默认始终构建。

## PC与目标BSP接入

PC装配由 `LUAT_USE_ZENOH_PICO=y` 显式开启，默认编译库内 vendored 源码；`ZENOH_PICO_ROOT` 仅用于指向另一份
1.9.0 源码树做对照（可选）。构建不执行Git命令、不下载源码；关闭时不加载组件或寻找依赖。使用原BSP helper构建：

```sh
cd bsp/pc
LUAT_USE_ZENOH_PICO=y ./build_macos.sh
```

确认过：装配段只纳入 `api/collections/link/net/protocol/runtime/session/transport/utils/system/common` 十个通用目录，
不纳入 `system/{unix,windows,...}` 等平台后端；缺必要头或通用目录会明确报错；版本来自 `version.txt` 且必须是 1.9.0。

官方目标BSP需要：同一套配置头与C11/atomic支持、仅上述官方通用源码及本模块4个src文件、统一network adapter/RTOS/堆/MCU时钟/TRNG实现，以及 `luaopen_zenohpico` 注册。桥接头位于 `components/zenoh_pico/include/luat_zenoh_pico.h`；EC7xx 侧的接线在 soc 仓库 `project/luatos/xmake.lua`，内建库注册在 `interface/src/luat_base_ec7xx.c`，开关按固件号放在 `project/luatos/inc/luat_conf_bsp_types_ec718hm.h`（1/101 号固件）。

目标示例需在网卡就绪后调用本页API；真实回显对端可用 `zenoh_peer <router> test/zenohpico/manual`。

## 官方验收与回退

本改动接续已合并的[PR282](https://gitee.com/openLuat/LuatOS/pulls/282)和[PR278](https://gitee.com/openLuat/LuatOS/pulls/278)。TEMP_3000专测已通过基础连接、4096B收发/Get和180秒短测；完整4115业务及256KiB真机尚未验收。本次新增动态大载荷、预算处理、SDK分片可靠性及Get登记分配失败修补，未声称目标已含本改动。新包继续要求Lua64及至少1024KiB脚本空间，见[AIR8000_PROFILE_REQUEST.md](AIR8000_PROFILE_REQUEST.md)。

目标构建需核开关关闭/开启、Get+Queryable完整配置、VM位宽、注册和资源增量；我们继续负责真机二进制Pub/Sub与Get发起/应答双向、断网/重新打开、队列满/GC、持续内存及实际对端序号。PR供源码复核，目标验收状态仍为待验证，不把Get裁掉以凑空间。

回退关闭 `LUAT_USE_ZENOH_PICO`，撤销三处PC装配/声明及新增组件；不要求清空Flash、FSKV或改变现有业务配置。


确定性关闭交错回归：同一入口增加 `--race-tests both`，独立主机测试构建启用 `LUAT_ZENOH_TEST_BARRIERS`，分别暂停真实worker出队后和真实producer入队前；实际close/socket断连后核终态或拒绝，并重开与真实peer确认。目标默认构建不包含这些屏障。此回归与 `--get-tests` 分开选择。

若dropped增加而Get终态缺失，Lua请求槽/回调引用不能仅靠SDK上下文退休保证恢复；应用应将会话判为不完整并关闭/重建。当前有界队列合同不承诺每条终态必达或自动修复同会话槽位。


关闭发生在SDK打开期间的回归使用 `--open-race-tests`（与Get/既有race套件互斥）。两阶段屏障分别位于真实SDK结果确定后、公开状态发布后；验证成功和失败结果均不覆盖CLOSING、closed仅一次、分配回到基线，并重开完成真实回显。该测试不会构造假的SDK结果。

每次正常构建还会编译执行 `host_transport_test` 与 `host_rx_test`：真实socketpair检查4096B短写/期限、短读字节守恒、通知0/1/15/16/17条消费预算及未知通知失败。主机事件桥用有限1ms消费FIFO；对0或永久等待明确退出86，捕获目标EC7xx零超时歧义。空邮箱不强制sleep(1ms)，与TEMP2222短等待分支一致；这不是完整RTOS模拟或目标网络ACK证明。

大载荷主机套件使用同一入口加`--payload-tests`，覆盖双向Pub/Sub、Get请求/回复与反向Queryable、远端超限、按需分配、TX/RX预算及拒绝回收、owned query过期、worker分配失败、Lua回调异常、关闭重开。测试输出与未验证项见[bsp/pc/zenoh_pico/PAYLOAD_TEST_RESULTS.md](../../bsp/pc/zenoh_pico/PAYLOAD_TEST_RESULTS.md)。主机通过不替代Air8000 ARM ABI、真实RTOS调度或完整业务RAM验收。

SDK仍为1.9.0基线，本地修补包括分片头直接传入可靠性枚举，避免RELIABLE=0被布尔转换反转，以及Get登记分配失败时保留原请求；来源及重建说明见[zenoh-pico/VENDOR.md](zenoh-pico/VENDOR.md)。`host_fragment_test.c`调用真实序列化/解码验证两类可靠性的首、续、末片和二进制守恒。


## 用户名密码认证与本批修补

`open(endpoint, adapter, callback, {username="测试用户", password="测试密码"})` 显式启用client USRPWD。
两项须同时提供，各1—128字节，不接受空值、NUL、CR/LF或未知options键。省略options仍是匿名连接；给了凭据但对端没有挑战/确认会失败，不退回匿名。认证失败不会发`opened`。

- `-68`：认证配置不合法；`-67`：认证握手结构或确认不合法；`-66`：对端拒绝；`-65`：算法自检失败。断线等仍可能保留SDK的传输错误码。
- 事件的`auth_stage`为`init_send/init_wait/open_send/open_wait/confirmed`，匿名时不添加；`remote_close_reason`保留对端Close原因，不含用户名、密码、nonce、HMAC或cookie。
- 用真实Zenoh 1.9.0 Router测试认证成功、128字节边界、错误用户名/密码、缺少凭据/挑战；另有SHA3/HMAC独立向量、配置分配失败和截断握手反例。测试使用临时合成凭据，退出删除字典，不读取现场账号。
- C可控凭据和proof缓冲在消费/失败/关闭时擦除；无法替Lua字符串或应用持久配置擦除原件。实现的来源、许可与本地修改见[THIRD_PARTY.md](THIRD_PARTY.md)及[zenoh-pico/VENDOR.md](zenoh-pico/VENDOR.md)。

多个Queryable命中同一请求时，`finish_reply`释放其中一个owner可返回`query_owner_released`；只有最后一个owner成功发送Final后才返回`query_finished`。Final写失败返回`error`，同时记录IO首错并释放资源，不重发不明完成度的帧。关闭的`cleanup_code`单独记录清场Final失败，不覆盖先前业务首错；没有主错误时清场失败也会体现在closed.code。

本批还修复配置复制/替换分配失败、握手cookie所有权与错误返回、Get退休/终态投递、已关闭会话Reply的moved数据释放及分片/扩展编码错误传播。测试操作见[CONSOLIDATED_TEST_RESULTS.md](../../bsp/pc/zenoh_pico/CONSOLIDATED_TEST_RESULTS.md)。SDK和绑定必须整批更新；不是在旧ROM上只换Lua脚本即可启用认证。

仍为单会话、有界结果队列，非Get命令和队列溢出的事件不保证逐条必达；state/dropped不等于业务端收件。未提供完整Lua业务门面、多会话或全部有效RX健康信息。1819认证注册、USB485、LED、真实RAM/栈与24小时业务长测须在新固件上另验，不能凭本机通过宣布生产可替换。
