/*
@module  rtsp
@summary RTSP 直播推流
@version 1.0
@date    2025.12.11
@tag     LUAT_USE_RTSP
@usage
-- RTSP推流示例
local rtsp = rtsp.create("rtsp://example.com:554/stream")
rtsp:setCallback(function(state, ...)
    if state == rtsp.STATE_CONNECTED then
        print("已连接到推流服务器")
    elseif state == rtsp.STATE_PLAYING then
        print("已开始推流")
    elseif state == rtsp.STATE_ERROR then
        print("出错:", ...)
    end
end)
rtsp:connect()

-- 开始处理
rtsp:start()

-- 30秒后停止
sys.wait(30000)
rtsp:stop()

-- 断开连接
rtsp:disconnect()
rtsp:destroy()
*/

#include "luat_base.h"
#include "luat_rtsp_push.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "lauxlib.h"
#include <stdlib.h>
#include "lwip/timeouts.h"
#include "lwip/tcpip.h"

#define LUAT_LOG_TAG "rtsp"
#include "luat_log.h"

typedef struct {
    rtsp_ctx_t *rtsp;
    int callback_ref;
} luat_rtsp_userdata_t;

/**
创建RTSP推流上下文
@api rtsp.create(url)
@string url RTSP服务器地址, 格式: rtsp://host:port/stream
@return userdata RTSP上下文对象
@usage
local rtsp = rtsp.create("rtsp://example.com:554/stream")
*/
static int l_rtsp_create(lua_State *L) {
    const char *url = luaL_checkstring(L, 1);
    
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)lua_newuserdata(L, sizeof(luat_rtsp_userdata_t));
    if (!ud) {
        LLOGE("内存分配失败");
        lua_pushnil(L);
        return 1;
    }
    
    ud->rtsp = rtsp_create();
    if (!ud->rtsp) {
        LLOGE("RTSP上下文创建失败");
        lua_pushnil(L);
        return 1;
    }
    ud->rtsp->user_data = (void *)ud;
    
    ud->callback_ref = LUA_NOREF;
    
    if (rtsp_set_url(ud->rtsp, url) != 0) {
        LLOGE("RTSP URL设置失败");
        rtsp_destroy(ud->rtsp);
        lua_pushnil(L);
        return 1;
    }
    
    luaL_getmetatable(L, "rtsp_ctx");
    lua_setmetatable(L, -2);
    
    LLOGD("RTSP上下文创建成功: %s", url);
    return 1;
}

/**
设置RTSP状态回调函数
@api rtsp:setCallback(func)
@function func 回调函数, 参数为 (state, ...) 
@return nil 无返回值
@usage
rtsp:setCallback(function(state, ...)
    if state == rtsp.STATE_IDLE then
        print("空闲状态")
    elseif state == rtsp.STATE_CONNECTING then
        print("正在连接")
    elseif state == rtsp.STATE_OPTIONS then
        print("发送OPTIONS")
    elseif state == rtsp.STATE_DESCRIBE then
        print("发送DESCRIBE")
    elseif state == rtsp.STATE_SETUP then
        print("发送SETUP")
    elseif state == rtsp.STATE_PLAY then
        print("发送PLAY请求")
    elseif state == rtsp.STATE_PLAYING then
        print("正在推流")
    elseif state == rtsp.STATE_DISCONNECTING then
        print("正在断开")
    elseif state == rtsp.STATE_ERROR then
        print("错误:", ...)
    end
end)
*/
static int l_rtsp_set_callback(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    if (lua_isfunction(L, 2)) {
        if (ud->callback_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, ud->callback_ref);
        }
        lua_pushvalue(L, 2);
        ud->callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        LLOGD("RTSP回调函数已设置");
    } else if (lua_isnil(L, 2)) {
        if (ud->callback_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, ud->callback_ref);
            ud->callback_ref = LUA_NOREF;
        }
        LLOGD("RTSP回调函数已清除");
    } else {
        LLOGE("参数错误，需要function或nil");
        lua_pushboolean(L, 0);
        return 1;
    }
    
    lua_pushboolean(L, 1);
    return 1;
}

