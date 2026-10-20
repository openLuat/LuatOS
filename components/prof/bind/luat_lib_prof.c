/*
@module  prof
@summary cycle profiler(性能周期剖析), 调优专用, 需 BSP 定义 LUAT_USE_PROF 才编译
@date    2026.10.14
@author  wendal
@tag LUAT_USE_PROF
@usage
-- 默认固件未开启 LUAT_USE_PROF, 本库不存在.
-- 调优构建中:
prof.enable(true)            -- 启用并清零
... 跑被测业务 ...
local st = prof.dump()       -- st.enabled / st.mods / st["模块名"].slots / 各 slot {ticks=,calls=,max=}
for name, m in pairs(st) do
    if type(m) == "table" and m.slots then
        for sname, v in pairs(m) do
            if type(v) == "table" then log.info("prof", name, sname, v.ticks, v.calls, v.max) end
        end
    end
end
prof.enable(false)           -- 关闭
*/

#include "luat_base.h"

/* 关态(LUAT_USE_PROF 未定义)时本 TU 为空, 避免 MSVC C4206 告警 */
typedef int luat_lib_prof_empty_tu_t;

#ifdef LUAT_USE_PROF

#include "lua.h"
#include "lauxlib.h"
#include "luat_prof.h"

#define LUAT_LOG_TAG "prof"
#include "luat_log.h"

/*
启用/关闭剖析器, 或只读取状态
@api prof.enable(on)
@boolean true=启用并清零, false=关闭并清零; 不传则只返回当前状态
@return boolean 当前是否启用
@usage
prof.enable(true)
*/
static int l_prof_enable(lua_State *L)
{
    if (lua_isboolean(L, 1))
    {
        luat_prof_enable(lua_toboolean(L, 1));
    }
    lua_pushboolean(L, luat_prof_on);
    return 1;
}

/*
清零所有模块的计数器, 保持当前启用状态
@api prof.reset()
*/
static int l_prof_reset(lua_State *L)
{
    (void)L;
    luat_prof_reset();
    return 0;
}

/*
读原始 cycle 计数器当前值
@api prof.tick()
@return int 原始 tick; 平台无计数器时恒为 0(NO-DATA)
*/
static int l_prof_tick(lua_State *L)
{
    lua_pushinteger(L, (lua_Integer)LUAT_PROF_TICK());
    return 1;
}

/*
tick 与微秒的换算系数
@api prof.ticks_per_us()
@return int 每微秒的 tick 数; 0 表示 BSP 未提供频率信息, 只能比较 ticks 相对占比
*/
static int l_prof_ticks_per_us(lua_State *L)
{
    lua_pushinteger(L, (lua_Integer)luat_prof_ticks_per_us());
    return 1;
}

/*
读取全部已注册模块的统计
@api prof.dump()
@return table {enabled=bool, ticks_per_us=int, mods=int, [i]=模块名, [模块名]={slots=int, [i]=槽位名, [槽位名]={ticks=,calls=,max=}}}
*/
static int l_prof_dump(lua_State *L)
{
    int mods = luat_prof_modules();
    int i, j, slots;

    lua_newtable(L);
    lua_pushboolean(L, luat_prof_on);
    lua_setfield(L, -2, "enabled");
    lua_pushinteger(L, (lua_Integer)luat_prof_ticks_per_us());
    lua_setfield(L, -2, "ticks_per_us");
    lua_pushinteger(L, mods);
    lua_setfield(L, -2, "mods");

    for (i = 0; i < mods; i++)
    {
        const char *mname = luat_prof_module_name(i);
        lua_pushinteger(L, i + 1);
        lua_pushstring(L, mname);
        lua_settable(L, -3);

        lua_newtable(L);
        slots = luat_prof_slots(i);
        lua_pushinteger(L, slots);
        lua_setfield(L, -2, "slots");

        for (j = 0; j < slots; j++)
        {
            const char *sname = luat_prof_slot_name(i, j);
            lua_pushinteger(L, j + 1);
            lua_pushstring(L, sname);
            lua_settable(L, -3);

            lua_newtable(L);
            lua_pushinteger(L, (lua_Integer)luat_prof_slot_ticks(i, j));
            lua_setfield(L, -2, "ticks");
            lua_pushinteger(L, (lua_Integer)luat_prof_slot_calls(i, j));
            lua_setfield(L, -2, "calls");
            lua_pushinteger(L, (lua_Integer)luat_prof_slot_max(i, j));
            lua_setfield(L, -2, "max");
            lua_setfield(L, -2, sname);
        }
        lua_setfield(L, -2, mname);
    }
    return 1;
}

/*
内建自测: 注册 "prof.selftest" 模块并跑两段已知 span, 用于无消费者时端到端验证
@api prof.selftest()
@return boolean true=已执行(需 LUAT_USE_PROF 且剖析器已 enable 才有计数)
@usage
prof.enable(true)
prof.selftest()
local st = prof.dump()  -- st["prof.selftest"].spin.ticks > 0
*/
static const char *const prof_selftest_slots[] = {"spin", "accum"};

static int l_prof_selftest(lua_State *L)
{
    static int selftest_id = -1;
    uint32_t tok;
    volatile uint32_t sink = 0;
    uint32_t i;

    if (selftest_id < 0)
    {
        selftest_id = luat_prof_register("prof.selftest", prof_selftest_slots, 2);
        if (selftest_id < 0)
        {
            lua_pushboolean(L, 0);
            return 1;
        }
    }

    LUAT_PROF_BEGIN(tok);
    for (i = 0; i < 100000; i++)
    {
        sink += i;
    }
    LUAT_PROF_END(selftest_id, 0, tok);

    LUAT_PROF_BEGIN(tok);
    for (i = 0; i < 10000; i++)
    {
        sink = sink * 1664525u + 1013904223u;
    }
    LUAT_PROF_END(selftest_id, 1, tok);

    (void)sink;
    lua_pushboolean(L, 1);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_prof[] =
{
    { "enable",       ROREG_FUNC(l_prof_enable)},
    { "reset",        ROREG_FUNC(l_prof_reset)},
    { "tick",         ROREG_FUNC(l_prof_tick)},
    { "ticks_per_us", ROREG_FUNC(l_prof_ticks_per_us)},
    { "dump",         ROREG_FUNC(l_prof_dump)},
    { "selftest",     ROREG_FUNC(l_prof_selftest)},
    { NULL,           ROREG_INT(0)}
};

LUAMOD_API int luaopen_prof(lua_State *L)
{
    luat_newlib2(L, reg_prof);
    return 1;
}

#endif /* LUAT_USE_PROF */
