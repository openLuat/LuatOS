--- 通用 cycle profiler(prof 组件)端到端测试模块
-- 基于内建 prof.selftest() 模块, 不依赖任何外部消费者
-- 未开启 LUAT_USE_PROF 的固件(默认): 所有用例 SKIP, 不判失败
-- @module prof_test

local sys = require("sys")
-- prof 是 C 内置模块, 通过全局变量访问(非 require); 默认固件中不存在
local prof = prof

local prof_test = {}

local SELF_MOD = "prof.selftest"

-- 返回 false 表示本构建未启用 LUAT_USE_PROF, 用例按 SKIP 处理
-- 注意: rotable2 实现的 C 库 type() 为 userdata, 不是 table
local function need_prof(case)
    if prof == nil or type(prof.enable) ~= "function" then
        log.warn("prof_test", case .. " SKIP: prof 库不存在(未定义 LUAT_USE_PROF, 属默认行为)")
        return false
    end
    return true
end

-- 取 selftest 模块的某个 slot 统计, 断言结构完整
local function selftest_slot(st, name)
    assert(type(st) == "table", "dump 未返回 table")
    local m = st[SELF_MOD]
    assert(type(m) == "table" and m.slots == 2, "prof.selftest 模块未注册或槽位数不对")
    local s = m[name]
    assert(type(s) == "table" and s.ticks and s.calls and s.max, "slot " .. name .. " 缺少 ticks/calls/max 字段")
    return s
end

function prof_test.test_enable_disable()
    if not need_prof("test_enable_disable") then return end

    assert(prof.enable(true) == true, "enable(true) 后状态应为 true")
    assert(prof.enable(false) == false, "enable(false) 后状态应为 false")
    assert(prof.enable() == false, "无参读取应保持当前状态")
    log.info("prof_test", "enable/disable OK")
end

function prof_test.test_selftest_counts()
    if not need_prof("test_selftest_counts") then return end

    prof.enable(true)
    assert(prof.selftest() == true, "selftest 应执行成功")
    local st = prof.dump()
    assert(st.enabled == true, "dump.enabled 应为 true")
    assert(st.mods >= 1, "dump.mods 应 >= 1")

    local spin = selftest_slot(st, "spin")
    local accum = selftest_slot(st, "accum")
    assert(spin.calls == 1, "spin.calls 应为 1, 实际 " .. tostring(spin.calls))
    assert(accum.calls == 1, "accum.calls 应为 1, 实际 " .. tostring(accum.calls))

    local tpu = prof.ticks_per_us()
    if spin.ticks == 0 and accum.ticks == 0 and prof.tick() == 0 then
        -- 平台无 cycle 计数器: 明确 NO-DATA, 不按"零开销"解读
        log.warn("prof_test", "cycle counter 不可用, 本次运行按 NO-DATA 处理(calls 语义已验证)")
    else
        assert(spin.ticks > 0 and accum.ticks > 0, "有计数器时 ticks 应 > 0")
        assert(spin.max > 0 and spin.max <= spin.ticks, "max 应在 (0, ticks] 区间")
        log.info("prof_test", string.format("spin ticks=%d accum ticks=%d ticks_per_us=%d",
            spin.ticks, accum.ticks, tpu))
    end
    prof.enable(false)
end

function prof_test.test_disabled_no_count()
    if not need_prof("test_disabled_no_count") then return end

    prof.enable(false)          -- 关闭即清零
    assert(prof.selftest() == true, "关态下 selftest 仍应可执行(空跑)")
    local spin = selftest_slot(prof.dump(), "spin")
    assert(spin.calls == 0 and spin.ticks == 0, "关态下不应产生任何计数")
    log.info("prof_test", "关态零采集 OK")
end

function prof_test.test_reset()
    if not need_prof("test_reset") then return end

    prof.enable(true)
    prof.selftest()
    prof.reset()
    local spin = selftest_slot(prof.dump(), "spin")
    assert(spin.calls == 0 and spin.ticks == 0 and spin.max == 0, "reset 后计数应全部归零")
    assert(prof.enable() == true, "reset 不应改变启用状态")
    prof.enable(false)
    log.info("prof_test", "reset OK")
end

return prof_test
