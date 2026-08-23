# fatfs SD 卡 sim 失败 — 根因报告

> 本 worktree: `vfs-fatfs-sd-sim-debug`
> 起点 commit: `4f764f8e6`(vfs-utest-aggregate)
> 报告时间: 2026-06-13

## 现象

跑 `bsp/pc/build/out/luatos-lua.exe testcase/common/scripts/
testcase/utest/fs/vfs_uniform/scripts/ testcase/utest/fs/vfs_uniform_fatfs/scripts/`
在 mount 阶段即失败,SD 卡模拟器从未被访问过。日志关键片段:

```
D/fatfs init sdcard at spi=20 cs=23
E/SPI_TF cmd 0 arg 0 result -6
40 00 00 00 00 95 FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF FF
D/SPI_TF sdcard init fail!
D/SPI_TF SDHC error, please reboot tf card
W/fatfs mount failed, try auto format
E/SPI_TF cmd 0 arg 0 result -6
D/SPI_TF sdcard init fail!
D/fatfs auto format ret 3
E/fatfs sd/tf format failed 3
E/main [string "mount_fatfs.lua"]:12: fatfs mount failed: false
```

- `result -6` = `ERROR_OPERATION_FAILED`,意味着 `luat_spitf_cmd` 在 6 命令字节 +
  40 dummy 字节共 46 字节里**没有找到任何非 0xFF 响应**
- `40 00 00 00 00 95` 是 fatfs 自己发出去的 CMD0 命令(含 0x95 CRC7)
- 后面 40 个 `0xFF` 全是 luat_spitf_cmd 在 `diskio_spitf.c:261` 预填的 dummy
  字节(`memset(spitf->TempData + 6, 0xff, TxLen - 6)`),从未被 SPI transfer
  回调覆盖

## 探针输出

在 `luat_spi_pc.c:1418` 早退处加临时 log:

```c
if (win32spis[spi_id].open == 0) {
    LLOGW("PROBE luat_spi_transfer spi=%d open=0 active_cs=%d",
          spi_id, g_spi_routes[spi_id].active_cs);
    return -1;
}
```

跑同一条命令,前 5 行:

```
W/luat.spi PROBE luat_spi_transfer spi=20 open=0 active_cs=0
W/luat.spi PROBE luat_spi_transfer spi=20 open=0 active_cs=0
W/luat.spi PROBE luat_spi_transfer spi=20 open=0 active_cs=0
E/SPI_TF cmd 0 arg 0 result -6
D/SPI_TF sdcard init fail!
```

每次 fatfs 启动会触发 3 次早退(对应 `luat_spitf_init:588/590/592` 的三次
80+80+46 字节 transfer),`active_cs=0` 在 `mount_fatfs.lua` 传 cs=23 后仍未变。

## 根因(精确到一行)

**`bsp/pc/port/driver/luat_spi_pc.c:1414-1419` 的 `luat_spi_transfer` 早退于
`win32spis[spi_id].open == 0`,而 `open` 字段从 mount_fatfs.lua 走到
`fatfs.mount` 整数参数路径时,从未被设为 1。**

具体调用链:

```
mount_fatfs.lua:11
  fatfs.mount(fatfs.SPI, "/fatfs", 20, 23, 24*1000*1000)
    ↓
luat_lib_fatfs.c:134-141  (type 0 整数参数分支)
  spit->spi_id  = 20
  spit->spi_cs  = 23
  spit->fast_speed = 24*1000*1000
  diskio_open_spitf(0, spit)            ← 只把值塞进 g_s_spitf
    ↓                                    ← 关键:此路径不调 luat_spi_setup
                                          也不调 luat_spi_bus_setup
                                          也不调 luat_spi_device_setup
    ↓
diskio_spitf.c:1060-1083 luat_spi_set_sdhc_ctrl_default
  g_s_spitf.CSPin   = 23
  g_s_spitf.SpiID   = 20
  g_s_spitf.SpiSpeed = 24*1000*1000
  (没有调 luat_spi_setup)
    ↓
[f_mount → f_diskio → disk_initialize → luat_spitf_init]
    ↓
luat_spitf_init:578   luat_spi_change_speed(20, 400000)   ← PC 上是 no-op
luat_spitf_init:587   luat_gpio_set(23, 0)               ← 仅设 GPIO
luat_spitf_init:588   luat_spi_transfer(20, ...)        ← 早退!open=0
luat_spitf_init:589   luat_gpio_set(23, 1)
luat_spitf_init:590   luat_spi_transfer(20, ...)        ← 早退!open=0
luat_spitf_init:592   luat_spitf_cmd(CMD0)
                        ↓ luat_spi_transfer(20, ...)   ← 早退!open=0
                          → recv_buf 保持 0xFF → result -6 → init fail
```

对照 type 1(spi.device_setup + fatfs.mount(userdata))路径:它走
`luat_lib_spi.c:579` 的 `spi.device_setup` → `luat_spi_device_setup` →
`luat_spi_bus_setup` → `luat_spi_setup`,会设 `win32spis[id].open = 1` 并
`pc_spi_route_set_active_cs(bus_id, cs) = 23`,所以 type 1 路径在 PC 上是好的。

## 影响范围

- 任何在 PC 上用 `fatfs.mount(fatfs.SPI, "/", spi_id, cs, speed)` 整数参数
  形式挂载 SD 卡,**全部失效**
- `testcase/utest/fs/vfs_uniform_fatfs/` 的 30 个共享用例全部无法执行(mount
  阶段就 assert 失败)
