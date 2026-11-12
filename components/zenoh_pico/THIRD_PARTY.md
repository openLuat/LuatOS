# 第三方来源和许可

zenoh-pico 1.9.0 固定提交 e83d39b4415f6897e8d6c3b3b651ca88a05f4a17，来源 https://github.com/eclipse-zenoh/zenoh-pico 。

核心源码按"嵌入式所需文件"裁剪后随本目录入库到 `zenoh-pico/`：`src` 只含 api/collections/link/net/protocol/runtime/session/transport/utils/system/common 十个通用目录的 `.c`，`include` 只含这些源码与组件配置头实际 include 到的头文件闭包。上游源码的本地修补逐项登记在VENDOR.md，未收录范围与重新生成步骤见 `zenoh-pico/VENDOR.md`。

`include/zenoh-pico.h` 与 `include/zenoh-pico/config.h` 分别由该提交的 `.in` 模板替换版本/功能数值派生，保留原版权、贡献者和 `EPL-2.0 OR Apache-2.0` 标记。配置选择与裁剪说明见README；不是上游默认配置。原始完整许可随本目录 `THIRD_PARTY_LICENSE` 提供。

PC 真实对端用到的 unix 后端（`system.c`/`network.c`/`unix.h`）同样来自上述提交、逐字节未修改，随测试脚本放在 `bsp/pc/zenoh_pico/unix_backend/`，不进固件。

本贡献自己的generic桥接、Lua接口、构建片段、demo与测试源按LuatOS的MIT许可，文件标记 SPDX-License-Identifier: MIT。模板派生头与随库入库的上游源码仍保留原许可，未改标为MIT。


认证SHA3-256派生自[XKCP](https://github.com/XKCP/XKCP)提交`d20c8fcaecc543f816a0721d0dfc13b4cf27c14d`的`Standalone/CompactFIPS202/C/Keccak-readable-and-compact.c`，原文件SHA256 `7d25b518f28b4b9be141495dde205621fdb528e880596ef9507d30ba1b937dc9`。保留Keccak团队署名及CC0-1.0声明，完整许可在`zenoh-pico/THIRD_PARTY/XKCP_LICENSE`（原LICENSE SHA256 `138d7bdf2ac34f062f12ccd0e4490da14fbd92a0d2602eba4e65f3470176b6ec`）。只留下SHA3-256必需函数，使用便携字节读写，增加私有命名与scratch擦除；不宣称未经修改，也不改标MIT。

USRPWD报文及算法按官方Zenoh 1.9.0源码协议实现，参考`zenoh-protocol`和`zenoh-transport`同版crate内提交`81c6c933b6e41d72a05f04c4442ef57717ddc72b`。未复制Rust运行库，未引入新的运行时外部依赖。真实Router互通与Python标准库hashlib/hmac向量只作为研发验证工具。
