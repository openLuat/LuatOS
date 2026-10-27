## 功能模块介绍

本 demo 演示在 Air1601/Air1602 上使用合宙 adb（**hzadb**，日志口用户指令协议 v2）的完整流程。
hzadb 把**日志口复用成命令通道**，不需要额外占用一路 UART，上位机就能读写设备文件、
枚举挂载点、查询分区空间、文件指纹、内存和网络状态。

协议能力（帧格式、时序、实测数据见本目录 `PROTOCOL.md`）：

- 协议版本号、命令序号、滑动窗口 + 逐片确认 + 自动重传
- HELLO 握手协商分片大小、控制类回应去重
- open/read/write/close 文件模型，支持带 offset 的随机读写
- 可选 HMAC 挑战应答鉴权（AUTH）
- LSMOUNT / FSSTAT / FILE_SHA1 / MEMINFO / NETSTAT 状态类指令

hzadb 库只实现协议栈本身（帧解析、序号、去重、分片、鉴权门控），**不内置任何业务逻辑**：
文件系统操作由 `hzadb.fs()` 安装，状态查询由 `hzadb.mem()` / `hzadb.netdrv()` 安装，
也可以只用 `hzadb.reg_op()` 注册自己的指令。所以设备端开放哪些能力、哪些路径可读可写，
完全由应用脚本决定，这也正是本 demo 要演示的重点。

> **产品支持（重要）**：hzadb 依赖固件的 `log.set_usercmd_cb` / `log.usercmd_write`，
> 需要固件打开宏 `LUAT_USE_LOG_USER_CMD`；截至 2026-09-22 **仅 Air1601/Air1602 提供该能力**。
> 在 Air1603/Air1604/Air1605 等其它型号上，`hzadb.start()` 返回 `false` 并打印一条 warn，
> 日志口收不到协议帧，上位机表现为握手超时。详见 https://docs.openluat.com/osapi/ext/hzadb/

项目分为以下核心模块：

1、main.lua：主程序入口，初始化看门狗，启动 hzadb 应用任务

2、hzadb_app.lua：hzadb 设备端应用模块，安装指令集（fs/mem/netdrv）→ 可选只读保护 →
   可选鉴权 → 启动协议栈 → 起心跳日志，并打印启动信息与固件能力自检

3、host/luat_usercmd.py：Python 上位机库（与 `olddemo/demo/hzadb/host/` 里同一份），
   封装了握手、鉴权、分片、窗口、重传、翻页聚合，业务侧只用 `write_file` / `read_file` / `lsdir` 这些方法

4、host/demo_hzadb.py：上位机演示脚本，一条命令跑完「握手 → 鉴权 → 挂载点/分区 →
   写文件 → 读回校验 → 列目录 → stat → exists → 内存/网络状态 → 删除」

5、PROTOCOL.md：hzadb 协议说明（帧格式、错误码、窗口与分片实测数据、鉴权流程）


## 系统消息介绍

本 demo 不使用 `sys.publish` / `sys.subscribe` 这类系统消息。

命令帧不经过 Lua 消息队列：固件日志口收到 `cmd = SOC_CMD_USER_CMD(20)` 的帧后，
直接回调 `log.set_usercmd_cb` 注册的函数，hzadb 在回调里完成解析与分发，
回应通过 `log.usercmd_write` 走**独占命令帧通道**，不占用普通日志显示。

心跳日志用的是 `sys.timerLoopStart`，作用是验证「命令帧 + 普通日志帧」在同一根日志线上
共存时互不干扰 —— 这是日志口复用成命令通道后最容易被忽略的一点。


## 对外接口介绍

设备端（hzadb_app.lua）：

1、`hzadb_app.start()`：安装指令集并启动协议栈
   - 返回 `true`：日志口已被 hzadb 接管，上位机可以连接
   - 返回 `false`：两种情况，看紧挨着的日志就能区分
     - `固件 usercmd 通道 不可用`：固件未开启 `LUAT_USE_LOG_USER_CMD`（或不是 Air1601/Air1602）
     - `鉴权开启失败`：配了 `AUTH_TOKEN` 但 `set_auth` 报错（长度不对 / 固件缺 crypto），
       此时**主动放弃启动**，宁可不可用也不让日志口在没有鉴权的状态下对外开放

