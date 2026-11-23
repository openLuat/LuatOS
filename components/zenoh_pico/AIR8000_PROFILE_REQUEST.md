# Air8000 原生 zenohpico 测试固件配置

请基于本 PR 最终合入的提交构建，分配一个新的固件编号。

| 项目 | 构建要求 |
|---|---|
| 平台与脚本 ABI | Air8000，112 基础，Lua 64 位 |
| 组件 | 启用原生 zenohpico，包括用户名密码认证、Pub/Sub、Get 和 Queryable |
| SDK | 同一提交中的 LuatOS 绑定、generic TCP 适配、配置头与随库 zenoh-pico 1.9.0。包含 auth.c 和 auth_sha3.c；ZP_LUATOS_PATCH_ABI 为 20261116 |
| 裁剪 | 裁掉字库和 LCD 相关组件 |
| 脚本空间 | 至少 1024KiB（1048576 字节）可用于脚本；现用脚本已超过 512KiB |
| 消息大小 | 使用随库配置，单条载荷上限 256KiB。载荷预算占用运行时 RAM，脚本区使用 Flash |

发布时请附固件编号、下载链接、实际构建提交及脚本分区大小，以便核对目标版本并复测。主机回归结果与复测命令见[测试结果](../../bsp/pc/zenoh_pico/CONSOLIDATED_TEST_RESULTS.md)。