static int l_rtsp_handler(lua_State *L, void *udata) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)msg->ptr;
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
static void l_state_callback(rtsp_ctx_t *ctx, rtsp_state_t oldstate, rtsp_state_t newstate, int error_code) {
    rtos_msg_t msg = {0};
    msg.handler = l_rtsp_handler;
    msg.ptr = ctx->user_data;
    msg.arg1 = (int)newstate;
    msg.arg2 = (int)oldstate;
    LLOGD("RTSP状态(%d)回调消息入队 %p %p", (int)newstate, &msg, ctx->user_data);
    // luat_msgbus_put(&msg, 0);
}

/**
连接到RTSP服务器
@api rtsp:connect()
@return boolean 成功返回true, 失败返回false
@usage
local ok = rtsp:connect()
if ok then
    print("连接请求已发送")
else
    print("连接失败")
end
*/
static int l_rtsp_connect(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    rtsp_set_state_callback(ud->rtsp, l_state_callback);
    
    int ret = tcpip_callback_with_block(rtsp_connect, (void *)ud->rtsp, 0);
    LLOGD("RTSP连接请求: %s", ret == 0 ? "成功" : "失败");
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/**
断开RTSP连接
@api rtsp:disconnect()
@return boolean 成功返回true, 失败返回false
@usage
rtsp:disconnect()
*/
static int l_rtsp_disconnect(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    int ret = rtsp_disconnect(ud->rtsp);
    LLOGD("RTSP断开连接: %s", ret == 0 ? "成功" : "失败");
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

static void t_rtsp_poll(void *arg) {
    rtsp_ctx_t *ctx = (rtsp_ctx_t *)arg;
    rtsp_poll(ctx);
    sys_timeout(20, t_rtsp_poll, ctx);
}

/**
处理RTSP事件
@api rtsp:start()
@return nil 无返回值
@usage
rtsp:start()
*/
static int l_rtsp_start(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        return 0;
    }
    sys_timeout(20, t_rtsp_poll, ud->rtsp);
    return 0;
}

/**
停止处理RTSP事件
@api rtsp:stop()
@return nil 无返回值
@usage
rtsp:stop()
*/
static int l_rtsp_stop(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        return 0;
    }
    // 移除定时器回调
    sys_untimeout(t_rtsp_poll, ud->rtsp);
    return 0;
}

/**
获取RTSP连接状态
@api rtsp:getState()
@return int 当前状态值
@usage
local state = rtsp:getState()
if state == rtsp.STATE_CONNECTED then
    print("已连接")
elseif state == rtsp.STATE_PLAYING then
    print("正在推流")
end
*/
static int l_rtsp_get_state(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        lua_pushinteger(L, -1);
        return 1;
    }
    
    rtsp_state_t state = rtsp_get_state(ud->rtsp);
    lua_pushinteger(L, (lua_Integer)state);
    return 1;
}

/**
设置H.264 SPS参数
@api rtsp:setSPS(sps_data)
@string sps_data 或 
@userdata sps_data H.264序列参数集数据
@return boolean 成功返回true, 失败返回false
@usage
local sps = string.fromBinary("\x67\x42...") -- H.264 SPS数据
rtsp:setSPS(sps)
*/
static int l_rtsp_set_sps(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    size_t len = 0;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 2, &len);
    
    if (rtsp_set_sps(ud->rtsp, data, (uint32_t)len) == RTSP_OK) {
        LLOGD("SPS已设置: %u字节", (uint32_t)len);
        lua_pushboolean(L, 1);
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

/**
设置H.264 PPS参数
@api rtsp:setPPS(pps_data)
@string pps_data 或 
@userdata pps_data H.264图像参数集数据
@return boolean 成功返回true, 失败返回false
@usage
local pps = string.fromBinary("\x68\xCB...") -- H.264 PPS数据
rtsp:setPPS(pps)
*/
static int l_rtsp_set_pps(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    size_t len = 0;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 2, &len);
    
    if (rtsp_set_pps(ud->rtsp, data, (uint32_t)len) == RTSP_OK) {
        LLOGD("PPS已设置: %u字节", (uint32_t)len);
        lua_pushboolean(L, 1);
    } else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

/**
推送H.264视频帧
@api rtsp:pushFrame(frame_data, timestamp)
@string frame_data 或 
@userdata frame_data H.264编码的视频帧数据
@int timestamp 时间戳(毫秒), 可选，为0则使用内部时间戳
@return int 成功时返回已发送或已入队的字节数, 失败返回负数
@usage
-- 持续推送H.264帧
local frame_data = ... -- 获取H.264帧数据
local timestamp = sys.now() % 0x100000000
local ret = rtsp:pushFrame(frame_data, timestamp)
if ret >= 0 then
    print("已发送", ret, "字节")
else
    print("发送失败:", ret)
end
*/
static int l_rtsp_push_frame(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        lua_pushinteger(L, -1);
        return 1;
    }
    
    size_t len = 0;
    const uint8_t *data = (const uint8_t *)luaL_checklstring(L, 2, &len);
    uint32_t timestamp = 0;
    
    if (!lua_isnil(L, 3)) {
        timestamp = (uint32_t)luaL_checkinteger(L, 3);
    }
    
    if (len == 0 || len > (1024 * 1024)) {
        LLOGE("帧数据大小无效: %u", (uint32_t)len);
        lua_pushinteger(L, RTSP_ERR_INVALID_PARAM);
        return 1;
    }
    
    int ret = rtsp_push_h264_frame(ud->rtsp, data, (uint32_t)len, timestamp);
    lua_pushinteger(L, ret);
    return 1;
}

