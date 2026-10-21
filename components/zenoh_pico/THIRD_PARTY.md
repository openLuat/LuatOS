# 第三方来源和许可

zenoh-pico 1.9.0 固定提交 e83d39b4415f6897e8d6c3b3b651ca88a05f4a17，来源 https://github.com/eclipse-zenoh/zenoh-pico 。核心源代码外置并保持原件。

`include/zenoh-pico.h` 与 `include/zenoh-pico/config.h` 分别由该提交的 `.in` 模板替换版本/功能数值派生，保留原版权、贡献者和 `EPL-2.0 OR Apache-2.0` 标记。配置选择与裁剪说明见README；不是上游默认配置。原始完整许可随本目录 `THIRD_PARTY_LICENSE` 提供。

本贡献自己的generic桥接、Lua接口、构建片段、demo与测试源按LuatOS的MIT许可，文件标记 SPDX-License-Identifier: MIT。模板派生头仍保留原许可，未改标为MIT。
