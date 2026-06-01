# PC模拟器 Web Console 运行手册

## 1. 启动方式

Web Console 通过命令行参数开启：

```powershell
cd bsp\pc
.\build\out\luatos-lua.exe --webc=18921
```

- `--webc=<port>`：启动并绑定到 `127.0.0.1:<port>`
- 端口范围：`1-65535`
- 非法端口会直接报错并退出

如果只做普通脚本运行，不传 `--webc` 即可保持关闭。

## 2. 启动优先级

启动顺序如下：

1. 命令行 `--webc=<port>`，优先级最高
2. `pcconf/pcconf.json` 中的 `web_console.enabled=1`
3. 其余情况不启动 Web Console

也就是说，**CLI 只负责显式开启**；是否自动继承端口与刷新间隔，取决于 `pcconf` 持久化配置。

## 3. `pcconf` 目录与文件

运行目录下会使用：

```text
pcconf/
pcconf/pcconf.json
```

行为说明：

- `pcconf` 目录不存在时会自动创建
- 配置加载失败时会回落到默认值，并在需要时自动补写
- 通过 Web API 修改的配置会写回 `pcconf/pcconf.json`

### 3.1 文件格式

v1 的持久化格式是 **JSON**，由 `cJSON` 读写。当前并未把 YAML 当作一等格式支持。

示例骨架：

```json
{
  "schema_version": 1,
  "mcu_mhz": 240,
  "uart_udp_port_start": 9000,
  "uart_udp_id_start": 0,
  "uart_udp_id_count": 8,
  "web_console": {
    "enabled": 1,
    "port": 18080,
    "refresh_interval": 5
  },
  "storage": {
    "tf_enabled": 1,
    "nor_enabled": 1,
    "nand_enabled": 1,
    "tf_capacity_mb": 64,
    "nor_capacity_mb": 16,
    "nand_capacity_mb": 128,
    "nor_model": "w25q128",
    "nand_model": "w25n01gv"
  },
  "network": {
    "enabled": 1
  },
  "simulator": {
    "enabled": 1
  }
}
```

## 4. Web Console 默认行为

- 不传 `--webc` 时，CLI 路径本身不启用 Web Console
- 如果 `pcconf/pcconf.json` 里启用了 `web_console.enabled`，则会自动继承该端口启动
- 如果两者都没有开启项，就保持关闭；需要明确关掉时，把 `web_console.enabled` 设为 `0`

## 5. 验证脚本

优先使用仓库自带脚本验证：

```powershell
cd bsp\pc
.\tests\ps1\test_webc_args.ps1
.\tests\ps1\test_webc_runtime.ps1
.\tests\ps1\test_webc_uart31_console.ps1
.\tests\ps1\test_webc_uart32_gnss.ps1
```

必要时也可直接运行模拟器：

```powershell
.\build\out\luatos-lua.exe --webc=18921 --noexit
```

## 6. 开发工作流约定

- **Worktree 隔离**：每个独立任务优先使用单独 git worktree，避免互相污染
- **Fleet 并行开发**：如果有多个互不依赖的子任务，拆开并行处理
- **TDD-first**：先补测试/回归脚本，再做实现，再跑验证
- **本仓库构建命令**：
  - 非 GUI 变更：`cd bsp\pc && cmd /c build_windows_32bit_msvc.bat`
  - GUI/LVGL/SDL 相关：`cd bsp\pc && cmd /c build_windows_32bit_msvc_gui.bat`
  - 64 位：把脚本换成 `build_windows_64bit_msvc.bat`
- **脚本测试命令**：
  - PC 模拟器 Lua 测试：`build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\<suite>\scripts\`
  - Web Console 回归：优先跑 `tests\ps1\test_webc_*.ps1`
  - C 层 utest 覆盖率：`cd bsp\pc && .\pc_utest_coverage.ps1 -Suite c_utest_dtls_basic`（其余网络 suite 用 `-SkipBuild` 串行跑）
