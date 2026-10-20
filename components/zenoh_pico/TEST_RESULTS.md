# 测试证据与未验证项

## 当前验收状态（2026-10-20）

Get/Queryable、owned query、local cancel及两处关闭/接纳竞态修复已重新从固定PR基线构建验证。严格C11检查和128/125源ASan/UBSan重建通过；真实Lua5.5.1、zenohd1.9.0及固定SDK e83d39b4415f6897e8d6c3b3b651ca88a05f4a17，隔离loopback端点。

|实际测试|结果|耗时|
|---|---|---|
|两项确定性关闭/断连交错（含重编）|host0/peer0，2项通过|15.114秒|
|双向Get与生命周期|host0/peer0，19项通过；对端15请求/4反向查询|22.879秒|
|原Pub/Sub兼容|host0/peer0，16项通过；对端28输入，短读1213/短写558|15.008秒|

三轮无ASan/UBSan异常，14项程序输入前后摘要一致。当前重编host SHA256 `d8469ccbae2faeb028b67f505ac77e13067895157f0e842d215cb71d07fecae4`，peer `ed6e08337ff2dffe3658a8e8123c107ab65f93e7e04e8dcf09899fc565d69e15`。可按README同一入口分别运行 `--race-tests both`、`--get-tests` 和默认模式复验；后两轮使用同一已核二进制 `--skip-build`。主机测试屏障默认编入独立测试binary，但未启用测试点时不暂停；目标构建不定义该宏。

Air8000 V2055/112测试底层已验证模块注册、原Pub/Sub API和STA入网；该底层未导出Get/queryable/reply，不含本次C增量。独立基础TCP诊断08因测试脚本漏注册VUART receive回调，启动令牌未被设备接纳，未发起TCP；此轮不作为模块TCP故障证据。随后09修复receive钩子，真机已接纳启动令牌并实际调用connect，但12秒内仍为state=3、online回调0、隔离Mac对端accepted=0。09诊断证据完整、outer记录退出0仅代表取证完成，TCP仍未通过；空PCB和未accept不能证明未发SYN、AP隔离、119故障或唯一BSP根因。我们继续负责定位和专板验证，不将08夹具修复写成TCP已恢复。

尚未完成：匹配Air8000 BSP的完整编译链接、Flash/堆/栈容量、设备双轮Pub/Sub与关闭重连、双向Get和长期压力。需要目标生效配置、对应平台库及打包链，或基于本PR提供的可核验固件/ELF/map。独立主机通过不替代目标验收，合入完成条件尚未满足。以下各节为历史结果，当时的“未推送”仅描述对应日期。

验证日期：2026-10-13。固定 zenoh-pico 1.9.0 `e83d39b4415f6897e8d6c3b3b651ca88a05f4a17`，zenohd 1.9.0，macOS 26.5 arm64，clang C11，实际宿主 Lua 5.5.1。

## 实际通过

- 本模块 generic 系统/TCP 适配和全部6个主机侧C文件通过 `-Wall -Wextra -Werror`；122个上游通用源文件参与真实编译链接。
- 使用 ASan/UBSan，主机直接执行本模块 generic 系统/TCP 源码；pthread/POSIX 网络控制桥限制每次读取7字节、写入17字节。独立 C 对端使用官方 Unix 后端，连接真实隔离 router `127.0.0.1:17447`。
- 16项通过：参数拒绝、唯一session、二进制及0/1/255/1024/4096字节边界、DELETE与空PUT区分、分配拒绝、退订旧样本过滤、4订阅上限、命令背压与结果丢弃观察、关闭过滤、10次重开及堆清理、GC关闭、真实TCP断连恢复、部分帧失败后零后续写、closed回调立即重开、实际短读/短写、独立对端确认停止。
- 故障回归在第一帧仅写5字节后注入失败，已入队第二条命令不发布，后续 `network_tx` 调用为0；显式重连后再次真实互通。
- 实际输出：`HOST_PASS checks=16 lua=Lua 5.5`、`PARTIAL_IO reads=1211 writes=558`、`HOST_EXIT 0`、`PEER_DONE received=28`、`PEER_EXIT 0`、`INTEROP_PASS`。对端28个输入包括有意退订及队列溢出场景，不代表客户端全部收到或零丢弃。无 ASan/UBSan 报告。
- 两个独立只读复核完成；短写故障继续发送、closed释放时序及依赖暂存差异检查均已修复。复核不等于目标构建。