/**
获取RTSP统计信息
@api rtsp:getStats()
@return table 统计信息表
@usage
local stats = rtsp:getStats()
print("已发送字节数:", stats.bytes_sent)
print("已发送视频帧数:", stats.video_frames_sent)
print("已发送RTP包数:", stats.rtp_packets_sent)
*/
static int l_rtsp_get_stats(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        lua_pushnil(L);
        return 1;
    }
    
    rtsp_stats_t stats = {0};
    rtsp_get_stats(ud->rtsp, &stats);
    
    lua_newtable(L);
    lua_pushinteger(L, stats.bytes_sent);
    lua_setfield(L, -2, "bytes_sent");
    lua_pushinteger(L, stats.video_frames_sent);
    lua_setfield(L, -2, "video_frames_sent");
    lua_pushinteger(L, stats.rtp_packets_sent);
    lua_setfield(L, -2, "rtp_packets_sent");
    lua_pushinteger(L, stats.connection_time);
    lua_setfield(L, -2, "connection_time");
    lua_pushinteger(L, stats.last_video_timestamp);
    lua_setfield(L, -2, "last_video_timestamp");
    
    return 1;
}

/**
设置RTP传输模式
@api rtsp:setTransportMode(mode)
@string mode 传输模式: "udp", "tcp", "udp_fec"
@return boolean 成功返回true，失败返回false
@usage
-- 使用TCP传输模式（适合外网）
rtsp:setTransportMode("tcp")
-- 使用UDP传输模式（适合局域网，默认）
rtsp:setTransportMode("udp")
-- 使用UDP+FEC传输模式（平衡方案）
rtsp:setTransportMode("udp_fec")
*/
static int l_rtsp_set_transport_mode(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        return 0;
    }

    const char *mode_str = luaL_checkstring(L, 2);
    rtsp_transport_mode_t mode;

    if (strcmp(mode_str, "udp") == 0) {
        mode = RTSP_TRANSPORT_UDP;
    } else if (strcmp(mode_str, "tcp") == 0) {
        mode = RTSP_TRANSPORT_TCP;
    } else if (strcmp(mode_str, "udp_fec") == 0) {
        mode = RTSP_TRANSPORT_UDP_FEC;
    } else {
        LLOGE("无效的传输模式: %s", mode_str);
        lua_pushboolean(L, 0);
        return 1;
    }

    int ret = rtsp_set_transport_mode(ud->rtsp, mode);
    lua_pushboolean(L, ret == RTSP_OK);
    return 1;
}

