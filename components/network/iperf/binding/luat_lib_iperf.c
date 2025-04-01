/*
@module  iperf
@summary 吞吐量测试
@catalog 网络API
@version 1.0
@date    2025.02.14
@tag LUAT_USE_IPERF
@usage
-- 本库仅部分模组固件已添加
-- 当前仅支持server模式, client模式未添加
*/

#include "luat_base.h"
#include "luat_lwiperf.h"
#include "luat_network_adapter.h"
#include "luat_netdrv.h"
#include "luat_msgbus.h"
#include "lwip/ip.h"

#define LUAT_LOG_TAG "iperf"
#include "luat_log.h"

static void* iperf_session;

static int l_iperf_report_handle(lua_State*L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    uint32_t bytes_transferred, ms_duration, bandwidth;
    bytes_transferred = msg->arg1;
    ms_duration = msg->arg2;
    bandwidth = (int)ptr;
    lua_getglobal(L, "sys_pub");
    lua_pushstring(L, "IPERF_REPORT");
    lua_pushinteger(L, bytes_transferred);
    lua_pushinteger(L, ms_duration);
    lua_pushinteger(L, bandwidth);
    LLOGD("report bytes %ld ms_duration %ld bandwidth %ld kbps", bytes_transferred, ms_duration, bandwidth);
    lua_call(L, 4, 0);
    return 0;
}

static void iperf_report_cb(void *arg, enum lwiperf_report_type report_type,
    const ip_addr_t* local_addr, u16_t local_port, const ip_addr_t* remote_addr, u16_t remote_port,
    u32_t bytes_transferred, u32_t ms_duration, u32_t bandwidth_kbitpsec) {
    rtos_msg_t msg = {0};
    msg.arg1 = bytes_transferred;
    msg.arg2 = ms_duration;
    msg.ptr = (void*)bandwidth_kbitpsec;
    msg.handler = l_iperf_report_handle;
    luat_msgbus_put(&msg, 0);
}

static int start_gogogo(int adpater_id, int is_server, const ip_addr_t* remote_ip) {
    char buff[64] = {0};
    char buff2[64] = {0};
    if (adpater_id < 0 || adpater_id >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        // 必须明确指定合法的索引号
        LLOGE("非法的网络适配器索引号 %d", adpater_id);
        return 0;
    }
    // 首先, 通过netdrv获取对应的网络设备的netif
    luat_netdrv_t* drv = luat_netdrv_get(adpater_id);
    if (drv == NULL || drv->netif == NULL) {
        LLOGE("非法的网络适配器索引号 %d", adpater_id);
        return 0;
    }
    if (!netif_is_up(drv->netif) || !netif_is_link_up(drv->netif) || ip_addr_isany(&drv->netif->ip_addr)) {
        LLOGE("该网络还没就绪, 无法启动");
        return 0;
    }
    ipaddr_ntoa_r(&drv->netif->ip_addr, buff, sizeof(buff));
    if (is_server) {
        iperf_session = luat_lwiperf_start_tcp_server(&drv->netif->ip_addr, 5001, iperf_report_cb, NULL);
        LLOGD("iperf listen %s:5001", buff);
    }
    else {
        ipaddr_ntoa_r(remote_ip, buff2, sizeof(buff2));
        luat_lwiperf_start_tcp_client(remote_ip, 5001, LWIPERF_CLIENT, iperf_report_cb, NULL, &drv->netif->ip_addr);
        LLOGD("iperf connect %s --> %s:5001", buff, buff2);
    }
    return iperf_session != NULL;
}

/*
启动server模式
@api iperf.server(id)
@int 网络适配器的id, 必须填, 例如 socket.LWIP_ETH0
@return boolean 成功返回true, 失败返回false
@usage
-- 启动server模式, 监听5001端口
if iperf then
    log.info("启动iperf服务器端")
    iperf.server(socket.LWIP_ETH)
end
*/
static int l_iperf_server(lua_State *L) {
    if (iperf_session != NULL) {
        LLOGE("已经启动了server或者client,要先关掉才能启动新的");
        return 0;
    }
    int adpater_id = luaL_checkinteger(L, 1);
    if (start_gogogo(adpater_id, 1, NULL)) {
        lua_pushboolean(L, 1);
        return 1;
    }
    return 0;
}

/*
启动client模式
@api iperf.client(id)
@int 网络适配器的id, 必须填, 例如 socket.LWIP_ETH0
@string 远程服务器的ip, 只能是ipv4地址,不支持域名!!! 必须填值
@return boolean 成功返回true, 失败返回false
@usage
-- 启动client模式, 连接服务器的5001端口
if iperf then
    log.info("启动iperf客户端端")
    -- 47.94.236.172 是演示服务器, 不一定有开启
    iperf.client(socket.LWIP_ETH, "47.94.236.172")
    sys.wait(60*1000)
    -- 测试完成停掉
    iperf.abort()
end

-- 测试结果回调
sys.subscribe("IPERF_REPORT", function(bytes, ms_duration, bandwidth)
    log.info("iperf", bytes, ms_duration, bandwidth)
end)
*/
static int l_iperf_client(lua_State *L) {
    ip_addr_t remote_ip = {0};
    if (iperf_session != NULL) {
        LLOGE("已经启动了server或者client,要先关掉才能启动新的");
        return 0;
    }
    int adpater_id = luaL_checkinteger(L, 1);
    const char* ip = luaL_checkstring(L, 2);
    if (ipaddr_aton(ip, &remote_ip) == 0) {
        LLOGE("非法的ip地址 %s", ip);
        return 0;
    }
    if (start_gogogo(adpater_id, 0, &remote_ip)) {
        lua_pushboolean(L, 1);
        return 1;
    }
    return 0;
}

/*
关闭iperf
@api iperf.abort()
@return boolean 成功返回true, 失败返回false
@usage
-- 关闭已经启动的server或者client
*/
static int l_iperf_abort(lua_State *L) {
    if (iperf_session == NULL) {
        return 0;
    }
    luat_lwiperf_abort(iperf_session);
    iperf_session = NULL;
    lua_pushboolean(L, 1);
    return 1;
}


#include "rotable2.h"
static const rotable_Reg_t reg_iperf[] =
{
    { "server" ,           ROREG_FUNC(l_iperf_server)},
    { "client" ,           ROREG_FUNC(l_iperf_client)},
    { "abort" ,            ROREG_FUNC(l_iperf_abort)},
	{ NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_iperf( lua_State *L ) {
    luat_newlib2(L, reg_iperf);
    return 1;
}

