/*
@module  icmp
@summary ICMP协议(PING)
@version 1.0
@date    2024.010.15
@demo    icmp
@tag LUAT_USE_NETWORK
@usage
-- 等网络就绪后, 初始化icmp库
icmp.setup(socket.LWIP_GP)
-- 执行ping,等待回应
icmp.ping(socket.LWIP_GP, "183.2.172.177")
-- 等待结果
sys.waitUnitl("PING_RESULT", 3000)
-- 详细用法请看demo
*/


#include "luat_base.h"
#include "luat_icmp.h"
#include "luat_network_adapter.h"
#include "luat_msgbus.h"

#include "lwip/ip_addr.h"

#include "rotable2.h"

#define LUAT_LOG_TAG "icmp"
#include "luat_log.h"

typedef struct ping_result
{
    uint8_t adapter_id;
    uint32_t addr;
    uint32_t t_used;
}ping_result_t;


static int l_icmp_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    uint32_t addr = msg->arg2;
    char buff[32] = {0};
    ip_addr_t ip = {0};
    ip_addr_set_ip4_u32(&ip, addr);
    ipaddr_ntoa_r(&ip, buff, 32);
    if (lua_isfunction(L, -1)) {
        lua_pushstring(L, "PING_RESULT");
        lua_pushinteger(L, (msg->arg1 >> 16) & 0xFFFF);
        lua_pushinteger(L, (msg->arg1 >> 0) & 0xFFFF);
        lua_pushstring(L, buff);
        lua_call(L, 4, 0);
    }
    return 0;
}

static void l_icmp_cb(void* _ctx, uint32_t tused) {
    if (_ctx == NULL) {
        return;
    }
    luat_icmp_ctx_t* ctx = (luat_icmp_ctx_t*)_ctx;
    rtos_msg_t msg = {
        .handler = l_icmp_handler,
        .arg1 = ctx->adapter_id << 16 | (tused & 0xFFFF),
        .arg2 = ip_addr_get_ip4_u32(&ctx->dst)
    };
    luat_msgbus_put(&msg, 0);
}

/*
初始化指定网络设备的icmp
@api icmp.setup(id)
@int 网络适配器的id
@return bool 成功与否
@usage
-- 初始化4G网络的icmp, 要等4G联网后才能调用
icmp.setup(socket.LWIP_GP)
*/
static int l_icmp_setup(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    luat_icmp_ctx_t* ctx = luat_icmp_init(id);
    if (ctx != NULL) {
        ctx->cb = l_icmp_cb;
    }
    lua_pushboolean(L, ctx != NULL);
    return 1;
}

/*
发起ping(异步的)
@api icmp.ping(id, ip, len)
@int 网络适配器的id
@string 目标ip地址,不支持域名!!
@int ping包大小,默认128字节,可以不传
@return bool 成功与否, 仅代表发送与否,不代表服务器已经响应
@usage
sys.taskInit(function()
    sys.waitUntil("IP_READY")
    sys.wait(1000)
    icmp.setup(socket.LWIP_GP)
    while 1 do
        icmp.ping(socket.LWIP_GP, "121.14.77.221")
        sys.waitUntil("PING_RESULT", 3000)
        sys.wait(3000)
    end
end)

sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", id, time, dst);
end)
*/
static int l_icmp_ping(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    luat_icmp_ctx_t* ctx = luat_icmp_get(id);
    if (ctx == NULL) {
        ctx = luat_icmp_init(id);
        if (ctx == NULL) {
            LLOGW("icmp初始化失败");
            return 0;
        }
    }
    const char* ip = luaL_checkstring(L, 2);
    size_t len = luaL_optinteger(L, 3, 128);
    ip_addr_t addr = {0};
    if (0 == ipaddr_aton(ip, &addr)) {
        LLOGW("目标地址非法 %s", ip);
        return 0;
    };
    int result = luat_icmp_ping(ctx, &addr, len);
    lua_pushinteger(L, result == 0);
    return 1;
}

static int l_icmp_debug(lua_State *L) {
    extern uint8_t g_icmp_debug;
    g_icmp_debug = lua_toboolean(L, 1);
    lua_pushboolean(L, g_icmp_debug);
    return 1;
}

static const rotable_Reg_t reg_icmp[] =
{
    { "setup" ,           ROREG_FUNC(l_icmp_setup)},
    { "ping" ,            ROREG_FUNC(l_icmp_ping)},
    { "debug" ,           ROREG_FUNC(l_icmp_debug)},
    // { "close" ,           ROREG_FUNC(l_icmp_close)},
	{ NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_icmp( lua_State *L ) {
    luat_newlib2(L, reg_icmp);
    return 1;
}