/**
获取网络质量统计信息
@api rtsp:getNetworkStats()
@return table 网络统计信息，包含:
  - packet_loss_rate: 丢包率 (0.0-1.0)
  - rtt_ms: 往返延迟 (毫秒)
  - jitter_ms: 抖动 (毫秒)
  - bandwidth_kbps: 估算带宽 (Kbps)
  - rtp_packets_sent: 已发送的RTP包数
  - rtp_packets_lost: 丢失的RTP包数
  - rtp_bytes_sent: 已发送的RTP字节数
  - rtp_packets_retransmitted: 重传的RTP包数
  - rtp_nack_received: 接收到的NACK请求数
@usage
local stats = rtsp:getNetworkStats()
print("丢包率:", stats.packet_loss_rate)
print("延迟:", stats.rtt_ms)
print("重传包:", stats.rtp_packets_retransmitted)
*/
static int l_rtsp_get_network_stats(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        return 0;
    }

    rtsp_network_stats_t stats;
    if (rtsp_get_network_stats(ud->rtsp, &stats) != RTSP_OK) {
        lua_pushnil(L);
        return 1;
    }

    lua_createtable(L, 0, 9);

    lua_pushnumber(L, stats.packet_loss_rate);
    lua_setfield(L, -2, "packet_loss_rate");

    lua_pushinteger(L, stats.rtt_ms);
    lua_setfield(L, -2, "rtt_ms");

    lua_pushinteger(L, stats.jitter_ms);
    lua_setfield(L, -2, "jitter_ms");

    lua_pushinteger(L, stats.bandwidth_kbps);
    lua_setfield(L, -2, "bandwidth_kbps");

    lua_pushinteger(L, stats.rtp_packets_sent);
    lua_setfield(L, -2, "rtp_packets_sent");

    lua_pushinteger(L, stats.rtp_packets_lost);
    lua_setfield(L, -2, "rtp_packets_lost");

    lua_pushinteger(L, stats.rtp_bytes_sent);
    lua_setfield(L, -2, "rtp_bytes_sent");

    lua_pushinteger(L, stats.rtp_packets_retransmitted);
    lua_setfield(L, -2, "rtp_packets_retransmitted");

    lua_pushinteger(L, stats.rtp_nack_received);
    lua_setfield(L, -2, "rtp_nack_received");

    return 1;
}

/**
设置网络统计回调函数
@api rtsp:setNetworkStatsCallback(func)
@function func 回调函数，参数为统计信息table
@return boolean 成功返回true，失败返回false
@usage
rtsp:setNetworkStatsCallback(function(stats)
    print("丢包率:", stats.packet_loss_rate)
    print("延迟:", stats.rtt_ms)
end)
*/
static int l_rtsp_set_network_stats_callback(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        return 0;
    }

    if (lua_isnil(L, 2)) {
        // 清除回调
        rtsp_set_network_stats_callback(ud->rtsp, NULL);
        lua_pushboolean(L, 1);
        return 1;
    }

    if (!lua_isfunction(L, 2)) {
        LLOGE("网络统计回调必须是函数");
        lua_pushboolean(L, 0);
        return 1;
    }

    // TODO: 实现Lua回调的保存和调用
    // 目前暂时不支持Lua回调
    LLOGW("Lua网络统计回调暂未实现");
    lua_pushboolean(L, 0);
    return 1;
}

/**
设置FEC参数
@api rtsp:setFECParam(param, value)
@string param 参数名称: "redundancy"
@number value 参数值 (redundancy: 0-100)
@return boolean 成功返回true，失败返回false
@usage
-- 设置FEC冗余度为30%
rtsp:setFECParam("redundancy", 30)
*/

/**
销毁RTSP上下文，释放所有资源
@api rtsp:destroy()
@return nil 无返回值
@usage
rtsp:destroy()
*/
static int l_rtsp_destroy(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (!ud || !ud->rtsp) {
        return 0;
    }
    
    if (ud->callback_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, ud->callback_ref);
        ud->callback_ref = LUA_NOREF;
    }
    
    rtsp_destroy(ud->rtsp);
    ud->rtsp = NULL;
    
    LLOGD("RTSP上下文已销毁");
    return 0;
}

static int l_rtsp_gc(lua_State *L) {
    luat_rtsp_userdata_t *ud = (luat_rtsp_userdata_t *)luaL_checkudata(L, 1, "rtsp_ctx");
    if (ud && ud->rtsp) {
        if (ud->callback_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, ud->callback_ref);
        }
        rtsp_destroy(ud->rtsp);
        ud->rtsp = NULL;
    }
    return 0;
}

#include "rotable2.h"

