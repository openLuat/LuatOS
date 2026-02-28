/*
@module  rtmp
@summary RTMP 直播推流
@version 1.0
@date    2025.12.8
@tag     LUAT_USE_RTMP
@usage
-- RTMP推流示例
local rtmp = rtmp.create("rtmp://example.com:1935/live/stream")
rtmp:setCallback(function(state, ...)
    if state == rtmp.STATE_CONNECTED then
        print("已连接到推流服务器")
    elseif state == rtmp.STATE_PUBLISHING then
        print("已开始推流")
    elseif state == rtmp.STATE_ERROR then
        print("出错:", ...)
    end
end)
rtmp:connect()

-- 开始处理
rtmp:start()

-- 30秒后停止
sys.wait(30000)
rtmp:stop()

-- 断开连接
rtmp:disconnect()
rtmp:destroy()
*/

#include "luat_base.h"
#include "luat_rtmp_push.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "lauxlib.h"
#include <stdlib.h>
#include "lwip/timeouts.h"
#include "lwip/tcpip.h"

#define LUAT_LOG_TAG "rtmp"
#include "luat_log.h"

typedef struct {
    rtmp_ctx_t *rtmp;
    int callback_ref;
    int polling;          /* 1=已启动定时轮询, 0=未启动 */
} luat_rtmp_userdata_t;

/**
创建RTMP推流上下文
@api rtmp.create(url)
@string url RTMP服务器地址, 格式: rtmp://host:port/app/stream
@return userdata RTMP上下文对象
@usage
local rtmp = rtmp.create("rtmp://example.com:1935/live/stream")
*/
static int l_rtmp_create(lua_State *L) {
    const char *url = luaL_checkstring(L, 1);
    
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)lua_newuserdata(L, sizeof(luat_rtmp_userdata_t));
    if (!ud) {
        LLOGE("内存分配失败");
        lua_pushnil(L);
        return 1;
    }
    
    ud->rtmp = rtmp_create();
    if (!ud->rtmp) {
        LLOGE("RTMP上下文创建失败");
        lua_pushnil(L);
        return 1;
    }
    ud->rtmp->user_data = (void *)ud;
    
    ud->callback_ref = LUA_NOREF;
    
    if (rtmp_set_url(ud->rtmp, url) != 0) {
        LLOGE("RTMP URL设置失败");
        rtmp_destroy(ud->rtmp);
        lua_pushnil(L);
        return 1;
    }
    
    luaL_getmetatable(L, "rtmp_ctx");
    lua_setmetatable(L, -2);
    
    LLOGD("RTMP上下文创建成功: %s", url);
    return 1;
}

/**
设置RTMP状态回调函数
@api rtmp:setCallback(func)
@function func 回调函数, 参数为 (state, ...) 
@return nil 无返回值
@usage
rtmp:setCallback(function(state, ...)
    if state == rtmp.STATE_IDLE then
        print("空闲状态")
    elseif state == rtmp.STATE_CONNECTING then
        print("正在连接")
    elseif state == rtmp.STATE_HANDSHAKING then
        print("握手中")
    elseif state == rtmp.STATE_CONNECTED then
        print("已连接")
    elseif state == rtmp.STATE_PUBLISHING then
        print("推流中")
    elseif state == rtmp.STATE_DISCONNECTING then
        print("正在断开")
    elseif state == rtmp.STATE_ERROR then
        print("错误:", ...)
    end
end)
*/
static int l_rtmp_set_callback(lua_State *L) {
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)luaL_checkudata(L, 1, "rtmp_ctx");
    if (!ud || !ud->rtmp) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    if (lua_isfunction(L, 2)) {
        if (ud->callback_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, ud->callback_ref);
        }
        lua_pushvalue(L, 2);
        ud->callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        LLOGD("RTMP回调函数已设置");
    } else if (lua_isnil(L, 2)) {
        if (ud->callback_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, ud->callback_ref);
            ud->callback_ref = LUA_NOREF;
        }
        LLOGD("RTMP回调函数已清除");
    } else {
        LLOGE("参数错误，需要function或nil");
        lua_pushboolean(L, 0);
        return 1;
    }
    
    lua_pushboolean(L, 1);
    return 1;
}

static int l_rtmp_handler(lua_State *L, void *udata) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)msg->ptr;
    if (!ud || ud->callback_ref == LUA_NOREF) {
        return 0;
    }
    int state = msg->arg1;
    lua_rawgeti(L, LUA_REGISTRYINDEX, ud->callback_ref);
    if (lua_isfunction(L, -1)) {
        lua_pushinteger(L, state);
        lua_call(L, 1, 0);
    }
    return 0;
}