## 复现

按 [README](README.md) 固定依赖，运行：

```sh
python3 components/zenoh_pico/tests/run_host.py \
  --zenoh-root ../zenoh-pico --lua-root /path/to/existing/lua-prefix \
  --router /path/to/zenohd --sanitize
```

完整重建后互通受本机沙箱网络权限限制，首次绑定被拒绝；获已批准本机运行权限后使用同一新构建的二进制 `--skip-build` 完成上述互通。SHA256：

- host: `e761abef5c202d4dd0e06058f2ab898b2cc469d4ea45a972d4cf5bcbf28da49c`
- peer: `06a0475e8b22f0cce8e4ea73bf6338b1960be4e46537f925421af4f5801e6342`

## 未验证

完整 LuatOS PC helper/xmake、LuatOS 5.3 VM、Air8000 内核编译/链接/位宽、真机网卡及长期负载、Flash/堆/栈峰值和延迟均未验证。独立 POSIX 桥不替代真实 LuatOS network adapter、RTOS/BSP。没有设备或业务服务器动作。保持 Draft，目标编译与真机由官方补验。

## 官方目录意见修订复验（2026-10-13）

demo原样移动至 `olddemo/demo/zenoh_pico/main.lua`；桥接头原样移动至组件include；移除组件xmake并把原固定依赖/源码装配内联到PC xmake。独立只读复核确认三条意见覆盖、移动内容字节不变、include路径和demo链接有效，无新增阻断。

本轮 `luac -p` 通过；两平台文件及全部6个本次C文件严格C11检查通过，128/125源文件ASan/UBSan重新编译链接通过。沙箱首次本机绑定EPERM，随后已批准权限下同一新二进制完成16项：`HOST_PASS checks=16 lua=Lua 5.5`、`PARTIAL_IO reads=1213 writes=558`、`HOST_EXIT 0`、`PEER_DONE received=28`、`PEER_EXIT 0`、`INTEROP_PASS`，无sanitizer异常。

本轮host SHA256 `1516359ed491e1f9dbedd6127c44e701b285ac94069c9e3428ce00b9dde7991b`；peer SHA256 `402e5fc7e5955a6a830917661011763086bfbac6a8c5ea276eaa44f4d8d01759`。Lua5.5语法检查不代表xmake运行或LuatOS5.3验证，完整PC/BSP与真机边界继续保留。

## 2026-10-15本地未发布Get与peer修复

以下增量未commit/push，设备尚未运行本原生增量，不覆盖上述2026-10-13历史证据。固定同一1.9.0 SDK/zenohd与真实Lua5.5.1/POSIX短读7B短写17B，启用QUERY+QUERYABLE，未启用unstable/API私有取消。

- strict C11 -Wall -Wextra -Werror及128/125源ASan/UBSan重建通过；原16项真实回归host0/peer0，实际短读1214/短写558，对端28输入。
- 可选双轮peer已真验证host0/peer0，两个20B值按轮次原值回显，每轮退订/正常close/reopen，无stop依赖。默认旧peer模式不变。
- 初始Get17项真实互通host0/peer0；停写复核加入“接纳Get立即close”后真实复现缺终态：host1/20.814449秒，未超时杀进程。根因为close drain只free未执行GET，没有通知GetDone。
- 最小修复给已接纳但未交SDK的Get投递closed终态，随后完整18项Get/双方实收host0/peer0（含3次立即close）；对端get_received15/device_get3，错误回复和正常done分开。原16项又通过。没有sanitizer异常。
- 18项覆盖导出/参数、0/20/4096B二进制双reply/final、错误reply、有限timeout、local cancel与迟到抑制、分配失败不消耗id、peer→Lua Queryable原值双reply/final、query userdata GC、撤销持有query/迟到reply执行拒绝、4个queryable、4个Get与取消、callback throw、pending close、旧代token、真实TCP断连、模块分配恢复、session GC和未执行Get立即close。
- 公开本地入口 `run_host.py --get-tests` 已加入；使用已核修复二进制 `--skip-build` 复验同18项host0/peer0，无sanitizer报告。此前失败原件与修复后原件分别保存，不改名掩盖尝试。