2、`hzadb_app.get_status()`：返回状态表 `{ready, version, auth, readonly}`
   - `ready`：协议栈是否已接管日志口
   - `version`：hzadb 库版本号（年月日时分）
   - `auth`：鉴权是否生效
   - `readonly`：是否只读模式

文件顶部的三个可配置项（改完重新烧录即可，不需要动业务代码）：

| 配置项 | 默认值 | 作用 |
| --- | --- | --- |
| `AUTH_TOKEN` | `""`（不鉴权） | 填 8~64 字节随机串后开启 HMAC 挑战应答鉴权，上位机需用同款 token 调 `auth()` |
| `READ_ONLY` | `false` | 置 `true` 时用 `hzadb.reg_op` 覆盖 write/mkdir/rmdir/remove，一律回 `E_DENIED` |
| `HEARTBEAT_MS` | `5000` | 心跳日志周期，填 `0` 关闭 |

上位机（host/luat_usercmd.py，节选常用方法）：

| 方法 | 说明 |
| --- | --- |
| `UserCmd(port, baud=6000000)` | 打开串口，创建实例 |
| `wait_ready()` | 等设备启动 + HELLO 握手 + 分片协商，返回协商后的写片长 |
| `auth(token)` | 可选鉴权，设备端没开鉴权时返回 `False`（不算错误） |
| `lsmount()` / `fsstat(path)` | 挂载点枚举 / 分区空间（total、used、block_size、fs） |
| `write_file(path, data)` / `read_file(path)` | 自动分片、窗口、重传的整文件读写，返回字节数 / bytes |
| `lsdir(path)` | 列目录，自动翻页聚合，返回 `[{name, type, size}]` |
| `stat(path)` / `exists(path)` / `remove(path)` / `mkdir` / `rmdir` | 对应同名指令 |
| `request(subcmd, body)` | 直接发子指令，返回 `(errno, flags, body)`，本 demo 用它查 MEMINFO / NETSTAT |


## 演示功能概述

### 1、主程序入口模块（main.lua）

- 初始化项目信息和版本号（`PROJECT = "HZADB"`、`VERSION = "001.999.000"`）
- 初始化看门狗，并定时喂狗
- 用 `pcall(require, "hzadb_app")` 加载应用模块：库没打包进去时给一条明确提示，
  而不是抛一堆堆栈让人猜
- 启动任务里调用 `hzadb_app.start()`，并按返回值区分「已接管日志口」和「固件不支持」
- 结尾 `sys.run()`

### 2、hzadb 设备端应用模块（hzadb_app.lua）

启动顺序（每一步都有日志，出问题看日志就能定位）：

1. 打印协议栈版本、协议版本 `0x01`、单帧数据区上限 1024 字节
2. **固件能力自检**：判断 `log.set_usercmd_cb` 是否为 function，
   区分「固件没开宏」和「库没打包进脚本」两种失败
3. 打印挂载点（`io.lsmount`）与根分区空间（`io.fsstat`），
   让操作者知道上位机该往哪个路径传文件
4. 安装标准操作集：
   - `hzadb.fs()`：装 13 条文件系统指令（open/close/write/read/lsdir/mkdir/rmdir/
     remove/stat/exists/lsmount/fsstat/file_sha1），**默认拦截对 `/luadb` 的读文件请求**
     （防止固件脚本被别人读走），`lsdir/stat/exists` 和写操作不受影响
   - `hzadb.mem()`：MEMINFO，返回 sys/lua/psram 三组 total/used/max
   - `hzadb.netdrv()`：NETSTAT，返回适配器数量 + 每个适配器的 link/ready/napt 与 IPv4
5. 可选只读保护：`READ_ONLY=true` 时用 `hzadb.reg_op` 覆盖写类指令。
   注意必须在 `hzadb.fs()` **之后**注册才有效，后注册的会替换掉标准实现