/**
状态回调函数（内部使用）
*/
static void l_state_callback(rtmp_ctx_t *ctx, rtmp_state_t oldstate, rtmp_state_t newstate, int error_code) {
    rtos_msg_t msg = {0};
    msg.handler = l_rtmp_handler;
    msg.ptr = ctx->user_data;
    msg.arg1 = (int)newstate;
    msg.arg2 = (int)oldstate;
    LLOGD("RTMP状态(%d)回调消息入队 %p %p", (int)newstate, &msg, ctx->user_data);
    luat_msgbus_put(&msg, 0);
}

/**
连接到RTMP服务器
@api rtmp:connect()
@return boolean 成功返回true, 失败返回false
@usage
local ok = rtmp:connect()
if ok then
    print("连接请求已发送")
else
    print("连接失败")
end
*/
static int l_rtmp_connect(lua_State *L) {
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)luaL_checkudata(L, 1, "rtmp_ctx");
    if (!ud || !ud->rtmp) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    rtmp_set_state_callback(ud->rtmp, l_state_callback);
    
    int ret = tcpip_callback_with_block(rtmp_connect, (void *)ud->rtmp, 0);
    LLOGD("RTMP发起连接请求: %s", ret == 0 ? "成功" : "失败");
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/* 前向声明 */
static void t_rtmp_poll(void *arg);

/**
断开RTMP连接
@api rtmp:disconnect()
@return boolean 成功返回true, 失败返回false
@usage
rtmp:disconnect()
*/
static int l_rtmp_disconnect(lua_State *L) {
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)luaL_checkudata(L, 1, "rtmp_ctx");
    if (!ud || !ud->rtmp) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    /* 先停止定时轮询，防止断开后继续访问 */
    if (ud->polling) {
        ud->polling = 0;
        sys_untimeout(t_rtmp_poll, ud->rtmp);
    }
    
    int ret = tcpip_callback_with_block(rtmp_disconnect, (void *)ud->rtmp, 0);
    LLOGD("RTMP发起断开连接请求: %s", ret == 0 ? "成功" : "失败");
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

static void t_rtmp_poll(void *arg) {
    rtmp_ctx_t *ctx = (rtmp_ctx_t *)arg;
    if (!ctx || !ctx->user_data) {
        return; /* 上下文已销毁，不再续注定时器 */
    }
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)ctx->user_data;
    if (!ud->polling) {
        return; /* 已停止，不再续注定时器 */
    }
    rtmp_poll(ctx);
    sys_timeout(20, t_rtmp_poll, ctx);
}

/**
处理RTMP事件
@api rtmp:start()
@return nil 无返回值
@usage
rtmp:start()
*/
static int l_rtmp_start(lua_State *L) {
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)luaL_checkudata(L, 1, "rtmp_ctx");
    if (!ud || !ud->rtmp) {
        return 0;
    }
    if (!ud->polling) {
        ud->polling = 1;
        sys_timeout(20, t_rtmp_poll, ud->rtmp);
    }
    return 0;
}

/**
停止RTMP事件轮询
@api rtmp:stop()
@return nil 无返回值
@usage
rtmp:stop()
*/
static int l_rtmp_stop(lua_State *L) {
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)luaL_checkudata(L, 1, "rtmp_ctx");
    if (!ud || !ud->rtmp) {
        return 0;
    }
    if (ud->polling) {
        ud->polling = 0;
        sys_untimeout(t_rtmp_poll, ud->rtmp);
    }
    return 0;
}

/**
获取RTMP连接状态
@api rtmp:getState()
@return int 当前状态值
@usage
local state = rtmp:getState()
if state == rtmp.STATE_CONNECTED then
    print("已连接")
elseif state == rtmp.STATE_PUBLISHING then
    print("正在推流")
end
*/
static int l_rtmp_get_state(lua_State *L) {
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)luaL_checkudata(L, 1, "rtmp_ctx");
    if (!ud || !ud->rtmp) {
        lua_pushinteger(L, -1);
        return 1;
    }
    
    rtmp_state_t state = rtmp_get_state(ud->rtmp);
    lua_pushinteger(L, (lua_Integer)state);
    return 1;
}

