# DNS 中继

## Scope（范围）

`components/network/dns_server/`：提供可移植的报文解析器和专用的 lwIP
传输后端。SDK 的 WAN 发现和 ABI 适配位于 SDK 封装层。

## Where to Look（文件索引）

- `include/luat_dns_server.h`：API、核心线程约束和生命周期约定。
- `include/luat_dns_server_lwip.h`：具有明确类型的厂商移植层钩子。
- `src/luat_dns_server_packet.c`：仅依赖标准 C 的问题解析器。
- `src/luat_dns_server_lwip.c`：实例状态、延迟任务和原始传输。
- `README.md`：源文件选择、默认值、所有权和回归测试接入点。

## Conventions（约定）

遵循 API 的线程约束，保持解析器独立于 LuatOS/lwIP。
所有原始网络操作都应放在 `_lwip` 后端或移植层编译单元中。
ABI、清理和匹配规则以 README 的**所有权与 SDK 移植层**和**响应校验**
两节为唯一权威说明。

## Verification Recipe（验证步骤）

1. 运行 `testcase/tools/network_servers/` 下的独立解析器回归测试，
   以及基于虚拟 netif 的 lwIP 生命周期回归测试。
2. 通过 PC 辅助批处理构建脚本编译并链接上游 lwIP。
3. 使用实际 SDK 的头文件和工具链对 SDK 适配层进行语法检查，
   包括不兼容函数指针诊断。按 README 的说明选择源文件。

## Anti-Patterns（禁止的做法）

- 不得在接收回调或 SDK 的释放后回调中移除或重新绑定 UDP PCB。
- 已投递的任务仍持有引用时，不得释放实例存储。
- 厂商修改了回调 ABI 时，不得编译上游默认移植层。
- 获取熵失败时，不得用计数器或标准 C 伪随机数生成器代替。

## Related Docs（相关文档）

- `../AGENTS.md`
- `README.md`
