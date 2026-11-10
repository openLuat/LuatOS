# 内置的 zenoh-pico 1.9.0 源码

本目录是[官方 zenoh-pico](https://github.com/eclipse-zenoh/zenoh-pico) **1.9.0** 的**裁剪副本**，
只保留嵌入式模块编译所需的文件，供 `LUAT_USE_ZENOH_PICO` 固件与 PC 模拟器直接编译。
除下述两处本地修补外，上游文件逐字节未修改。胶水层（配置头、Lua 绑定、generic 系统/TCP 适配）在本目录的父级
`components/zenoh_pico/{include,src}`。

## 固定版本

- 版本：`1.9.0`（`version.txt`）
- 提交：`e83d39b4415f6897e8d6c3b3b651ca88a05f4a17`（tag `1.9.0`）

`version.txt` 是构建期版本锁：`bsp/pc/xmake.lua` 与 soc 仓库 `project/luatos/xmake.lua`
都会核对它，不符直接报错，避免配置头（按 1.9.0 生成）与核心源码错配。

## 收录范围

| 内容 | 数量 | 说明 |
|------|------|------|
| `src/{api,collections,link,net,protocol,runtime,session,transport,utils,system/common}/**.c` | 122 | 官方通用源码，不带任何平台后端 |
| `include/**/*.h` | 144 | 上述源码 + 组件配置头实际用到的头文件闭包 |
| `version.txt` | 1 | 版本锁 |

## 未收录（及去处）

- `docs/ examples/ tests/ ci/ cmake/ zephyr/ flipper/ tools/`、`CMakeLists.txt` 等构建/文档文件：与固件无关。
- `include/zenoh-pico.h.in`：组件 `include/zenoh-pico.h` 已是 1.9.0 生成结果。
- `src/system/{unix,windows,arduino,espidf,freertos,mbed,threadx,zephyr,...}` 等平台后端：
  模组侧由 `components/zenoh_pico/src/zenoh_luatos_{system,tcp}.c` +
  `include/zenoh_luatos_platform.h` 提供；PC 真实对端用的 unix 后端在
  `bsp/pc/zenoh_pico/unix_backend/`。
- `include/zenoh-pico/system/platform/` 下其它平台头：`ZENOH_GENERIC` 分支不会引用，
  只有 unix 的那份随 PC 对端放在 `bsp/pc/zenoh_pico/unix_backend/include/`。

## 重新生成（升级或补文件）

1. 取对应 tag 的干净工作树，例如：
   `git clone --branch 1.9.0 https://github.com/eclipse-zenoh/zenoh-pico.git ../zenoh-pico`
2. 按"收录范围"复制 `src/<通用目录>/**.c`；
3. 用编译器的依赖输出算头文件闭包，再复制（`-MM` 只列真正 include 到的头）：

   ```sh
   arm-none-eabi-gcc -MM -std=gnu11 -DZENOH_GENERIC -DZENOH_C_STANDARD=11 \
       -DZENOH_COMPILER_GCC -I components/zenoh_pico/include -I ../zenoh-pico/include \
       <每个 .c 文件>
   ```

   把输出里落在 `../zenoh-pico/include` 下的路径按相对路径复制过来；
4. 复制 `version.txt`；
5. 两个仓库各编一次：soc 侧 `xmake`（ec718hm 1 号）与 PC 侧
   `LUAT_USE_ZENOH_PICO=y xmake`，确认无缺头文件报错。

裁剪按"目录 + 头文件闭包"机械处理。重新生成后须重新应用并验证下述本地修补，不能静默恢复旧错误。

## 行尾（LF）

上游是 LF，本目录也必须是 LF。除明确记录的补丁文件外，保持逐字节一致。在 Windows 上复制时
容易整棵树变成 CRLF（等于每个文件多出一个 `CR`/行），所以：

- `components/zenoh_pico/.gitattributes` 已把本目录钉成 `* text=auto eol=lf`，
  `git add` 时自动归一到 LF；
- 复制完可用下列命令自查，输出为空才算干净：

  ```sh
  git ls-files --eol -- components/zenoh_pico | grep -v 'i/lf'
  git diff --ignore-cr-at-eol --stat -- components/zenoh_pico   # 核对是否只有预期改动
  ```

- 想确认某个文件与上游完全一致，直接比 blob 哈希（比"看行数"可靠）：

  ```sh
  git hash-object components/zenoh_pico/zenoh-pico/include/zenoh-pico/api/primitives.h
  # 应等于上游 1.9.0 同名文件的 blob sha
  ```

## 本地修补：分片可靠性（2026-11-09）

- `src/transport/common/tx.c` 中的 `__unsafe_z_serialize_zenoh_fragment`。
- `_z_t_msg_make_fragment_header`第二参要求`z_reliability_t`，原代码却传`reliability == Z_RELIABILITY_RELIABLE`。枚举`RELIABLE=0`、`BEST_EFFORT=1`，导致两者的分片R位反转。改为直接传`reliability`，不改线协议或SDK版本。
- 原版可靠/尽力两种真实序列化反例均失败；修补后须通过`bsp/pc/zenoh_pico/host_fragment_test.c`的首/续/末片、二进制守恒测试，以及256KiB连续三包真实互通。
- 保留原EPL-2.0 OR Apache-2.0许可；本文件仍标1.9.0基线加本地补丁，不宣称上游已接纳。撤销此一行即可将tx.c恢复为上游版本，但会恢复该错误。

## 本地修补：Get登记分配失败（2026-11-10）

- `src/session/query.c` 中的 `_z_unsafe_register_pending_query`。链表节点分配失败时，插入函数返回原表头。确认表头已更新后才登记新请求并推进ID，失败则走已有SDK内存不足路径。
- 在真实SDK分配器注入失败，验证空链表安全返回、已有请求的ID和回调保持原样、清理时原回调只执行一次。保留同一上游许可和1.9.0基线。