6. 可选鉴权：`AUTH_TOKEN` 非空时调 `hzadb.set_auth`，
   必须在 `hzadb.start()` **之前**，否则 HELLO 的 caps 位无法告知上位机需要鉴权。
   如果 `set_auth` 失败（token 长度不在 8~64，或固件没带 crypto），
   **直接终止启动**并打 error —— 不继续往下走，避免"以为有鉴权"却在裸奔
7. 启动协议栈：`hzadb.start()` 内部注册 `log.set_usercmd_cb`，之后日志口收到的协议帧都交给 hzadb 分发
8. 起心跳日志

### 3、上位机 Python 库（host/luat_usercmd.py）

- 传输层：A5 命令帧、CRC16、转义、组帧，与固件 `am_log.c` 对应
- 会话层：HELLO 握手协商写片长（新固件 1024，旧固件自动收缩到 476 / 90），
  序号 + 滑动窗口 + 逐片确认 + 自动重传，控制类指令用 `(seq, 回应帧)` 缓存去重
- 文件层：`write_file` / `read_file` 自动切分与拼装，`lsdir` 自动翻页
- 依赖只有 `pyserial`，不装其它包

### 4、上位机演示脚本（host/demo_hzadb.py）

一条命令跑完 7 步，每步都有中文提示和失败排查方向：

1. 握手 + 分片协商：打印协商后的写片长与 caps
2. 鉴权（可选）：传了 `--token` 才调 `auth()`
3. 挂载点枚举与根分区空间
4. 写文件 → 读回逐字节校验 → 打印耗时与吞吐
5. 列目录（前 10 项）、`stat`、`exists`
6. MEMINFO（sys/lua/psram 分别的总量/已用/峰值）、NETSTAT（link/ready/napt/IPv4）
7. 删除测试文件并确认 `exists=false`


## 安全说明（鉴权与只读）

日志口复用成命令通道，本质上是把「调试口」变成了「文件系统入口」，所以有两道闸：

1、**读拦截**：`hzadb.fs()` 默认拦截 `/luadb` 下的读文件请求（`open` 读模式 / `read` /
   `file_sha1`），防止别人把固件脚本读走。要改拦截范围，改 `script/libs/hzadb.lua` 里的
   `READ_DENY_PREFIXES`，或干脆不用 `fs()`、自己用 `reg_op` 注册更细的白名单。
2、**鉴权与只读**：本 demo 的 `AUTH_TOKEN` / `READ_ONLY` 两个开关。

> **量产一定要配 `AUTH_TOKEN`**。默认不鉴权时，任何能打开日志口的工具（不止 Luatools）
> 都能读写设备文件。token 建议 ≥16 字节随机串，且不要写进公开仓库。


## 演示硬件环境

1、Air1601 或 Air1602 开发板一块（**必须**是这两个型号，其它型号固件没有 usercmd 通道）：

- 板载 USB 转串口，或 TYPE-C USB 数据线一根，接开发板 USB1 口（串口下载/调试）

2、电脑一台，用于运行 Luatools 或 Python 上位机

3、不需要额外接线：hzadb 走的就是日志口（下载/日志复用同一个 USB 口）

