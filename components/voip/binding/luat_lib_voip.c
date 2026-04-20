/*
 * luat_lib_voip.c - VoIP 模块 Lua 绑定
 *
 * 对外提供 voip 模块:
 *   voip.start(opts)     -- 启动 VoIP 音频引擎
 *   voip.stop()          -- 停止
 *   voip.on(event, cb)   -- 注册回调
 *   voip.stats()         -- 获取统计信息
 *   voip.isRunning()     -- 是否运行中
 *   voip.getState()      -- 获取状态
 */

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_voip_core.h"
#include "rotable2.h"
#include "luat_network_adapter.h"
#define LUAT_LOG_TAG "voip"
#include "luat_log.h"

#include <string.h>

/*
@api voip.start(opts)
@tag LUAT_USE_VOIP
@table opts 配置表
@return boolean 成功返回 true, 失败返回 false
@usage
-- 麦克风全双工模式
voip.start({
    remote_ip   = "192.168.1.100",
    remote_port = 10000,
    local_port  = 10000,
    codec       = 0,            -- 0:PCMU  1:PCMA
    ptime       = 20,           -- 打包时长 ms
    sample_rate = 8000,
    jitter_depth= 3,
    multimedia_id = 0,
    stats_interval = 5000,      -- 统计回调间隔 ms, 0=不回调
})
*/
static int l_voip_start(lua_State *L)
{
    if (!lua_istable(L, 1)) {
        LLOGE("voip.start requires a table argument");
        lua_pushboolean(L, 0);
        return 1;
    }

    voip_config_t cfg;
    memset(&cfg, 0, sizeof(cfg));

    /* remote_ip */
    lua_getfield(L, 1, "remote_ip");
    if (lua_isstring(L, -1)) {
        const char *ip = lua_tostring(L, -1);
        size_t len = strlen(ip);
        if (len >= sizeof(cfg.remote_ip)) len = sizeof(cfg.remote_ip) - 1;
        memcpy(cfg.remote_ip, ip, len);
        cfg.remote_ip[len] = '\0';
    }
    lua_pop(L, 1);

    /* remote_port */
    lua_getfield(L, 1, "remote_port");
    cfg.remote_port = (uint16_t)luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    /* local_port */
    lua_getfield(L, 1, "local_port");
    cfg.local_port = (uint16_t)luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    /* codec: 0=PCMU, 1=PCMA */
    lua_getfield(L, 1, "codec");
    cfg.codec = (uint8_t)luaL_optinteger(L, -1, VOIP_CODEC_PCMU);
    lua_pop(L, 1);

    /* ptime */
    lua_getfield(L, 1, "ptime");
    cfg.ptime = (uint16_t)luaL_optinteger(L, -1, VOIP_FRAME_MS_DEFAULT);
    lua_pop(L, 1);

    /* sample_rate */
    lua_getfield(L, 1, "sample_rate");
    cfg.sample_rate = (uint32_t)luaL_optinteger(L, -1, VOIP_SAMPLE_RATE_DEFAULT);
    lua_pop(L, 1);


    /* jitter_depth */
    lua_getfield(L, 1, "jitter_depth");
    cfg.jitter_depth = (uint16_t)luaL_optinteger(L, -1, VOIP_JB_DEPTH_DEFAULT);
    lua_pop(L, 1);

    /* multimedia_id */
    lua_getfield(L, 1, "multimedia_id");
    cfg.multimedia_id = (uint8_t)luaL_optinteger(L, -1, 0);
    lua_pop(L, 1);

    /* stats_interval */
    lua_getfield(L, 1, "stats_interval");
    cfg.stats_interval_ms = (uint32_t)luaL_optinteger(L, -1, VOIP_STATS_INTERVAL_DEFAULT);
    lua_pop(L, 1);

    /* adapter */
    lua_getfield(L, 1, "adapter");
    cfg.adapter = (int)luaL_optinteger(L, -1, network_get_last_register_adapter());
    lua_pop(L, 1);

    /* 基本校验 */
    if (cfg.remote_ip[0] == '\0' || cfg.remote_port == 0) {
        LLOGE("voip.start: remote_ip and remote_port are required");
        lua_pushboolean(L, 0);
        return 1;
    }

    int ret = voip_start(&cfg);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
@api voip.stop()
@tag LUAT_USE_VOIP
@return boolean 成功返回 true
@usage
voip.stop()
*/
static int l_voip_stop(lua_State *L)
{
    (void)L;
    int ret = voip_stop();
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
@api voip.on(event, callback)
@tag LUAT_USE_VOIP
@string event 事件名: "state", "stats", "error"
@function callback 回调函数
@return nil
@usage
voip.on("state", function(state)
    log.info("voip", "state changed:", state)  -- "started"/"stopped"/"error"
end)

voip.on("stats", function(stats)
    log.info("voip", "tx_packets:", stats.tx_packets, "rx_packets:", stats.rx_packets)
end)

voip.on("error", function(err)
    log.error("voip", "error:", err)
end)
*/
static int l_voip_on(lua_State *L)
{
    const char *event = luaL_checkstring(L, 1);
    voip_ctx_t *ctx = voip_get_ctx();

    if (!lua_isfunction(L, 2) && !lua_isnil(L, 2)) {
        return luaL_argerror(L, 2, "function or nil expected");
    }

    int *ref_ptr = NULL;
    if (strcmp(event, "state") == 0) {
        ref_ptr = &ctx->cb_state_ref;
    } else if (strcmp(event, "stats") == 0) {
        ref_ptr = &ctx->cb_stats_ref;
    } else if (strcmp(event, "error") == 0) {
        ref_ptr = &ctx->cb_error_ref;
    } else {
        LLOGW("voip.on: unknown event '%s'", event);
        return 0;
    }

    /* 释放旧的引用 */
    if (*ref_ptr != 0) {
        luaL_unref(L, LUA_REGISTRYINDEX, *ref_ptr);
        *ref_ptr = 0;
    }

    /* 设置新引用 */
    if (lua_isfunction(L, 2)) {
        lua_pushvalue(L, 2);
        *ref_ptr = luaL_ref(L, LUA_REGISTRYINDEX);
    }

    return 0;
}

/*
@api voip.stats()
@tag LUAT_USE_VOIP
@return table 统计信息
@usage
local s = voip.stats()
log.info("voip", "tx_packets:", s.tx_packets)
*/
static int l_voip_stats(lua_State *L)
{
    voip_stats_t stats;
    voip_get_stats(&stats);

    lua_newtable(L);
    lua_pushinteger(L, stats.tx_packets);      lua_setfield(L, -2, "tx_packets");
    lua_pushinteger(L, stats.tx_bytes);        lua_setfield(L, -2, "tx_bytes");
    lua_pushinteger(L, stats.rx_packets);      lua_setfield(L, -2, "rx_packets");
    lua_pushinteger(L, stats.rx_bytes);        lua_setfield(L, -2, "rx_bytes");
    lua_pushinteger(L, stats.rx_lost);         lua_setfield(L, -2, "rx_lost");
    lua_pushinteger(L, stats.rx_out_of_order); lua_setfield(L, -2, "rx_out_of_order");
    lua_pushinteger(L, stats.jb_played);       lua_setfield(L, -2, "jb_played");
    lua_pushinteger(L, stats.jb_silence);      lua_setfield(L, -2, "jb_silence");

    return 1;
}

/*
@api voip.isRunning()
@tag LUAT_USE_VOIP
@return boolean 是否正在运行
@usage
if voip.isRunning() then
    log.info("voip", "audio active")
end
*/
static int l_voip_is_running(lua_State *L)
{
    lua_pushboolean(L, voip_is_running());
    return 1;
}

/*
@api voip.getState()
@tag LUAT_USE_VOIP
@return string 状态字符串: "idle"/"starting"/"running"/"stopping"/"error"
@usage
log.info("voip", "state:", voip.getState())
*/
static int l_voip_get_state(lua_State *L)
{
    voip_state_t state = voip_get_state();
    const char *s;
    switch (state) {
    case VOIP_STATE_IDLE:     s = "idle"; break;
    case VOIP_STATE_STARTING: s = "starting"; break;
    case VOIP_STATE_RUNNING:  s = "running"; break;
    case VOIP_STATE_STOPPING: s = "stopping"; break;
    case VOIP_STATE_ERROR:    s = "error"; break;
    default:                  s = "unknown"; break;
    }
    lua_pushstring(L, s);
    return 1;
}

#include "rotable2.h"

static const rotable_Reg_t reg_voip[] =
{
    { "start",      ROREG_FUNC(l_voip_start)},
    { "stop",       ROREG_FUNC(l_voip_stop)},
    { "on",         ROREG_FUNC(l_voip_on)},
    { "stats",      ROREG_FUNC(l_voip_stats)},
    { "isRunning",  ROREG_FUNC(l_voip_is_running)},
    { "getState",   ROREG_FUNC(l_voip_get_state)},

    /* 常量 */
    { "PCMU",       ROREG_INT(VOIP_CODEC_PCMU)},
    { "PCMA",       ROREG_INT(VOIP_CODEC_PCMA)},

    { NULL,         ROREG_INT(0)}
};

LUAMOD_API int luaopen_voip(lua_State *L)
{
    luat_newlib2(L, reg_voip);
    return 1;
}
