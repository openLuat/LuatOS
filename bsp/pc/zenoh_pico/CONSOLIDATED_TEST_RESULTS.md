# 2026-11-11 集中修复与测试结果

接续 [PR282](https://gitee.com/openLuat/LuatOS/pulls/282) 和 [PR278](https://gitee.com/openLuat/LuatOS/pulls/278)。本页区分旧版本隔夜结果、本批代码短回归及目标板待验；不能把三者合并成“生产已通过”。

## 本次改动

1. 补齐 Zenoh 1.9 client USRPWD：Lua options 严格校验、挑战/证明/确认、错误账号密码拒绝、缺挑战不降级；保留认证阶段与远端关闭原因，擦除可控凭据和临时证明缓冲。新增 SHA3/HMAC 来源及许可证见 THIRD_PARTY.md。
2. 修复配置替换/clone、cookie、附件和分片初始化的分配失败与所有权问题；关闭后的 Reply 也消费 moved 参数。
3. Final 由最后一个 query owner 实际发送并返回真实结果；仍有其它 owner 时只报 owner 释放，清场错误不覆盖业务首错。
4. 主动取消读取不再误报网络故障；一旦取消写入（包括半帧），停止后续写入，避免把清场数据接到残帧后。
5. C 发送缓冲交给 SDK 引用计数，去掉第二次整包复制。最后引用释放才归还 TX 预算，跨 close/reopen 仍计费；Lua→C 的安全复制保留。
6. 订阅和 Queryable 各16个，Get仍4个，入站Query仍4个；Key512B、parameters255B，Get期限1–600000ms从接纳开始，入站Query30秒。单载荷256KiB、TX/RX各512KiB预算。

## 本批最终主机回归

macOS arm64、Apple clang21、LuatOS Lua5.3/64、真实 zenohd1.9及SDK；所有网络回归限定127.0.0.1:17447。功能构建使用ASan/UBSan，ASAN_OPTIONS=detect_leaks=0:halt_on_error=1；没有声称运行LSan。源码、头、Lua和二进制均固定摘要，skip-build拒绝漂移。

最终 build15 清单 SHA256：`e7b35f833834c9cb1fd4a77c6c1db91baa78aed31bcb1b52d5b6b0bf8953d317`。
host SHA256：`573bd8ffaa23b60871821f6f9adbba199d1cfecfe17af076073e5ce2b0d1a9bb`。
peer SHA256：`6e1bd074767eabed630a4ae29eb07256c2f752318a18c3d6bec1891a72202883`。

|最终用例|结果及范围|
|---|---|
|build15|generic平台严格C语法、分片可靠性、15类transport、5类RX/握手、9类内存/所有权、认证codec/config和31组Python hashlib/hmac独立向量通过|
|legacy05|基础互通、短读写、关闭重连、事件与错误路径通过|
|get03|Get生命周期、连续375次4096B Get、反向Queryable通过|
|payload03|22组；0至262144B二进制Pub/Sub/Get、超限拒绝、预算/OOM、SDK最后引用跨关闭重开计费通过|
|final04|双owner仅最后发Final、0/5字节Final故障、真实5字节写入后取消、禁止后续写、资源回收和重连通过|
|race03/openrace03|真实producer/worker接纳与关闭交错、SDK打开成功/失败竞争通过|
|auth06|anonymous/correct/maximum/wrong_user/wrong_password/missing_credentials/missing_challenge七项通过|

前六类网络套件host/peer均真实退出0，Router由owner正常SIGTERM清场（-15），无强杀或清场错误，17447释放。认证七项host均0；三个正向case的peer均0，每case三轮打开/关闭重开（匿名项不称认证），每代验证0/1/4096/65536/262144B回显。负向case禁止opened；错用户/密码为-66，缺挑战为-67；匿名客户端连强认证Router的拒绝目前为SDK-117，未虚报为-66。临时凭据由测试生成并清除，不使用生产账号。

复验方式（每次使用新的run目录；不要同时占用17447）：

```sh
python3 bsp/pc/zenoh_pico/run_host.py --lua-root /path/to/luatos-lua53-prefix --build-dir /tmp/zp-build --sanitize
python3 bsp/pc/zenoh_pico/run_host.py --lua-root /path/to/luatos-lua53-prefix --build-dir /tmp/zp-build --sanitize --skip-build --router /path/to/zenohd --run-dir /tmp/zp-base
# 逐项增加 --get-tests / --payload-tests / --final-tests / --race-tests both / --open-race-tests
python3 bsp/pc/zenoh_pico/run_auth.py --build-dir /tmp/zp-build --router /path/to/zenohd --out /tmp/zp-auth
```

源码或测试变更后重新构建；不改旧清单让旧二进制冒充新版本。PC完整xmake、ARM链接及目标BSP资源增量尚未验证，generic语法检查不替代它们。

## 隔夜 Lua / 原生比较（本轮实修之前的固定候选）

两客户端同Mac、同Lua5.3/64、同ASan/UBSan，经同一个公网地址NAT回流；不是跨运营商或Air8000实测。2026-11-10 19:33至11-11 08:30，双方各15432完整轮，约12小时56分23秒，各25次计划重连。0/1/256/4095/4096/4097/65535/65536B逐字回显均完成，未出现新的意外失败或崩溃，关闭后内存未持续增加，四业务进程均退出0。

|载荷|Lua RTT P50/P95 ms|原生 RTT P50/P95 ms|
|---|---:|---:|
|1B|8.014 / 8.382|10.946 / 14.878|
|256B|15.426 / 15.986|10.909 / 14.825|
|4096B|149.161 / 153.058|39.639 / 45.982|
|65536B|2305.754 / 2320.635|506.839 / 518.934|

稳定性在这个观察窗内未见明显差别。大包原生更快，但Lua主机桥每5ms轮询最多读257B，原生后台连续推进；人为短IO、线程调度、共享CPU和NAT均在RTT内。末段同时有编译工作。不能将4.5倍写成纯C收益或设备提速。该run无Get/认证，也没有覆盖本批新代码的隔夜稳定性。

另一个原生16h回环完成17976业务轮、26964个唯一Get终态后，在最终closed之后、PASS打印前触发宿主共享printf_dtoa.c:917有符号移位UBSan，整run仍记FAILED（host -15，peer0），不能写16h全通过。此公共printf问题本PR未修改。

## 本批去掉第二次复制的 A/B

同源码、同Lua5.3/64、同-O1、关闭sanitizer；A仅开启测试宏恢复第二份复制，B使用SDK拥有缓冲。按A/B/B/A串行跑，读257B/写511B，每轮6尺寸、每尺寸8预热+64计时；共1536计时样本、1728回显，四轮host/peer均0。测试hook两组开销一致；宏不进入目标构建。

没有测出一致提速。256KiB RTT P50：A1781.209ms、B1790.582ms；P95：1810.638/1820.624ms。4KiB/64KiB/256KiB记录的C/SDK堆峰值分别277506/338946/535554B，两组相同。1B和256B峰值分别少9B、264B。API接纳时延不含worker之后的复制，不能作为移除第二次复制的直接速度证明。

可确认代码少复制一次、所有权及预算回收通过；当前证据不足以宣称整体更快、大包总峰值下降或真机性能已改善。没有CPU耗时或饱和吞吐数据。

## 仍需收件的边界

- 旧公网262143B第407轮回显超时、第375次Get真机故障根因仍未确认；本机375次通过不能替代原场景定位。
- 认证已与真实Router验证，但目标TRNG/8KiB任务栈/ARM ABI、认证取消各阶段及更全面畸形扩展注入仍需补测；不宣称协议模糊测试全覆盖。
- USRPWD不等于TLS，不提供链路加密或服务端身份认证；不改生产安全策略。
- 单session及有限结果队列合同保留；未实现Lua四会话完整门面、可靠业务receipt或完整4115注册/采集/LED流程。P1事件唤醒优化未做。
- 新固件先在专用1819验源码/SoC SHA、实际1024KiB脚本布局、WiFi/TCP、正确/错误凭据、256KiB Pub/Sub/Get双向、关闭后重连，再跑180秒/30分钟/2小时及完整4115模拟长测。每步保留双端序号、Reply/Final真实返回、首错及内存。失败保现场，不把本机结果填成真机通过。

固件配置与实际交付要求见 [AIR8000_PROFILE_REQUEST.md](../../../components/zenoh_pico/AIR8000_PROFILE_REQUEST.md)。
