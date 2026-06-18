/*
 * luat_lib_netdrv_event.c - netdrv 事件 Lua 绑定
 *
 * 从 luat_lib_netdrv.c 拆分出来,目的仅仅是文件级拆分(luat_lib_netdrv.c 太大).
 * 不导出为独立 Lua 模块,只有一个对外符号 `l_netdrv_on`,被 luat_lib_netdrv.c
 * 的 reg_netdrv[] 通过 extern 引用.
 */

#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_rtos.h"
#include "luat_zbuff.h"
#include "luat_netdrv.h"
#include "luat_netdrv_napt.h"
#include "luat_netdrv_drv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_event.h"

#include "lwip/ip.h"
#include "lwip/ip4.h"
#include "lwip/tcpip.h"

#define LUAT_LOG_TAG "netdrv.event"
#include "luat_log.h"

static int s_socket_evt_ref[NW_ADAPTER_QTY] = {0};
static int s_pkg_evt_ref[NW_ADAPTER_QTY] = {0};

static int l_socket_evt_cb(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    netdrv_tcp_evt_t* evt = (netdrv_tcp_evt_t*)ptr;
    int ref = s_socket_evt_ref[evt->id];
    if (ref == 0) {
        LLOGW("socket evt cb no lua ref");
        luat_heap_free(ptr);
        return 0;
    }
    // LLOGD("socket evt cb %d %d lua function %d", evt->id, evt->flags, ref);
    // 取出函数
    lua_geti(L, LUA_REGISTRYINDEX, ref);
    if (!lua_isfunction(L, -1)) {
        LLOGW("socket evt cb ref not function");
        lua_pop(L, 1);
        luat_heap_free(ptr);
        return 0;
    }
    lua_pushinteger(L, evt->id);
    switch (evt->flags)
    {
    case 0x81:
        lua_pushstring(L, "create");
        break;
    case 0x82:
        lua_pushstring(L, "release");
        break;
    case 0x83:
        lua_pushstring(L, "connecting");
        break;
    case EV_NW_TIMEOUT - EV_NW_RESET:
        lua_pushstring(L, "timeout");
        break;
    case EV_NW_SOCKET_CLOSE_OK - EV_NW_RESET:
        lua_pushstring(L, "closed");
        break;
    case EV_NW_SOCKET_CONNECT_OK - EV_NW_RESET:
        lua_pushstring(L, "connected");
        break;
    case EV_NW_SOCKET_REMOTE_CLOSE - EV_NW_RESET:
        lua_pushstring(L, "remote_close");
        break;
    case EV_NW_SOCKET_ERROR - EV_NW_RESET:
        lua_pushstring(L, "error");
        break;
    case EV_NW_DNS_RESULT - EV_NW_RESET:
        lua_pushstring(L, "dns_result");
        break;

    default:
        lua_pushstring(L, "unknown");
        break;
    }
    lua_newtable(L);
    // 填充参数表 远端ip, 远端端口, 本地ip, 本地端口
    char buff[32] = {0};
    if (!ip_addr_isany(&evt->remote_ip)) {
        ipaddr_ntoa_r(&evt->remote_ip, buff, 32);
        lua_pushstring(L, buff);
        lua_setfield(L, -2, "remote_ip");
    }

    if (!ip_addr_isany(&evt->online_ip)) {
        ipaddr_ntoa_r(&evt->online_ip, buff, 32);
        lua_pushstring(L, buff);
        lua_setfield(L, -2, "online_ip");
    }

    lua_pushinteger(L, evt->remote_port);
    lua_setfield(L, -2, "remote_port");

    switch (evt->proto)
    {
    case 1:
        lua_pushstring(L, "tcp");
        break;
    case 2:
        lua_pushstring(L, "udp");
        break;
    case 3:
        lua_pushstring(L, "http");
        break;
    case 4:
        lua_pushstring(L, "mqtt");
        break;
    case 5:
        lua_pushstring(L, "websocket");
        break;
    default:
        lua_pushstring(L, "unknown");
        break;
    }
    lua_setfield(L, -2, "proto");

    // p = ipaddr_ntoa_r(&evt->local_ip, buff, 32);
    // lua_pushstring(L, p);
    // lua_setfield(L, -2, "local_ip");

    // lua_pushinteger(L, evt->local_port);
    // lua_setfield(L, -2, "local_port");

    if (evt->domain_name[0]) {
        lua_pushstring(L, evt->domain_name);
        lua_setfield(L, -2, "domain_name");
    }

    lua_call(L, 3, 0);
    // 释放内存
    luat_heap_free(ptr);

    return 0;
}

