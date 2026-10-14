# components/prof — 通用 cycle profiler(调优专用)

标准化的性能周期剖析设施。**默认关闭(`LUAT_USE_PROF` 未定义), 关闭时插桩宏编译为空, 零开销**;
调优时由 BSP 定义 `LUAT_USE_PROF` 打开。

> 注意区分: `components/mempool/profiler`(`LUAT_USE_PROFILER`, Lua 库 `profiler`)是**内存** profiler, 与本组件无关。

## 组成

| 部分 | 文件 | 说明 |
|---|---|---|
| 头文件/宏 | `include/luat_prof.h` | `LUAT_PROF_BEGIN/END` 插桩宏, 架构内联 tick(ARMv7-M DWT CYCCNT / x86 rdtsc / 其他走 weak `luat_prof_tick()`) |
| 核心 | `src/luat_prof.c` | 模块/槽位注册表(静态池 8×32, 不 malloc), ticks/calls/max 累加, weak 平台桩 |
| Lua 绑定 | `bind/luat_lib_prof.c` | Lua 库 `prof`, `LUAT_USE_PROF` 时才注册 |

## 开启方式

- ec7xx BSP (luatos-soc-2024): 取消 `project/luatos/inc/luat_conf_bsp.h` 开发者区段(//<-- custom 之后)中 `// #define LUAT_USE_PROF 1` 的注释。注意: 各型号头 `luat_conf_bsp_<model>.h` 自包含, `luat_conf_bsp_dft.h` 仅在无型号构建时生效, 所以开关放在 luat_conf_bsp.h 的型号链之后。BSP 实现(DWT 初始化 + 307MHz 频率换算)在 `interface/src/luat_prof_ec7xx.c`。改开关后需 `xmake f` 重新配置(out/luat_conf_bsp.txt 在 on_config 阶段生成, 增量构建不会自动重跑)。
- PC 模拟器: `$env:LUAT_USE_PROF = "y"`(PowerShell)或 `LUAT_USE_PROF=y`(sh)后重编; PC 侧 tick 走 rdtsc。
- 其他环境: 定义宏并提供 `luat_prof_hw_init()` / `luat_prof_ticks_per_us()` 的 strong 实现(可选, 缺省为 weak 空桩/0)。

## 消费者插桩规范

```c
#include "luat_prof.h"

static const char *const mymod_slots[] = {"encode", "decode"};
static int mymod_id = -1;

// 模块初始化时注册一次(关态为空桩, 返回 -1, 后续宏自动失效):
mymod_id = luat_prof_register("mymod", mymod_slots, 2);

// 热路径:
uint32_t tok;
LUAT_PROF_BEGIN(tok);
... 被测代码 ...
LUAT_PROF_END(mymod_id, 0, tok);
```

- 消费者代码**不需要任何 #ifdef**; 关态下宏展开为 `((void)0)`, API 为头文件内联空桩。
- `tok` 就近声明即可, 关态下未被读写(与 g729 已量产插桩同构)。
- 运行时由 `prof.enable(true/false)` 控制采集, 关闭时 BEGIN 只做一次全局变量判断, 不产生调用。

## Lua 侧读取

```lua
prof.enable(true)         -- 启用并清零
-- 跑被测业务 --
local st = prof.dump()    -- st.enabled / st.mods / st["模块名"]["槽位名"] = {ticks=,calls=,max=}
prof.enable(false)
```

- `prof.ticks_per_us()` 返回 0 表示 BSP 未提供频率(NO-DATA), 此时只能比较 ticks 相对占比。
- `prof.selftest()` 注册内建 `prof.selftest` 模块跑已知 span, 用于无消费者时端到端验证。

## NO-DATA 语义

平台无 cycle 计数器(tick 恒 0)时, ticks/max 恒 0 而 calls 正常累加 — 测试与脚本应显式区分
"无数据"与"零开销", 不要把 ticks==0 当作被测代码零成本。

## 数值显示注意

默认 32 位 Lua VM 的 `lua_Integer` 是 32 位有符号数, ticks 超过 2^31 后 Lua 侧显示为负值,
仅影响直接打印; C 侧累加与差值计算均为 uint32 回绕语义, 占比/差值分析不受影响
(需要读绝对值时先 `ticks % 2^31` 或自行按 uint32 解释)。
