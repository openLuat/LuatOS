# 256KiB载荷修复与主机验收（2026-11-09）

本次接续[PR278](https://gitee.com/openLuat/LuatOS/pulls/278)。PR278的连接、短读写及关闭修复保留；本次补齐完整业务超过4096B的容量和资源处理。主机通过不等于目标固件或完整业务通过。

## 环境与复现

- macOS arm64、Clang、宿主Lua 5.5.1；目标LuatOS Lua 5.3/ARM/RTOS未由此替代。
- vendored zenoh-pico 1.9.0，基线`e83d39b4415f6897e8d6c3b3b651ca88a05f4a17`加VENDOR.md记录的一处可靠性补丁。
- 官方zenohd 1.9.0，二进制SHA256 `576b7110124bc352b9076aed349071fcf18023a0c9daf2bea289c8ade9fc9bdf`，默认传输配置；只监听127.0.0.1:17447，关闭发现与插件。
- 独立C peer使用Unix后端，绑定侧执行真实generic TCP代码。大包套件每次读取上限257B、写入511B，仍强制短读短写。

在仓库根执行，依赖须已安装：

```sh
python3 bsp/pc/zenoh_pico/run_host.py --lua-root /path/to/lua-prefix \
  --build-dir /path/to/test-build --router /path/to/zenohd --sanitize --payload-tests
```

旧功能分别去掉`--payload-tests`、替换为`--get-tests`、`--race-tests both`、`--open-race-tests`。复用本次已构建二进制可加`--skip-build`，入口打印实际SHA；不允许把别的构建结果混为同一次验收。未修补的外部pristine `--zenoh-root`仅用于旧版失败对照，完整通过应使用vendored补丁源码。

## 实测闭环

- 原版分片编码：可靠与尽力两种模式均失败，测试退出1。原因是枚举`RELIABLE=0/BEST_EFFORT=1`被布尔转换后反转。
- 修补后真实编码/解码：两种模式各5片、8192B逐字节相等，首/续/末、序号、R位均通过。
- ASan/UBSan大包套件21组通过，`HOST_EXIT 0`、`PEER_EXIT 0`、runner退出0。无sanitizer报告。
- 同一ASan/UBSan二进制完成旧功能回归，各子进程真实退出见下表。

|套件|最终结果|
|---|---|
|256KiB载荷与内存，21组|通过，host/peer/runner均0|
|原Pub/Sub，17项|通过，host/peer/runner均0|
|Get生命周期，19项|通过，host/peer/runner均0|
|关闭/接纳竞态，2种交错|通过，host/peer/runner均0|
|打开/关闭竞态，成功/失败交错|通过，host/peer/runner均0|

21组覆盖：0/1/4095/4096/4097/65535/65536/65537/131072/262143/262144B二进制Pub/Sub；64/128/256KiB Get请求与两次回复、反向Queryable与两次reply；256KiB错误回复；本地和远端262145B拒绝；查询持有/到期/撤销/关闭及attachment计费；结构和payload分配失败；真实Lua字符串与终态表OOM、四槽恢复；TX/RX累计字节预算、队列满回滚及唯一Get失败终态；用户回调抛错；关闭排空、重开后最大包。

内存实测：TX/RX峰值各524288B，结束均0；LuatOS C分配路径恢复暖机基线384B，峰值1061022B。该峰值**不包括完整Lua堆、真实设备其它任务/网络缓存**，不能当作设备RAM总需求。payload_stats也仅统计绑定持有的载荷；SDK重组、临时副本、元数据、栈等仍有额外开销。

## 连续三包曾失败，现已修正

最初连续发送3个262144B时，只交付前两包。原始send记录证明peer发出完整三条消息，但接收端第三条缺最后938B传输片，之后出现零长度batch；关闭Router batching没有改善。不能把缺包超时当作预算拒绝。

检查发现Pico 1.9.0 `transport/common/tx.c`将可靠性枚举转布尔值，分片R位与预期相反，原始字节亦为BestEffort。Router将这种消息视为可丢弃，与[上游报告的空Drop marker路径](https://github.com/eclipse-zenoh/zenoh/issues/2851)吻合；本轮未修改或插桩Router，不将其内部执行路径宣称完全证实。

仅修Pico一处参数为原枚举后，同一默认Router、原连续三包测试通过：两个最大包占满RX512KiB，第三包完整到达绑定并明确拒绝；恢复Lua派发后仅前两包交付，额度归零。默认测试保留这条反例，没有改为降低数据量或放宽超时。补丁许可与来源见VENDOR.md。

## 仍须目标验收

- 未执行本轮Air8000固件编译/烧录、1819的256KiB实测、真实RTOS峰值RAM/栈、持续吞吐或长期稳定性测试，也未执行完整4115注册/USB485/LED长测。
- 宿主Lua版本不同，ARM ABI和目标Lua 5.3须新固件核验；未执行完整PC BSP构建，只有专属host harness与generic接口严格编译。
- 上层既有64KiB业务及网页限制没有自动放开；认证、声明容量与完整替代验收仍另列。
- 新编号测试固件继续请求112基础裁字库/LCD相关组件，**至少1024KiB脚本Flash**。生产脚本已超过512KiB；Flash空间与通信RAM分别验收。