static const rotable_Reg_t reg_rtsp_ctx[] = {
    {"setCallback",   ROREG_FUNC(l_rtsp_set_callback)},
    {"connect",       ROREG_FUNC(l_rtsp_connect)},
    {"disconnect",    ROREG_FUNC(l_rtsp_disconnect)},
    {"start",         ROREG_FUNC(l_rtsp_start)},
    {"stop",          ROREG_FUNC(l_rtsp_stop)},
    {"getState",      ROREG_FUNC(l_rtsp_get_state)},
    {"setSPS",        ROREG_FUNC(l_rtsp_set_sps)},
    {"setPPS",        ROREG_FUNC(l_rtsp_set_pps)},
    {"pushFrame",     ROREG_FUNC(l_rtsp_push_frame)},
    {"getStats",      ROREG_FUNC(l_rtsp_get_stats)},
    {"setTransportMode", ROREG_FUNC(l_rtsp_set_transport_mode)},
    {"getNetworkStats", ROREG_FUNC(l_rtsp_get_network_stats)},
    {"setNetworkStatsCallback", ROREG_FUNC(l_rtsp_set_network_stats_callback)},
    {"destroy",       ROREG_FUNC(l_rtsp_destroy)},
    {"__gc",          ROREG_FUNC(l_rtsp_gc)},
    {NULL,            ROREG_INT(0)}
};

static const rotable_Reg_t reg_rtsp[] = {
    {"create",            ROREG_FUNC(l_rtsp_create)},
    
    // RTSP状态常量
    {"STATE_IDLE",        ROREG_INT(RTSP_STATE_IDLE)},
    {"STATE_CONNECTING",  ROREG_INT(RTSP_STATE_CONNECTING)},
    {"STATE_OPTIONS",     ROREG_INT(RTSP_STATE_OPTIONS)},
    {"STATE_DESCRIBE",    ROREG_INT(RTSP_STATE_DESCRIBE)},
    {"STATE_SETUP",       ROREG_INT(RTSP_STATE_SETUP)},
    {"STATE_PLAY",        ROREG_INT(RTSP_STATE_PLAY)},
    {"STATE_PLAYING",     ROREG_INT(RTSP_STATE_PLAYING)},
    {"STATE_DISCONNECTING",ROREG_INT(RTSP_STATE_DISCONNECTING)},
    {"STATE_ERROR",       ROREG_INT(RTSP_STATE_ERROR)},
    
    // 返回值常量
    {"OK",                ROREG_INT(RTSP_OK)},
    {"ERR_FAILED",        ROREG_INT(RTSP_ERR_FAILED)},
    {"ERR_INVALID_PARAM", ROREG_INT(RTSP_ERR_INVALID_PARAM)},
    {"ERR_NO_MEMORY",     ROREG_INT(RTSP_ERR_NO_MEMORY)},
    {"ERR_CONNECT_FAILED",ROREG_INT(RTSP_ERR_CONNECT_FAILED)},
    {"ERR_HANDSHAKE_FAILED",ROREG_INT(RTSP_ERR_HANDSHAKE_FAILED)},
    {"ERR_NETWORK",       ROREG_INT(RTSP_ERR_NETWORK)},
    {"ERR_TIMEOUT",       ROREG_INT(RTSP_ERR_TIMEOUT)},
    {"ERR_BUFFER_OVERFLOW",ROREG_INT(RTSP_ERR_BUFFER_OVERFLOW)},

    // 传输模式常量
    {"TRANSPORT_UDP",     ROREG_INT(RTSP_TRANSPORT_UDP)},
    {"TRANSPORT_TCP",     ROREG_INT(RTSP_TRANSPORT_TCP)},
    {"TRANSPORT_UDP_FEC", ROREG_INT(RTSP_TRANSPORT_UDP_FEC)},

    {NULL,                ROREG_INT(0)}
};

static int _rtsp_struct_newindex(lua_State *L) {
	const rotable_Reg_t* reg = reg_rtsp_ctx;
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

LUAMOD_API int luaopen_rtsp(lua_State *L) {
    luat_newlib2(L, reg_rtsp);
    
    luaL_newmetatable(L, "rtsp_ctx");
    lua_pushcfunction(L, _rtsp_struct_newindex);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
    
    return 1;
}