/**
获取RTMP统计信息
@api rtmp:getStats()
@return table 统计信息表
@usage
local stats = rtmp:getStats()
print("已发送字节数:", stats.bytes_sent)
print("已发送视频帧数:", stats.video_frames_sent)
print("已发送音频帧数:", stats.audio_frames_sent)
*/
static int l_rtmp_get_stats(lua_State *L) {
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)luaL_checkudata(L, 1, "rtmp_ctx");
    if (!ud || !ud->rtmp) {
        lua_pushnil(L);
        return 1;
    }
    
    rtmp_stats_t stats = {0};
    rtmp_get_stats(ud->rtmp, &stats);
    
    lua_newtable(L);
    lua_pushinteger(L, stats.bytes_sent);
    lua_setfield(L, -2, "bytes_sent");
    lua_pushinteger(L, stats.video_frames_sent);
    lua_setfield(L, -2, "video_frames_sent");
    lua_pushinteger(L, stats.audio_frames_sent);
    lua_setfield(L, -2, "audio_frames_sent");
    lua_pushinteger(L, stats.connection_time);
    lua_setfield(L, -2, "connection_time");
    
    return 1;
}

/**
销毁RTMP上下文，释放所有资源
@api rtmp:destroy()
@return nil 无返回值
@usage
rtmp:destroy()
*/
static int l_rtmp_destroy(lua_State *L) {
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)luaL_checkudata(L, 1, "rtmp_ctx");
    if (!ud || !ud->rtmp) {
        return 0;
    }
    
    /* 取消定时轮询，防止 UAF */
    if (ud->polling) {
        ud->polling = 0;
        sys_untimeout(t_rtmp_poll, ud->rtmp);
    }
    
    if (ud->callback_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, ud->callback_ref);
        ud->callback_ref = LUA_NOREF;
    }
    
    rtmp_destroy(ud->rtmp);
    ud->rtmp = NULL;
    
    LLOGD("RTMP上下文已销毁");
    return 0;
}

static int l_rtmp_gc(lua_State *L) {
    luat_rtmp_userdata_t *ud = (luat_rtmp_userdata_t *)luaL_checkudata(L, 1, "rtmp_ctx");
    if (ud && ud->rtmp) {
        /* 取消定时轮询，防止 UAF */
        if (ud->polling) {
            ud->polling = 0;
            sys_untimeout(t_rtmp_poll, ud->rtmp);
        }
        if (ud->callback_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, ud->callback_ref);
        }
        rtmp_destroy(ud->rtmp);
        ud->rtmp = NULL;
    }
    return 0;
}

#include "rotable2.h"

static const rotable_Reg_t reg_rtmp_ctx[] = {
    {"setCallback",   ROREG_FUNC(l_rtmp_set_callback)},
    {"connect",       ROREG_FUNC(l_rtmp_connect)},
    {"disconnect",    ROREG_FUNC(l_rtmp_disconnect)},
    {"start",         ROREG_FUNC(l_rtmp_start)},
    {"stop",          ROREG_FUNC(l_rtmp_stop)},
    {"getState",      ROREG_FUNC(l_rtmp_get_state)},
    {"getStats",      ROREG_FUNC(l_rtmp_get_stats)},
    {"destroy",       ROREG_FUNC(l_rtmp_destroy)},
    {"__gc",          ROREG_FUNC(l_rtmp_gc)},
    {NULL,            ROREG_INT(0)}
};

static const rotable_Reg_t reg_rtmp[] = {
    {"create",            ROREG_FUNC(l_rtmp_create)},
    
    // RTMP状态常量
    {"STATE_IDLE",        ROREG_INT(RTMP_STATE_IDLE)},
    {"STATE_CONNECTING",  ROREG_INT(RTMP_STATE_CONNECTING)},
    {"STATE_HANDSHAKING", ROREG_INT(RTMP_STATE_HANDSHAKING)},
    {"STATE_CONNECTED",   ROREG_INT(RTMP_STATE_CONNECTED)},
    {"STATE_PUBLISHING",  ROREG_INT(RTMP_STATE_PUBLISHING)},
    {"STATE_DISCONNECTING",ROREG_INT(RTMP_STATE_DISCONNECTING)},
    {"STATE_ERROR",       ROREG_INT(RTMP_STATE_ERROR)},
    
    {NULL,                ROREG_INT(0)}
};

static int _rtmp_struct_index(lua_State *L) {
	const rotable_Reg_t* reg = reg_rtmp_ctx;
    const char* key = luaL_checkstring(L, 2);
	while (1) {
		if (reg->name == NULL)
			return 0;
		if (!strcmp(reg->name, key)) {
			lua_pushcfunction(L, reg->value.value.func);
			return 1;
		}
		reg ++;
	}
}

LUAMOD_API int luaopen_rtmp(lua_State *L) {
    luat_newlib2(L, reg_rtmp);
    
    luaL_newmetatable(L, "rtmp_ctx");
    lua_pushcfunction(L, _rtmp_struct_index);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
    
    return 1;
}
