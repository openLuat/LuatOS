# 测试证据与未验证项

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