- `/fatfs` 任何后续操作不可达
- NAND / NOR 虚拟设备走的是 `lf.mount + lf` 抽象,绕开了 `fatfs.mount` 整数路径,
  不受此 bug 影响

## 候选修复方向(只列,不实现)

**方向 A:`mount_fatfs.lua` 改用 type 1 路径(最小侵入,跟 `luat_lib_fatfs.c:81-90`
示例一致)**

```lua
-- 现状
local mret = fatfs.mount(fatfs.SPI, "/fatfs", 20, 23, 24*1000*1000)

-- 改成
local tf_dev = spi.device_setup(20, 23, 0, 8, 24*1000*1000)
local mret = fatfs.mount(fatfs.SPI, "/fatfs", tf_dev)
```

- 优点:最小改动、只动测试脚本、跟官方示例对齐
- 缺点:如果其它真实 BSP 用户也是用整数路径(嵌入式开发者常见用法),他们
  的代码不受影响(嵌入式不需要 luat_spi_setup),但 PC 用户必须切到 type 1
- 风险:低

**方向 B:`luat_spi_set_sdhc_ctrl_default` 末尾对 type 0 补 `luat_spi_setup()`**

```c
// diskio_spitf.c:1060-1083 末尾追加
if (!userdata->type) {
    luat_spi_t cfg = {0};
    cfg.id = userdata->spi_id;
    cfg.cs = userdata->spi_cs;
    luat_spi_setup(&cfg);
}
```

- 优点:fatfs 组件自洽,嵌入式 / PC 统一行为
- 缺点:每次 mount 都做一次 setup 可能有副作用(PC 上是 noop 实际);
  嵌入式 BSP 的 luat_spi_setup 通常已经做过(用户自己调的),这里再调一次
  会重新打开 SPI
- 风险:中(嵌入式已有 setup 流程的代码会重复)

**方向 C:`fatfs_mount` 的 type 0 分支补 `luat_spi_setup()`**

```c
// luat_lib_fatfs.c:134-141 else 分支内,diskio_open_spitf 前
luat_spi_t cfg = {0};
cfg.id = spit->spi_id;
cfg.cs = spit->spi_cs;
luat_spi_setup(&cfg);
diskio_open_spitf(0, (void*)spit);
```

- 优点:和 type 1 行为对称
- 缺点:同上,嵌入式可能重复
- 风险:中

**方向 D:让 PC BSP 的 `luat_spi_transfer` 第一次访问时 lazy-init**

```c
// luat_spi_pc.c:1418 改成
if (win32spis[spi_id].open == 0) {
    LLOGD("lazy-init spi=%d (no explicit setup)", spi_id);
    luat_spi_t cfg = {0};
    cfg.id = spi_id;
    // cs 没法猜 — 仍然需要 active_cs 来自 setup,所以这个方向不完整
    // 需要 pc_spi_route_set_active_cs(spi_id, ??)
    // ...
    return -1;  // 实际上这个方向不能完全解决问题
}
```

- 结论:这个方向**走不通**。lazy-init 时 CS 未知,需要 type 0 路径显式提供,
  所以本质上还是要修 type 0 调用方。
- 仅作记录用,不作为可选项

**方向 E(独立,不解决本 bug):撤销 commit `419030781` 的 xmake 冗余 defines**

`bsp/pc/xmake.lua:153-154` 的两行 `add_defines` 是冗余的(`luat_conf_bsp.h`
早就有 `#define LUAT_USE_FS_VFS 1` / `#define LUAT_USE_FATFS`),MSVC 编译期
还报 `C4005: 重定义` warning。

- 优点:清理,跟 `LuatOS no-require 约定` 一致(全局 C 模块宏不该在
  xmake.lua 重复定义)
- 缺点:跟当前 mount bug 无关
- 风险:零(无功能影响)
- 建议:作为方向 A/B/C 任一被采纳后**附带**的清理项

## 推荐

**方向 A + 方向 E** 组合:
- A 用最小改动修 mount
- E 清理 `419030781` 的 xmake 冗余

**为什么不是 B/C**:方向 B/C 在嵌入式 BSP 上会重复 `luat_spi_setup`,而嵌入式
开发者的代码流程里 `luat_spi_setup` 可能在更早的 BSP 初始化阶段调过,这里再
调一次有可能触发硬件重置。方向 A 把"PC 路径必须用 type 1"作为测试侧的
约定,不污染 fatfs 组件自身的语义。

## 验证方案(待用户选定方向后)

1. 在 worktree 里应用所选方向的 patch
2. 跑 `vfs_uniform_fatfs` 一次,期望:
   - mount 步骤不报 `fatfs mount failed: false`
   - `luat_spi_pc.c:1418` 探针不再触发
   - vfs_cases.lua 30 个用例实际跑(可能仍有部分 SKIPPED,预期 fatfs
     不支持的 C13 仍 skip)
3. 跑回归:`vfs_uniform_tfs / pgfs / ram / posix / lfs2` 应不受影响
4. 跑 `bsp/pc/build_windows_64bit_msvc.bat` 应无 `C4005` warning(方向 E)

## 探针代码当前状态

`bsp/pc/port/driver/luat_spi_pc.c:1418` 还插着一行 `LLOGW("PROBE ...")`,
未提交。停在这里等用户决策,决策后:
- 如果采纳方向 A:连同 A 的 patch 一起 revert 探针
- 如果采纳 B/C:同
- 如果不修 / 改其它方向:revert 探针
