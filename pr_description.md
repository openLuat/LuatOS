## 沙箱 4 项缺陷修复

> `script/libs/exapp.lua`

### 问题背景

在 PC 模拟器上对应用商店 294 个后装 app 做全生命周期回归测试（安装→启动→退出→卸载），通过率 85%（250/294），44 个未通过。经 crash dump + app 源码 + sandbox 代码三重分析，定位到 exapp.lua 沙箱层的 4 个根因缺陷。

---

### Fix 1: `EXT_LIBS` 缺少 `airui` → 部分 app 启动超时 (+1 行)

**位置**: `local EXT_LIBS = {...}` (~847 行)

**现象**: whack_a_mole2026、number_guess2026 等 6 个新 app 全部在 `launch` 阶段超时。

**根因**: 2026 系列 app 在源码中写 `local airui = require("airui")`，而沙箱 `EXT_LIBS` 列表中无 `airui`，`require` 退化为文件查找后失败，app 启动即崩溃。

**已有 250 个 PASS 的 app 均通过全局变量 `airui` 或 `exwin` 间接使用，未触发此缺陷。**

```diff
- "xmodem", "sys", "sysplus"
+ "xmodem", "sys", "sysplus", "airui"
```

---

### Fix 2: `pcall(json.decode)` 缺少 nil 检查 → `meta_data` 崩溃 (1 字)

**位置**: `install_remote_app` 内 (~4365 行)

**现象**: 二十四节气 app 崩溃 `exapp.lua:4387: attempt to index a nil value (local 'meta_data')`

**根因**: `json.decode("null")` 合法返回 `nil` 且不抛异常，`pcall` 返回 `true, nil`。`if ok then` 通过，后续 `meta_data.install_time = ...` 崩溃。

同一文件 line 3254 已有正确写法 `if not ok or type(meta_data) ~= "table"`，此处漏了。

```diff
- if ok then
+ if ok and type(meta_data) == "table" then
```

---

### Fix 3: `io.lsdir(dir, 100, 0)` 条目硬限制 → 卸载/拷贝不完整 (5 处, 各 +6 行)

**位置**: `copy_data_dir` ×2, `rmdir_recursive`, `dir_size_kb`, 数据迁移 (约 614/644/666/4079/4630 行)

**现象**: `jianfengchazhen`(飞针如缝) `res/` 目录含 **126 个 PNG 文件**，卸载时只删除前 100 个，`io.rmdir` 因目录非空失败，最终 `APP_STORE_ACTION_DONE` 返回失败。

**修复**: 所有 `io.lsdir(..., 100, 0)` 单次调用改为 `offset` 分页循环：

```diff
- local ret, list = io.lsdir(dir, 100, 0)
- if ret then
-     for _, item in ipairs(list) do ... end
- end
+ local offset = 0
+ while true do
+     local ret, list = io.lsdir(dir, 100, offset)
+     if not ret or not list or #list == 0 then break end
+     for _, item in ipairs(list) do ... end
+     if #list < 100 then break end
+     offset = offset + 100
+ end
```

---

### Fix 4: 缺少 `my_env.sys.taskInit` 代理 → app 任务逃逸沙箱致 VM 崩溃 (+12 行)

**位置**: `my_env.sys` 代理区 (~2569 行之后)

**现象**: xiaobang_v2_remote/slate/thorn/vale/wren 共 5 个 app 触发 `E/main Lua VM exit!!`

**根因**: 沙箱覆盖了 `sys` 的 7 个方法（run/subscribe/timerStart/timerLoopStart/timerStop/timerStopAll），**唯独漏了 `taskInit`**。`my_env.sys` 元表 `{__index = _G.sys}` 使未覆盖的方法穿透到真实实现。

app 调用 `sys.taskInit(ble_task_func)` 后，任务在**主线程**而非沙箱协程上运行。当任务在 PC 模拟器上访问不存在的 `bluetooth` 模块 → 错误不被沙箱 `xpcall` 捕获 → `Lua VM exit`。

日志可见时序证据：沙箱协程 `[01.968] co quit` → 2ms 后主线程 `[01.970] E/main Lua VM exit`

```lua
my_env.sys.taskInit = function(func, ...)
    local wrapped = function()
        local ok, err = xpcall(func, debug.traceback, ...)
        if not ok then
            my_env.log.error("taskInit", "task error:", err)
        end
    end
    local id = glob_sys.taskInit(wrapped)
    if id then
        table.insert(timer_ids, id)
        my_env.log.info("task_init", "task registered, ID:", id)
    end
    return id
end
```

---

### 影响评估

| 缺陷 | 影响 app 数 | 严重度 | 类型 |
|------|-----------|--------|------|
| EXT_LIBS 缺 airui | ~6 (require("airui") 的 app) | 高 | 功能性 |
| json.decode nil 检查 | ~1 (meta.json 异常时) | 中 | 防御性 |
| lsdir 100 限制 | ~3 (资源文件 >100 个) | 中 | 正确性 |
| taskInit 未代理 | ~5+ (使用 sys.taskInit 的 app) | **高** | 安全性(沙箱逃逸) |

**所有修复位于 `script/libs/exapp.lua`，共约 30 行增量。**
