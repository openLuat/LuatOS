# 第三方来源和许可

zenoh-pico 1.9.0 固定提交 e83d39b4415f6897e8d6c3b3b651ca88a05f4a17，来源 https://github.com/eclipse-zenoh/zenoh-pico 。

核心源码按"嵌入式所需文件"裁剪后随本目录入库到 `zenoh-pico/`：`src` 只含 api/collections/link/net/protocol/runtime/session/transport/utils/system/common 十个通用目录的 `.c`，`include` 只含这些源码与组件配置头实际 include 到的头文件闭包；上游文件逐字节未修改，未收录范围与重新生成步骤见 `zenoh-pico/VENDOR.md`。

`include/zenoh-pico.h` 与 `include/zenoh-pico/config.h` 分别由该提交的 `.in` 模板替换版本/功能数值派生，保留原版权、贡献者和 `EPL-2.0 OR Apache-2.0` 标记。配置选择与裁剪说明见README；不是上游默认配置。原始完整许可随本目录 `THIRD_PARTY_LICENSE` 提供。

PC 真实对端用到的 unix 后端（`system.c`/`network.c`/`unix.h`）同样来自上述提交、逐字节未修改，随测试脚本放在 `bsp/pc/zenoh_pico/unix_backend/`，不进固件。

本贡献自己的generic桥接、Lua接口、构建片段、demo与测试源按LuatOS的MIT许可，文件标记 SPDX-License-Identifier: MIT。模板派生头与随库入库的上游源码仍保留原许可，未改标为MIT。
