--[[
@module  mtnlog
@summary 运维日志分级写入（工程侧薄封装，只调用合宙官方库的公开接口）
@version 1.0（8203 新增）
@date    2026.09.28

=== 为什么需要这个文件 ===
本工程原先调用的是 `excloud.mtn_log(level, tag, ...)` 的**四参形式**，
但那是 iRTU 对 excloud 的定制扩展。合宙**官方** excloud 的公开接口是
`excloud.mtn_log(tag, ...)` —— **内部固定 info 级**。

按"LIB 必须使用合宙官方最新版、由业务代码适配官方接口"的约定（见 `AGENTS.md` §1.3），
工程侧不再依赖任何定制库，改为在这里做一层薄封装：

    mtnlog.info(tag, ...)   →  exmtn.log("info",  tag, ...)
    mtnlog.warn(tag, ...)   →  exmtn.log("warn",  tag, ...)
    mtnlog.error(tag, ...)  →  exmtn.log("error", tag, ...)

`exmtn` 与 `excloud` 一样是**合宙官方扩展库**（`script/libs/exmtn.lua`），
`exmtn.log(level, tag, ...)` 是它的公开接口（官方 @api 文档原文：
「@string level 日志级别，必须是 "info", "warn", 或 "error"」）
→ 所以本封装同样**只使用官方公开接口**，没有修改任何官方库。
官方行为：既按级别打串口日志，又把内容写入运维日志文件。

=== 为什么不用 excloud.mtn_log ===
官方版它固定 info 级，无法表达 warn / error；而本工程"1293 上报异常"等场景
需要 warn 级，便于平台侧按级别筛选运维日志。两者底座其实是同一套 exmtn。

=== 健壮性（日志问题绝不能影响业务主流程） ===
· exmtn 未初始化（如配置里运维日志开关关闭）→ 返回 false，不抛异常
· exmtn 库缺失 → 静默跳过
· 任何异常都被 pcall 兜住，调用方无需关心
]]

local mtnlog = {}

-- 惰性获取官方 exmtn，避免在模块加载期就建立强依赖
local function get_exmtn()
    local ok, m = pcall(require, "exmtn")
    if ok and type(m) == "table" and type(m.log) == "function" then
        return m
    end
    return nil
end

local function write(level, tag, ...)
    if type(tag) ~= "string" or tag == "" then
        return false
    end

    local exmtn = get_exmtn()
    if not exmtn then
        return false
    end

    -- 官方 exmtn.log 在未 init 时写文件会失败并返回 false（不抛异常）；
    -- 这里再用 pcall 兜一层，确保任何异常都不会传导给业务调用方
    local ok = pcall(exmtn.log, level, tag, ...)
    return ok
end

function mtnlog.info(tag, ...)  return write("info",  tag, ...) end
function mtnlog.warn(tag, ...)  return write("warn",  tag, ...) end
function mtnlog.error(tag, ...) return write("error", tag, ...) end

--[[
尽力把运维日志缓存落盘。

背景：iRTU 定制版 exmtn 提供 `exmtn.flush()`（CACHE_WRITE 模式下强制落盘），
**合宙官方 exmtn 没有这个接口**。按"官方没有的能力在工程侧补"的要求，
这里提供一个同名能力：

  · 若官方将来补上 flush → 直接调用
  · 否则返回 false，并给出替代方案（见下）

⚠️ 官方 exmtn 在 CACHE_WRITE 模式下由库内部自行决定落盘时机（缓存写满即落）。
   如果业务上确实需要"每条都立即写盘"（例如复位前必须保证日志可被服务器拉到），
   正确做法是**改配置**而不是改库：把 create.lua 的
   `mtn_log_write_way = excloud.MTN_LOG_CACHE_WRITE`
   改成 `excloud.MTN_LOG_ADD_WRITE`（直接写盘，无缓存）。

@return boolean 是否真的执行了落盘
]]
function mtnlog.flush()
    local exmtn = get_exmtn()
    if exmtn and type(exmtn.flush) == "function" then
        local ok = pcall(exmtn.flush)
        return ok
    end
    log.warn("mtnlog", "官方 exmtn 无 flush 接口，运维日志按 CACHE_WRITE 策略由库自动落盘",
        "（如需立即落盘，请把 create.lua 的 mtn_log_write_way 改为 MTN_LOG_ADD_WRITE）")
    return false
end

return mtnlog
