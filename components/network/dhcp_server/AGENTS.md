# DHCP 服务器

## Scope（范围）

可移植 DHCPv4 引擎及与其明确分离的 lwIP 原始接口后端。

## Where to Look（代码位置）

- `include/luat_dhcps.h`、`src/luat_dhcps.c`：报文和租约引擎。
- `include/luat_dhcps_lwip.h`、`src/luat_dhcps_lwip.c`：传输后端。
- `testcase/tools/network_servers/dhcp/`（相对于仓库根目录）：独立测试和主机兼容层。
- `README.md`：配置、API 和生命周期约定的权威说明。

## Conventions（约定）

- 协议逻辑须独立于 lwIP、平台时钟和内存分配。
- 保持各实例的存储由调用方拥有，并保留 LICENSE 中的 MIT 署名。
- 修改所有权、回调或清理流程时，遵循 README 的**线程所有权与生命周期**和
  **lwIP 后端**章节；操作顺序也是 API 约定的一部分。
- 传输测试替身和主机头文件应放在 testcase 目录树中。

## Recipes（操作流程）

修改生命周期时，按照 README 约定检查从初始化、接收派发到停止的完整流程，
再使用主机测试套件验证失败清理和重新启动。

在仓库根目录执行：

```text
python testcase/tools/network_servers/dhcp/run_host_tests.py
```

修改 SDK 适配层后，追加 `--sdk C:/path/to/sdk`。
测试脚本将编译警告视为错误；后端检查使用真实 lwIP 头文件和传输测试替身。
覆盖范围和限制见 README 的**验证**章节。

## Anti-Patterns（禁止事项）

- 不要将 lwIP 原始接口调用移入报文引擎。
- 不要在实例间共享租约存储，也不要绕过生命周期操作的串行化要求。
- 不要将主机传输测试视为固件或真实网络验收。

## Related Docs（相关文档）

- [README.md](README.md)
- [网络约定](../AGENTS.md)
- [测试约定](../../../testcase/AGENTS.md)