static void luat_socket_evt_cb(netdrv_tcp_evt_t* evt, void* userdata) {
    rtos_msg_t msg = {0};
    msg.handler = l_socket_evt_cb;
    msg.ptr = luat_heap_malloc(sizeof(netdrv_tcp_evt_t));
    if (msg.ptr == NULL) {
        LLOGE("socket evt cb no mem");
        return;
    }
    memcpy(msg.ptr, evt, sizeof(netdrv_tcp_evt_t));
    luat_msgbus_put(&msg, 0);
}

// 监听socket事件
// EVT_PKG: 数据包事件 C 入口 + Lua 派发
typedef struct pkg_evt_msg {
    uint8_t  id;
    uint8_t  event;
    uint16_t len;
    uint8_t  buff[4];
} pkg_evt_msg_t;

// tcpip/ch390h 线程 -> Lua 主线程
static int l_pkg_evt_cb(lua_State *L, void* ptr);

// C 回调入口: fire 路径最终走到这里
static void luat_pkg_evt_cb(luat_netdrv_pkg_evt_t* evt, void* userdata) {
    (void)userdata;
    if (!evt || !evt->buff || evt->len == 0) return;
    pkg_evt_msg_t* m = (pkg_evt_msg_t*)luat_heap_malloc(sizeof(pkg_evt_msg_t) + evt->len - 4);
    if (!m) return;
    m->id    = evt->id;
    m->event = evt->event;
    m->len   = evt->len;
    memcpy(m->buff, evt->buff, evt->len);
    rtos_msg_t msg = {0};
    msg.handler = l_pkg_evt_cb;
    msg.ptr = m;
    luat_msgbus_put(&msg, 0);
}

static int l_pkg_evt_cb(lua_State *L, void* ptr) {
    if (L == NULL || ptr == NULL) return 0;
    pkg_evt_msg_t* m = (pkg_evt_msg_t*)ptr;
    int ref = s_pkg_evt_ref[m->id];
    if (ref == 0) { luat_heap_free(m); return 0; }
    lua_geti(L, LUA_REGISTRYINDEX, ref);
    if (!lua_isfunction(L, -1)) { lua_pop(L, 1); luat_heap_free(m); return 0; }
    lua_pushinteger(L, m->id);
    lua_pushinteger(L, m->event);
    // arg3: zbuff userdata (PSRAM 分配, GC 时由 zbuff __gc 自动按 type 释放)
    luat_zbuff_t* z = (luat_zbuff_t*)lua_newuserdata(L, sizeof(luat_zbuff_t));
    luaL_setmetatable(L, LUAT_ZBUFF_TYPE);
    memset(z, 0, sizeof(luat_zbuff_t));
    z->type = LUAT_HEAP_PSRAM;
    z->len  = m->len;
    z->used = m->len;
    if (m->len > 0) {
        z->addr = (uint8_t*)luat_heap_opt_malloc(LUAT_HEAP_PSRAM, m->len);
        if (z->addr) {
            memcpy(z->addr, m->buff, m->len);
        } else {
            z->len = 0;
            z->used = 0;
        }
    }
    // 修正: 改用 lua_pcall, 用户回调内任意 error() 都会 longjmp 跳过
    // luat_heap_free(m) 造成 m 泄漏. pcall 形式无论成功失败都走同一释放路径.
    if (lua_pcall(L, 3, 0, 0) != LUA_OK) {
        // 错误信息留在栈顶, 让 msgbus 调度器取走记日志或上行抛出
        LLOGW("netdrv EVT_PKG callback error: %s", lua_tostring(L, -1));
        lua_pop(L, 1);
    }
    luat_heap_free(m);
    return 0;
}