最终host SHA256 `1671354bb8ce3ea2bab74bb5c2be22d010129948caf4cc3c9819f0882db87f2e`；peer SHA256 `843b03c14d34bf467f2d2f43ec50d4c782b7fa522fcb3f7b0a31fe1ab143289f`。该SHA与当前C/头/配置/peer源编译对应；新--get-tests只改变测试选择，不再改二进制。

未验证：LuatOS5.3原生绑定/完整PC/BSP构建、Air8000目标Flash/堆/栈和真机Get/网络、网络级取消、pending-query峰值并发/长期负载及当前官方master兼容。已装新板.03与未发布.04Lua只测试原TEMP模块，不能把本主机Get增量当已上板。Lua5.5/主机资源不代目标。第三方SDK原文未改，未操作生产/设备、未推送或自行回复PR。

## 2026-10-15最终本地冻结（19项Get，未发布）

当前证据以最终19项版本为准，上节18项及SHA为历史。增加实际owned incoming query持有到5秒清场/迟到reply拒绝，并统一deadline判断。新测试发现对端Get期限3秒先收到router Timeout而退出，保留双方失败原件后将对端期限改7秒等待native5秒final；扩大silent等待的无效实验已撤回。失败位置与host失败后的peer真实清场输出保留。

严格C11与128/125源ASan/UBSan完整重编+19项真实Get实际0/39.817071秒，13输入前后SHA一致：GET_HOST_PASS checks=19、HOST_EXIT 0、PEER_DONE received=0 get_received=15 device_get=4、PEER_EXIT 0、INTEROP_PASS。相同二进制原16项actual0/17.286654秒：HOST_PASS checks=16、reads1213/writes558、peer28输入、双方0，无sanitizer异常。

官方编译器两份Lua5.3/64位字节码语法校验actual0，宿主实际运行仍Lua5.5.1；完整PC/BSP/LuatOS5.3 native运行和Air8000目标/资源/真机均未验。上游SDK未改，没有设备、生产、commit/push或PR消息动作。未声称目标容量或当前master兼容。

最终host SHA256 `26682cc1e5f780d5ec01a8cb89fa42dca61601527b1d189359a53f7e5061a63a`；peer `67236c84a619c037a24a91ca120d7c70ce9d71ebf54debe9e9fd888309dfe2c2`。本地证据归协作项目runtime/zenohpico_dedicated_261015/evidence/native_get_final_v4；不将私有运行原件提交公开PR。

## 2026-10-16独审R1确定性复现及修复

原19/16虽真实通过，独审发现出队GET遇close无终态、接纳初检后实际断连清场仍晚入队。仅测试构建增加pthread调度屏障，保持真实worker/SDK/Lua/socket：旧版两case实际host1，出队trace确认barrier到达、state已closed而done仍缺失；晚入队trace确认真实disconnect已结束worker但get仍被接纳。失败原件保留。

最小修复：同代已出队GET因wanted变化而不能执行时尝试closed终态；短atomic_flag门使最后接纳检查/timeout0队列发送与worker停止接纳/排空线性化。分配/复制、SDK、网络、Lua回调均不在producer门内，worker门内仅有限排空/零等待结果与消息投递。目标调度最坏等待尚未验，不承诺硬实时上界。

固定版严格C11/128和125源ASan/UBSan重新编译，两个确定性交错actual0/16.726324秒；同二进制Get19项actual0/22.922123秒、原16项actual0/14.952350秒，均host0/peer0，无sanitizer报告。竞态peer实际收到12B控制消息且正常退出；Get peer15请求/4个反向查询，旧PubSub peer28输入。14程序输入前后SHA一致。独立只读复核确认R1闭合、无新增阻塞；不代目标构建/真机/长期压力。

最终host SHA256 `1a31d945a6175940ee86c7aaecf9917dd064a6b2b48a195aaa244b7b33417c19`；peer `c3dd59c396e7a97f04f5d80168c839e763cc598967a4190f37b7f0282d007249`。证据归协作项目runtime/zenohpico_dedicated_261015/evidence/get_r1_proof与get_r1_fixed；测试构建屏障默认不进入目标。SDK原文未改，未commit/push、未操作设备/生产。
