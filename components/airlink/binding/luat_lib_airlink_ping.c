/*
@module  airlink
@summary AirLink 异步ping绑定
@catalog 外设API
@version 1.0
@date    2025.05.30
@tag LUAT_USE_AIRLINK
*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_airlink.h"
#include "luat_airlink_ping.h"
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

typedef struct {
    uint64_t pkgid;
    uint64_t rtt_ms;
    uint8_t  ok;
    int      error_code;
    uint16_t echo_len;
    uint8_t  echo_buf[AIRLINK_PING_ECHO_MAX];
} ping_result_msg_t;

typedef struct {
    uint8_t  mode;
    uint64_t pkgid;
    uint32_t timeout_ms;
    uint16_t payload_len;
    uint8_t  payload[0]; // flexible array member
} ping_worker_args_t;

static int ping_result_cb(lua_State *L, void *ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    ping_result_msg_t* result = (ping_result_msg_t*)msg->ptr;

    lua_getglobal(L, "sys_pub");
    lua_pushstring(L, "AIRLINK_PING_RESULT");
    lua_pushinteger(L, (lua_Integer)result->pkgid);
    lua_pushboolean(L, result->ok ? 1 : 0);
    if (result->ok) {
        lua_pushinteger(L, (lua_Integer)result->rtt_ms);
        lua_pushlstring(L, (const char*)result->echo_buf, result->echo_len);
    } else {
        if (result->error_code == -1) {
            lua_pushstring(L, "timeout");
        } else {
            lua_pushinteger(L, result->error_code);
        }
        lua_pushnil(L);
    }
    lua_call(L, 5, 0);

    luat_heap_free(result);
    return 0;
}

static void ping_worker_task(void* param) {
    ping_worker_args_t* args = (ping_worker_args_t*)param;
    luat_rtos_task_handle self = luat_rtos_get_current_handle();

    ping_result_msg_t* result = (ping_result_msg_t*)luat_heap_malloc(sizeof(ping_result_msg_t));
    if (!result) {
        LLOGE("ping worker: malloc result failed");
        luat_heap_free(args);
        luat_rtos_task_delete(self);
        return;
    }
    memset(result, 0, sizeof(ping_result_msg_t));
    result->pkgid = args->pkgid;

    uint64_t rtt_ms   = 0;
    uint16_t echo_len = 0;
    int ret = luat_airlink_ping_raw(
        args->mode, args->pkgid,
        args->payload, args->payload_len,
        args->timeout_ms,
        &rtt_ms,
        result->echo_buf, AIRLINK_PING_ECHO_MAX,
        &echo_len);
    luat_heap_free(args);

    if (ret == 0) {
        result->ok       = 1;
        result->rtt_ms   = rtt_ms;
        result->echo_len = echo_len;
    } else {
        result->ok         = 0;
        result->error_code = ret;
    }

    rtos_msg_t msg = {0};
    msg.handler = ping_result_cb;
    msg.ptr     = result;
    luat_msgbus_put(&msg, 0);
    luat_rtos_task_delete(self);
}

/*
发起异步 ping, 结果通过 sys.subscribe("AIRLINK_PING_RESULT", ...) 接收
@api airlink.ping(data, timeout_ms)
@string/zbuff data 要回显的payload, 可为空字符串
@int timeout_ms 超时毫秒数, 默认3000
@return int request_id, 成功发起时返回pkgid; 失败返回nil
@usage
local reqid = airlink.ping("hello", 3000)
sys.subscribe("AIRLINK_PING_RESULT", function(id, ok, v1, v2)
    if id ~= reqid then return end
    if ok then
        log.info("ping", "rtt=" .. v1 .. "ms echo=" .. v2)
    else
        log.info("ping", "failed: " .. tostring(v1))
    end
end)
*/
int l_airlink_ping(lua_State *L) {
    const char* data     = NULL;
    size_t      data_len = 0;

    int t = lua_type(L, 1);
    if (t == LUA_TSTRING) {
        data = lua_tolstring(L, 1, &data_len);
    } else if (t == LUA_TUSERDATA) {
        luat_zbuff_t* buff = (luat_zbuff_t*)luaL_checkudata(L, 1, LUAT_ZBUFF_TYPE);
        data     = (const char*)buff->addr;
        data_len = buff->used;
    }
    // nil/none → empty payload

    if (data_len > AIRLINK_PING_ECHO_MAX) {
        LLOGE("ping: payload too large %zu (max %d)", data_len, AIRLINK_PING_ECHO_MAX);
        lua_pushnil(L);
        return 1;
    }

    uint32_t timeout_ms = (uint32_t)luaL_optinteger(L, 2, 3000);
    uint64_t pkgid      = luat_airlink_get_next_cmd_id();

    size_t args_size = sizeof(ping_worker_args_t) + data_len;
    ping_worker_args_t* args = (ping_worker_args_t*)luat_heap_malloc(args_size);
    if (!args) {
        LLOGE("ping: malloc args failed");
        lua_pushnil(L);
        return 1;
    }
    memset(args, 0, sizeof(ping_worker_args_t));
    int current_mode = luat_airlink_current_mode_get();
    args->mode        = (current_mode >= 0) ? (uint8_t)current_mode : LUAT_AIRLINK_MODE_LOOPBACK;
    args->pkgid       = pkgid;
    args->timeout_ms  = timeout_ms;
    args->payload_len = (uint16_t)data_len;
    if (data && data_len > 0) {
        memcpy(args->payload, data, data_len);
    }

    luat_rtos_task_handle task_handle = NULL;
    int ret = luat_rtos_task_create(&task_handle, 4 * 1024, 30,
                                    "airlink_ping", ping_worker_task, args, 0);
    if (ret != 0) {
        LLOGE("ping: task create failed %d", ret);
        luat_heap_free(args);
        lua_pushnil(L);
        return 1;
    }

    lua_pushinteger(L, (lua_Integer)pkgid);
    return 1;
}