/*
订阅网络事件
@api netdrv.on(adapter_id, event_type, callback, opts)
@int 网络适配器的id
@int 事件总类型, 支持 netdrv.EVT_SOCKET (旧) / netdrv.EVT_PKG (数据包)
@function 回调函数, EVT_SOCKET 时为 function(id, event, params),EVT_PKG 时为 function(id, layer, zbuff)
@table opts 可选, 仅 EVT_PKG 时使用. layer = "hw"/"lwip"/"napt" 或 netdrv.CH_HW/CH_LWIP/CH_NAPT 整数, 缺省 "hw"
@return bool 成功与否,成功返回true,否则返回nil
@usage
-- 1) 订阅socket连接状态变化事件 (旧用法, 无 opts)
netdrv.on(socket.LWIP_ETH, netdrv.EVT_SOCKET, function(id, event, params)
    -- id / event / params 含义见 socket 事件文档
    log.info("netdrv", "socket event", id, event)
end)

-- 2) 订阅数据包事件 (HW 通道, 旧用法, 默认 layer="hw")
-- Lua 仅观察, 不阻断 NAPT 后续流程 (包照常进入 LWIP/NAPT)
netdrv.on(socket.LWIP_ETH, netdrv.EVT_PKG, function(id, layer, zb)
    log.info("netdrv", "rx hw", layer, zb:used())
end)

-- 3) 拦截 LWIP 层出向包 (新功能, layer="lwip")
-- 注册即拦截: LWIP 出口的原 TX 包不再走 dataout, 直接丢弃.
-- Lua 拿到的 zbuff 是只读副本, 实际 TX 完全由 Lua 决定:
--   - 不做任何事 = 吞掉该包 (drop)
--   - 调 netdrv.send_raw(CH_HW, ...)   = 通过 HW 通道发出 (走 dataout)
--   - 调 netdrv.send_raw(CH_LWIP, ...) = 作为入向包注入 LWIP (模拟网络响应)
--   - 调 netdrv.send_raw(CH_NAPT, ...) = 走 NAPT 转发
local intercepted_count = 0
netdrv.on(socket.LWIP_ETH, netdrv.EVT_PKG, function(id, layer, zb)
    if layer == netdrv.CH_LWIP then
        intercepted_count = intercepted_count + 1
        log.info("netdrv", "intercepted lwip tx", zb:used())
        -- 例: 完全丢弃 (默认行为), 或注入自己的应答
        -- local fake = zbuff.create(64, 0)
        -- ... 填充 fake ...
        -- netdrv.send_raw(id, netdrv.CH_LWIP, fake)  -- 把 fake 作为入向包塞回 LWIP
    end
end, { layer = "lwip" })
*/
// 注意: 本函数被 luat_lib_netdrv.c 的 reg_netdrv[] 通过 extern 引用,
// 严禁改为 static, 否则编译期 rotable 条目会 unresolved.
//
// opts 参数 (可选, table 形式, 当前支持 EVT_PKG 订阅时使用):
//   layer = "hw" | "lwip" | "napt" | netdrv.CH_HW/CH_LWIP/CH_NAPT 整数
//         指定数据包事件订阅的 layer. 不传时默认 "hw" (兼容旧 API).
//         声明 layer="lwip" 后, 该 id 的 LWIP TX 出口会被用户脚本接管,
//         原 dataout 流程被跳过 (注册即拦截, 无 sync consume 模式).
int l_netdrv_on(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    if (id < 0) {
        return 0; // 非法id
    }
    // 防御: id 必须落在 [0, NW_ADAPTER_QTY) 区间, 否则下面 s_pkg_evt_ref[id]
    // 与 s_socket_evt_ref[id] 会越界访问. 早期 netdrv_get 守卫被 event_id
    // 检查前置后必须补回此守卫.
    if (id >= NW_ADAPTER_QTY) {
        LLOGW("netdrv.on id %d 越界 (>= %d)", id, NW_ADAPTER_QTY);
        return 0;
    }
    int event_id = luaL_checkinteger(L, 2);
    // EVT_PKG (event_id == 2) 走专属分支, 即便 netdrv/netif 不可用也允许幂等关闭
    if (event_id == 2) {
        // nil 关闭 -> 幂等 true
        if (lua_isnil(L, 3)) {
            if (s_pkg_evt_ref[id]) {
                luaL_unref(L, LUA_REGISTRYINDEX, s_pkg_evt_ref[id]);
                s_pkg_evt_ref[id] = 0;
            }
            luat_netdrv_register_pkg_event_cb(id, NULL, NULL);
            lua_pushboolean(L, 1);
            return 1;
        }
        // 非函数参数 -> 拒绝
        if (!lua_isfunction(L, 3)) {
            lua_pushnil(L);
            return 1;
        }
        // 解析 opts.layer (table 第 4 个参数, 可选)
        // 默认订阅 HW 通道, 保持旧 API 行为兼容.
        uint8_t layer_mask = LUAT_NETDRV_CH_HW;
        if (lua_istable(L, 4)) {
            if (lua_getfield(L, 4, "layer") != LUA_TNIL) {
                if (lua_type(L, -1) == LUA_TNUMBER) {
                    int v = lua_tointeger(L, -1);
                    if (v == LUAT_NETDRV_CH_HW || v == LUAT_NETDRV_CH_LWIP || v == LUAT_NETDRV_CH_NAPT) {
                        layer_mask = (uint8_t)v;
                    } else {
                        LLOGW("netdrv.on opts.layer 数值非法 %d, 忽略", v);
                    }
                } else if (lua_type(L, -1) == LUA_TSTRING) {
                    const char* s = lua_tostring(L, -1);
                    if (s) {
                        if (strcmp(s, "hw") == 0)        layer_mask = LUAT_NETDRV_CH_HW;
                        else if (strcmp(s, "lwip") == 0) layer_mask = LUAT_NETDRV_CH_LWIP;
                        else if (strcmp(s, "napt") == 0) layer_mask = LUAT_NETDRV_CH_NAPT;
                        else LLOGW("netdrv.on opts.layer 字符串非法 %s, 忽略", s);
                    }
                }
            }
            lua_pop(L, 1);
        }
        // 注册前确认 netif 可用
        luat_netdrv_t* nd = luat_netdrv_get(id);
        if (nd == NULL || nd->netif == NULL) {
            LLOGW("netdrv %d 无 netif, 无法注册 EVT_PKG", id);
            lua_pushnil(L);
            return 1;
        }
        lua_pushvalue(L, 3);
        int ref = luaL_ref(L, LUA_REGISTRYINDEX);
        if (s_pkg_evt_ref[id]) {
            luaL_unref(L, LUA_REGISTRYINDEX, s_pkg_evt_ref[id]);
        }
        s_pkg_evt_ref[id] = ref;
        luat_netdrv_register_pkg_event_cb(id, luat_pkg_evt_cb, NULL);
        luat_netdrv_set_pkg_layer(id, layer_mask);
        lua_pushboolean(L, 1);
        return 1;
    }
    luat_netdrv_t* netdrv = luat_netdrv_get(id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        return 0;
    }
    if (event_id == 0) {
        if (s_socket_evt_ref[id]) {
            luaL_unref(L, LUA_REGISTRYINDEX, s_socket_evt_ref[id]);
            s_socket_evt_ref[id] = 0;
        }
        luat_netdrv_register_socket_event_cb(id, 0, NULL, NULL);
        lua_pushboolean(L, 1);
        return 1;
    }
    else if (event_id == 1) {
        if (!lua_isfunction(L, 3)) {
            return 0;
        }
        lua_pushvalue(L, 3);
        s_socket_evt_ref[id] = luaL_ref(L, LUA_REGISTRYINDEX);
        // LLOGD("register socket event cb %d", s_socket_evt_ref[id]);
        luat_netdrv_register_socket_event_cb(id, 0xFF, luat_socket_evt_cb, NULL);
        lua_pushboolean(L, 1);
        return 1;
    }
    LLOGW("not support event type %d", event_id);
    return 0;
}