串口烧录与拨码开关位置详见 [1601 开发板使用说明](https://docs.openluat.com/air1601/product/shouce/)。


## 演示软件环境

1、Luatools 下载调试工具：https://docs.openluat.com/air1601/luatos/common/download/

2、固件版本：Air1601/Air1602 对应的最新固件（其它型号不支持本 demo）。

3、固件需启用以下宏：

```
LUAT_USE_LOG_USER_CMD     （hzadb 的前提，缺了 start() 直接返回 false）
LUAT_USE_CRYPTO           （只有开启鉴权 AUTH_TOKEN 时才需要，file_sha1 也依赖 crypto）
```

4、设备端协议栈是**通用库** `script/libs/hzadb.lua`。用 Luatools 烧录时要勾选
   **「添加默认lib」**，否则 `require "hzadb"` 会失败（本目录不自带协议栈副本）。

5、上位机（Python 脚本方式）：Python 3.7+，装一个依赖即可 `pip install pyserial`。

6、判断固件是否真的开启了 usercmd 通道，看启动日志这一行：

```
I/user.hzadb_app 固件 usercmd 通道 可用
```

如果是 `不可用`，说明该固件没开 `LUAT_USE_LOG_USER_CMD`，换固件版本。


## 演示核心步骤

1、用 Luatools **选择整个 `hzadb` 目录**烧录脚本，并勾选「添加默认lib」
   （`hzadb.lua` 在 `script/libs/`，不勾选会 `require` 失败）；固件按板型选 Air1601/Air1602 对应版本。

2、烧录成功后代码自动运行，串口日志关键内容（节选）：

```lua
[2026-10-27 10:00:00.100][LTOS/N][000000000.100]:I/user.main HZADB 001.999.000
[2026-10-27 10:00:00.320][LTOS/N][000000000.320]:I/user.hzadb_app 协议栈版本 202609221555 协议版本 1 单片上限 1024B
[2026-10-27 10:00:00.322][LTOS/N][000000000.322]:I/user.hzadb_app 固件 usercmd 通道 可用
[2026-10-27 10:00:00.330][LTOS/N][000000000.330]:I/user.hzadb_app 挂载点 /:soc /luadb:luadb /ram:ram
[2026-10-27 10:00:00.335][LTOS/N][000000000.335]:I/user.hzadb_app 根分区 soc 2097152/4194304 bytes, block 4096
[2026-10-27 10:00:00.340][LTOS/N][000000000.340]:I/user.hzadb_app 标准操作集安装完成 fs/mem/netdrv
[2026-10-27 10:00:00.342][LTOS/N][000000000.342]:I/user.hzadb_app 鉴权未开启(AUTH_TOKEN 为空)，任何能打开日志口的工具都能读写文件
[2026-10-27 10:00:00.350][LTOS/N][000000000.350]:I/user.hzadb_app hzadb 服务就绪：日志口已被接管 读写 无鉴权
[2026-10-27 10:00:00.352][LTOS/N][000000000.352]:I/user.main 日志口已被 hzadb 接管，可以用 Luatools 设备文件管理或上位机连接了
[2026-10-27 10:00:05.360][LTOS/N][000000005.360]:I/user.hzadb_app heartbeat lib 202609221555 usercmd已接管
```

3、连上位机，两种方式任选：

**方式一：Luatools 图形界面（最省事）**

用 Luatools 打开串口后，进入「设备文件管理」界面，可以直接浏览、上传、下载设备文件。

**方式二：命令行脚本（能看到每一步的返回值和吞吐）**

```bash
cd host
pip install pyserial
python demo_hzadb.py --port COM6
```

参数说明：

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `--port` | 必填 | 串口号，如 `COM6` 或 `/dev/ttyUSB0` |
| `--baud` | `6000000` | 日志口波特率；固件改过日志速率时用它覆盖 |
| `--token` | 空 | 设备端配了 `AUTH_TOKEN` 时填同款 token |
| `--dir` | `/ram` | 测试文件所在目录，默认放 ram（掉电清空、不磨损 flash） |

执行成功后的输出（节选）：

```
===== 1. 握手（HELLO） =====
  握手完成：协商写片长 1024 字节，caps=0x0000

===== 3. 挂载点 / 分区空间 =====
  /              soc
  /luadb         luadb
  /ram           ram
  根分区：soc 总 4.0MB / 已用 2.0MB（块 4096）

===== 4. 文件读写（WRITE/READ/CLOSE） =====
  写入 /ram/hzadb_demo.txt：1800 字节，耗时 0.02s（87.9 KB/s）
  读回 1800 字节，内容校验一致

===== 6. 内存状态（MEMINFO）/ 网络状态（NETSTAT） =====
  sys   总 1.2MB      已用 356.0KB   峰值 402.0KB
  lua   总 512.0KB    已用 128.0KB   峰值 140.0KB
  psram 总 8.0MB      已用 1.5MB     峰值 1.6MB
  适配器数量：1
    id=1  link=1 ready=1 napt=0 ip=192.168.1.23
```

4、进阶验证（可选）：

- 把 `hzadb_app.lua` 的 `READ_ONLY` 改成 `true` 重新烧录，再跑脚本，
  第 4 步写文件会拿到 `E_DENIED`，用来确认「权限由脚本决定」这条设计；
- 把 `AUTH_TOKEN` 填成 `"0123456789abcdef"` 重新烧录，不带 `--token` 跑脚本会失败，
  带 `--token` 就正常，用来确认鉴权闸门生效；
- 传输大文件时观察心跳日志：命令帧与日志帧共存，速度不会因为打日志而掉下来。
  协议实测写入约 235KB/s、读取约 120KB/s（窗口 W=1、chunk=1024，详见 `PROTOCOL.md`）。


## 常见问题

**Q1：上位机一直卡在握手，日志里也没有 hzadb 的启动信息？**

- 先看设备端日志有没有 `hzadb 服务就绪：日志口已被接管`；
- 没有这一行、只有 `hzadb 未启动`，说明固件没开 `LUAT_USE_LOG_USER_CMD`，
  换 Air1601/Air1602 对应固件（其它型号目前不提供该能力）；
- 有这一行但上位机仍超时，先确认串口号选对、`--baud` 与固件日志口速率一致，
  并关掉 Luatools 等占用同一串口的工具。

**Q2：`require "hzadb"` 失败 / 日志提示「加载 hzadb_app 失败」？**

- 设备端协议栈在 `script/libs/hzadb.lua`，烧录时必须勾选 Luatools 的「添加默认lib」；
- 本目录刻意不自带一份协议栈副本，避免和仓库版本不一致。

**Q3：写文件返回 `E_DENIED`？**

- 设备端 `READ_ONLY = true`，写类指令被脚本挡掉了；
- 或者设备端开了鉴权，但上位机没调 `auth()` / `--token` 传错；
- 还有一种情况：`hzadb.fs()` 默认拦截 `/luadb` 的**读**文件请求，读 `/luadb` 下自己的脚本
  会拿到 `E_DENIED`，这是设计如此，不是故障。

**Q4：传文件慢，或者时不时重传？**

- 优先用 ram 或 TF 卡目录做测试，往 flash 上写会受擦写速度限制；
- 窗口别开大：这套固件上 W=1 在读写两个方向都最快（实测 W=8 时连发 8 帧会稳定丢 3~4 帧）；
- 片长由 HELLO 协商，旧固件会自动收缩到 476 / 90 字节，
  日志里 `协商写片长` 的数字就是实际值，别手工写死；
- 数据线质量在 6M 波特率下影响很大，劣质线会直接表现为重传率上升（协议细节见 `PROTOCOL.md`）。

**Q5：开了鉴权后上位机报鉴权失败？**

- token 必须和设备端 `AUTH_TOKEN` 完全一致，长度 8~64 字节；
- 固件需带 crypto（`LUAT_USE_CRYPTO`），否则 `set_auth` 会直接报错；
  此时设备端会打印 `鉴权开启失败` 并**放弃启动协议栈**（不至于无鉴权对外开放），
  表现就是上位机一直握手超时——所以遇到连不上，先看有没有这条 error；
- 鉴权必须在 `hzadb.start()` 之前配置，改完记得重新烧录。

**Q6：「设备文件管理」里能浏览目录，但下载 `/luadb` 下的文件失败？**

- 正常情况下 `/luadb` 是**只读拦截**的：`lsdir` / `stat` / `exists` 正常，
  但读文件内容会回 `E_DENIED`，防止固件脚本被读走；
- 确实需要读，就在 `script/libs/hzadb.lua` 里调整 `READ_DENY_PREFIXES`，
  或者不用 `fs()`，自己用 `reg_op("open", ...)` 注册带白名单的实现。

**Q7：跑上位机脚本时提示串口被占用？**

- 先关掉 Luatools 里的串口（或退出 Luatools），同一时刻只能有一个程序占用日志口；
- Linux 下还需要把当前用户加入 `dialout` 组，或用 `sudo`。


## 参考资料

- hzadb 官方文档：https://docs.openluat.com/osapi/ext/hzadb/
- 协议细节（帧格式、错误码、窗口与分片实测）：本目录 `PROTOCOL.md`
