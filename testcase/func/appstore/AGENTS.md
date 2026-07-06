# 应用商店自动化测试 — 经验总结

## 测试架构

```
orchestrator.py (Python)
  ├── 从 API 拉取 app 列表
  ├── 逐个启动 PC 模拟器进程
  │     └── luatos-lua.exe → appstore_test.lua → test_single_app()
  │           ├── install: 下载 ZIP → 解压到 /app_store/
  │           ├── start:   sys.taskInit 启动 app
  │           ├── wait:    等待 3s 让 app 运行
  │           └── close:   exapp.close() → 卸载
  └── 汇总 result.json
```

每个 app 在**独立进程**中测试，进程间完全隔离。

## PC 模拟器路径映射

| 模拟器内路径 | 实际磁盘路径 |
|-------------|-------------|
| `/` (根) | `$(CWD)` — POSIX VFS 映射 |
| `/testresult/` | `<CWD>/testresult/` — 持久化，跨进程 |
| `/ram/` | 内存 RAM FS — **进程退出即丢失** |
| `/luadb/` | 编译时内嵌虚拟 FS |
| `/app_store/` | `<CWD>/app_store/` — **需每次清理** |

## 关键 Bug 及修复

### 1. `json.decode("null")` 返回 nil 不报错（exapp.lua）

**症状**：110/288 app 测试结果为 NORESULT (exit=0)

**根因**：
```lua
-- 修复前
local ok, meta_data = pcall(json.decode, meta_content)
if not ok then  -- json.decode("null") → ok=true, meta_data=nil，绕过检查
    goto continue
end
local size_kb = tonumber(meta_data.origin_size_kb)  -- 💥 nil index
```

**修复**：
```lua
if not ok or type(meta_data) ~= "table" then
    goto continue
end
```

**教训**：`pcall` 只捕获异常，不保证返回值类型。JSON 字面量 `null`/`true`/`false`/数字 都是合法 JSON，`json.decode` 都能成功返回非 table 值。

### 2. 崩溃检测：exit code 不是唯一的信号

`exit=0` 也可能是崩溃（Lua VM 正常退出但之前已崩溃）。检测逻辑：

```python
crashed = (
    "FATAL CRASH" in combined   # Win32 crash handler 输出
    or "Lua VM exit" in combined # Lua 层致命错误
    or nt_code & 0xC0000000 == 0xC0000000  # Windows NT 状态码
)
```

### 3. 残留目录污染

每次测试前必须清理 `/app_store/`。下载失败的 app 可能留下残缺的 `meta.json`，其内容可能是服务端错误页（JSON `{"code":404,...}`），导致后续 app 的 `exapp.init()` 扫描时崩溃。

```python
# orchestrator.py: test_one_app()
shutil.rmtree(str(app_store), ignore_errors=True)
```

## 崩溃分类（288 app 测试结果）

| 类别 | 数量 | 根因 |
|------|------|------|
| **NULL 函数指针** (DEP at 0x00000000) | 4 | 通过 NULL 函数指针调用 |
| **ACCESS_VIOLATION** (0xC0000005) | 38+ | NES/GBC 模拟器、LVGL 图形、模块 C 层初始化 |
| **airui 销毁后访问** | 29 | app 退出时定时器仍访问已销毁的 UI 组件 |
| **Lua 错误** | ~4 | nil global、nil function call |
| **PASS** | 190~ | 正常通过 |

## BGET 堆损坏调查结论

30+ ACCESS_VIOLATION crash 的 `.dmp` 文件中有 41% 崩溃在 `bget.c` 的 free list 遍历代码（RVA 0x8A010, 0x8A2A8）。但添加 FreeWipe/canary/assert 后，**同一批 app 的崩溃点并未出现在 BGET 内部**。

结论：RVA 地址与 BGET 函数重合是因为代码段地址重叠（链接顺序），**实际根因在各 app 自身的 C 模块**（NES 模拟器、LVGL、网络模块等），而非 BGET 分配器本身。

## 测试自动化经验

### 缓存策略

```python
# passed_cache.json: 记录已测试 app 的结果
# 删除此文件强制全量重测
cache[aid] = {"passed": bool, "crashed": bool, "stages": {...}, ...}
```

### 服务端限流

- 下载失败（服务器返回错误）→ 等 60s 冷却
- 正常完成 → 等 1.5s
- API 拉取列表也需 `time.sleep(1)` 控制频率

### orchestrator.py 使用

```bash
# 全量测试
python3 orchestrator.py

# 只测特定 app 列表
python3 orchestrator.py --filter testresult/crash_list.json
```

过滤文件格式：`[{"aid": "xxx", "url": "https://...", "name": "显示名"}, ...]`

## 未完成的工作

- **airui 销毁后访问**（29 个 crash）：需在 `exapp.close()` 时先停掉 app 的定时器，再销毁 UI 树
- crash 根因深挖：需用 WinDbg 逐个分析 .dmp 文件
