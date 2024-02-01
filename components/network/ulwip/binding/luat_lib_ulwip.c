/*
@module  ulwip
@summary 用户空间的lwip集成(开发中)
@version 1.0
@date    2024.1.22
@auther  wendal
@tag     LUAT_USE_ULWIP
@usage
--[[
注意: 本库处于开发中, 接口随时可能变化
用户空间的LWIP集成, 用于支持lwip的netif的网络集成, 实现在lua代码中直接控制MAC包/IP包的收发

总体数据路径如下

lua代码 -> ulwip.input -> lwip(netif->input) -> lwip处理逻辑 -> luatos socket框架

lua代码 <- ulwip回调函数 <- lwip(netif->low_level_output) <- lwip处理逻辑 <- luatos socket框架

应用示例:
1. Air601的wifi模块作为被控端, 通过UART/SPI收发MAC包, 实现Air780E/Air780EP集成wifi模块的功能
2. 使用W5500/CH395/ENC28J60等以太网模块, 在用户lua代码中控制其mac包收发, 并集成到luatos socket框架中
3. 通过蓝牙模块,集成lowpan6
]]
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_mem.h"
#include "luat_zbuff.h"

#include "lwip/opt.h"
#include "lwip/debug.h"
#include "lwip/stats.h"
#include "lwip/netif.h"
#include "lwip/etharp.h"
#include "lwip/dhcp.h"
#include "lwip/ethip6.h"

// #include "net_lwip.h"
#include "net_lwip2.h"

#include "luat_network_adapter.h"

#define LUAT_LOG_TAG "ulwip"
#include "luat_log.h"

#define USERLWIP_NET_COUNT NW_ADAPTER_INDEX_LWIP_NETIF_QTY

void net_lwip2_set_link_state(uint8_t adapter_index, uint8_t updown);

typedef struct ulwip_ctx
{
    int adapter_index;
    int output_lua_ref;
    struct netif *netif;
    uint16_t mtu;
    uint16_t flags;
    uint8_t hwaddr[ETH_HWADDR_LEN];
}ulwip_ctx_t;

static ulwip_ctx_t nets[USERLWIP_NET_COUNT];

// 搜索adpater_index对应的netif
static struct netif* find_netif(int adapter_index) {
    struct netif *netif = NULL;
    for (size_t i = 0; i < USERLWIP_NET_COUNT; i++)
    {
        if (nets[i].adapter_index == adapter_index)
        {
            netif = nets[i].netif;
            break;
        }
    }
    return netif;
}

// 回调函数, 用于lwip的netif输出数据
static int netif_output_cb(lua_State *L, void* ptr) {
    // LLOGD("netif_output_cb");
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_geti(L, LUA_REGISTRYINDEX, nets[msg->arg2].output_lua_ref);
    if (lua_isfunction(L, -1)) {
        lua_pushinteger(L, msg->arg2);
        // TODO ? 改成zbuff?
        lua_pushlstring(L, ptr, msg->arg1);
        luat_heap_free(ptr);
        lua_call(L, 2, 0);
    }
    else {
        // LLOGD("不是回调函数 %d", nets[msg->arg2].output_lua_ref);
        luat_heap_free(ptr);
    }
    return 0;
}

static err_t netif_output(struct netif *netif, struct pbuf *p) {
    // LLOGD("lwip待发送数据 %p %d", p, p->tot_len);
    rtos_msg_t msg = {0};
    msg.handler = netif_output_cb;
    msg.arg1 = p->tot_len;
    msg.arg2 = -1;
    for (size_t i = 0; i < USERLWIP_NET_COUNT; i++)
    {
        if (nets[i].netif == netif)
        {
            msg.arg2 = i;
            break;
        }
    }
    if (msg.arg2 < 0) {
        LLOGE("netif_output %p not found", netif);
        return ERR_IF;
    }
    msg.ptr = luat_heap_malloc(p->tot_len);
    if (msg.ptr == NULL)
    {
        LLOGE("malloc %d failed for netif_output", p->tot_len);
        return ERR_MEM;
    }
    
    size_t offset = 0;
    do {
        memcpy((char*)msg.ptr + offset, p->payload, p->len);
        offset += p->len;
        p = p->next;
    } while (p);
    luat_msgbus_put(&msg, 0);
    return 0;
}

#if LWIP_NETIF_STATUS_CALLBACK
static void netif_status_callback(struct netif *netif)
{
    LLOGD("netif status changed %s", ip4addr_ntoa(netif_ip4_addr(netif)));
    for (size_t i = 0; i < USERLWIP_NET_COUNT; i++)
    {
        if (nets[i].netif == netif)
        {
            if (!ip_addr_isany(&netif->ip_addr)) {
                LLOGD("设置网络状态为UP %d", i);
                net_lwip2_set_link_state(nets[i].adapter_index, 1);
            }
            else {
                LLOGD("设置网络状态为DOWN %d", i);
                net_lwip2_set_link_state(nets[i].adapter_index, 0);
            }
            break;
        }
    }
  
}
#endif

static err_t luat_netif_init(struct netif *netif) {
    for (size_t i = 0; i < USERLWIP_NET_COUNT; i++)
    {
        if (nets[i].netif == netif)
        {
            LLOGD("netif init %d %p", i, netif);
            
            netif->linkoutput = netif_output;
            netif->output     = etharp_output;
            #if LWIP_IPV6
            netif->output_ip6 = ethip6_output;
            #endif
            netif->mtu        = 1460; // TODO 支持配置
            netif->flags      = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP | NETIF_FLAG_ETHERNET | NETIF_FLAG_IGMP | NETIF_FLAG_MLD6;
            memcpy(netif->hwaddr, nets[i].hwaddr, ETH_HWADDR_LEN);
            netif->hwaddr_len = ETH_HWADDR_LEN;
            return 0;
        }
    }
    return ERR_IF;
}

/*
初始化lwip netif
@api ulwip.setup(adapter_index, mac, output_lua_ref)
@int adapter_index 适配器编号
@string mac 网卡mac地址
@function output_lua_ref 回调函数, 参数为(adapter_index, data)
@return boolean 成功与否
@usage
-- 初始化一个适配器, 并设置回调函数
ulwip.setup(socket.LWIP_STA, string.fromHex("18fe34a27b69"), function(adapter_index, data)
    log.info("ulwip", "output_lua_ref", adapter_index, data:toHex())
end)
-- 注意, setup之后, netif的状态是down, 调用ulwip.updown(adapter_index, true)后, 才能正常收发数据
*/
static int l_ulwip_setup(lua_State *L) {
    // 必须有适配器编号
    int adapter_index = luaL_checkinteger(L, 1);
    // 设置MAC地址,必须的
    const char* mac = luaL_checkstring(L, 2);
    if (adapter_index < 0 || adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY)
    {
        LLOGE("非法的adapter_index %d", adapter_index);
        return 0;
    }
    if (!lua_isfunction(L, 3)) {
        LLOGE("output_lua_ref must be a function");
        return 0;
    }
    struct netif *netif = NULL;
    for (size_t i = 0; i < USERLWIP_NET_COUNT; i++)
    {
        if (nets[i].netif == NULL)
        {
            netif = luat_heap_malloc(sizeof(struct netif));
            if (netif) {
                memset(netif, 0, sizeof(struct netif));
                nets[i].adapter_index = adapter_index;
                nets[i].netif = netif;
                lua_pushvalue(L, 3);
                memcpy(nets[i].hwaddr, mac, ETH_HWADDR_LEN);
                nets[i].output_lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
                break;
            }
        }
    }
    if (netif == NULL)
    {
        LLOGE("没有空余的netif了");
        return 0;
    }

    // 已经分配netif, 继续初始化
    #if defined(TYPE_EC718P)
    net_lwip2_set_netif(adapter_index, netif, luat_netif_init, 0);
    #else
    netif_add(netif, IP4_ADDR_ANY, IP4_ADDR_ANY, IP4_ADDR_ANY, NULL, luat_netif_init, netif_input);
    netif->name[0] = 'u';
    netif->name[1] = 's';
    #if LWIP_IPV6
    netif_create_ip6_linklocal_address(netif, 1);
    netif->ip6_autoconfig_enabled = 1;
    #endif

    #endif

    #if LWIP_NETIF_STATUS_CALLBACK
    netif_set_status_callback(netif, netif_status_callback);
    #endif

    #if defined(TYPE_EC718P)
    // nothing
    #else
    net_lwip2_set_netif(adapter_index, netif);
    #endif
    
    lua_pushboolean(L, 1);
    return 1;
}

/*
设置netif的状态
@api ulwip.updown(adapter_index, up)
@int adapter_index 适配器编号
@boolean up true为up, false为down
@return boolean 成功与否
@usage
-- 参考ulwip.setup
*/
static int l_ulwip_updown(lua_State *L) {
    // 必须有适配器编号
    int adapter_index = luaL_checkinteger(L, 1);
    struct netif* netif = find_netif(adapter_index);
    if (netif == NULL) {
        LLOGE("没有找到netif");
        return 0;
    }
    if (lua_isboolean(L, 2)) {
        if (lua_toboolean(L, 2)) {
            netif_set_up(netif);
        }
        else {
            netif_set_down(netif);
        }
    }
    lua_pushboolean(L, netif_is_up(netif));
    return 1;
}

/*
设置netif的物理链路状态
@api ulwip.link(adapter_index, up)
@int adapter_index 适配器编号
@boolean up true为up, false为down
@return boolean 当前状态
@usage
-- 参考ulwip.setup
*/
static int l_ulwip_link(lua_State *L) {// 必须有适配器编号
    int adapter_index = luaL_checkinteger(L, 1);
    struct netif* netif = find_netif(adapter_index);
    if (netif == NULL) {
        LLOGE("没有找到netif");
        return 0;
    }
    if (lua_isboolean(L, 2))
    {
        if (lua_toboolean(L, 2))
        {
            netif_set_link_up(netif);
        }
        else {
            netif_set_link_down(netif);
        }
    }
    lua_pushboolean(L, netif_is_link_up(netif));
    return 1;
}

/*
往netif输入数据
@api ulwip.input(adapter_index, data)
@int adapter_index 适配器编号
@string data 输入的数据
@return boolean 成功与否
@usage
-- 参考ulwip.setup
*/
static int l_ulwip_input(lua_State *L) {
    // 必须有适配器编号
    int adapter_index = luaL_checkinteger(L, 1);
    int ret = 0;
    struct pbuf *q = NULL;
    const char* data = NULL;
    size_t len = 0;
    struct netif* netif = find_netif(adapter_index);
    if (netif == NULL) {
        LLOGE("没有找到netif %d", adapter_index);
        return 0;
    }
    if (lua_type(L, 2) == LUA_TSTRING)
    {
        data = luaL_checklstring(L, 2, &len);
    }
    else if (lua_type(L, 2) == LUA_TUSERDATA) {
        luat_zbuff_t* zb = (luat_zbuff_t*)luaL_checkudata(L, 2, "zbuff");
        data = (const char*)zb->addr;
        len = zb->used;
    }
    else {
        LLOGE("未知的数据格式, 当前仅支持zbuff和string");
        return 0;
    }
    struct pbuf *p = pbuf_alloc(PBUF_RAW, len, PBUF_POOL);
    if (p == NULL) {
        LLOGE("pbuf_alloc failed");
        return 0;
    }
    for (q = p; q != NULL; q = q->next) {
        memcpy(q->payload, data, q->len);
        data += q->len;
    }
    ret = netif->input(p, netif);
    if(ret != ERR_OK) {
        LLOGE("netif->input ret %d", ret);
        LWIP_DEBUGF(NETIF_DEBUG, ("l_ulwip_input: IP input error\n"));
        pbuf_free(p);
        return 0;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/*
启动或关闭dhcp
@api ulwip.dhcp(adapter_index, up)
@int adapter_index 适配器编号
@boolean up true为启动, false为关闭
@return boolean 当前状态
@usage
-- 参考ulwip.setup
*/
static int l_ulwip_dhcp(lua_State *L) {
    // 必须有适配器编号
    int adapter_index = luaL_checkinteger(L, 1);
    struct netif* netif = find_netif(adapter_index);
    if (netif == NULL) {
        LLOGE("没有找到netif");
        return 0;
    }
    #if LWIP_DHCP
    if (lua_type(L, 2) == LUA_TBOOLEAN)
    {
        if (lua_toboolean(L, 2))
        {
            dhcp_start(netif);
        }
        else {
            dhcp_stop(netif);
        }
        lua_pushboolean(L, 1);
        return 1;
    }
    #endif
    return 0;
}

/*
设置或获取ip信息
@api ulwip.ip(adapter_index, ip, netmask, gw)
@int adapter_index 适配器编号
@string ip IP地址, 仅获取时可以不填
@string netmask 子网掩码, 仅获取时可以不填
@string gw 网关地址, 仅获取时可以不填
@return string ip地址, 子网掩码, 网关地址
@usage
-- 获取现有值
local ip, netmask, gw = ulwip.ip(socket.LWIP_STA)
-- 设置新值
ulwip.ip(socket.LWIP_STA, "192.168.0.1", "255.255.255.0", "192.168.0.1")
*/
static int l_ulwip_ip(lua_State *L) {
    const char* tmp = NULL;
    // 必须有适配器编号
    int adapter_index = luaL_checkinteger(L, 1);
    struct netif* netif = find_netif(adapter_index);
    if (netif == NULL) {
        LLOGE("没有找到netif %d", adapter_index);
        return 0;
    }
    if (lua_type(L, 2) == LUA_TSTRING)
    {
        tmp = luaL_checkstring(L, 2);
        ipaddr_aton(tmp, &netif->ip_addr);
        tmp = luaL_checkstring(L, 3);
        ipaddr_aton(tmp, &netif->netmask);
        tmp = luaL_checkstring(L, 2);
        ipaddr_aton(tmp, &netif->gw);
    }
    // 反馈IP信息
    tmp = ip_ntoa(&netif->ip_addr);
    lua_pushstring(L, tmp);
    tmp = ip_ntoa(&netif->netmask);
    lua_pushstring(L, tmp);
    tmp = ip_ntoa(&netif->gw);
    lua_pushstring(L, tmp);
    return 3;
}

// void net_lwip2_register_adapter(uint8_t adapter_index);
// void net_lwip2_set_netif(uint8_t adapter_index, struct netif *netif);
/*
将netif注册到luatos socket中
@api ulwip.reg(adapter_index)
@int adapter_index 适配器编号
@return boolean 成功与否
@usage
-- 参考ulwip.setup
*/
static int l_ulwip_reg(lua_State *L) {
    // 必须有适配器编号
    int adapter_index = luaL_checkinteger(L, 1);
    struct netif* netif = find_netif(adapter_index);
    if (netif == NULL) {
        LLOGE("没有找到netif %d", adapter_index);
        return 0;
    }
    net_lwip2_register_adapter(adapter_index);
    lua_pushboolean(L, 1);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_ulwip[] =
{
    { "input" ,             ROREG_FUNC(l_ulwip_input)},
    { "setup" ,             ROREG_FUNC(l_ulwip_setup)},
    { "updown" ,            ROREG_FUNC(l_ulwip_updown)},
    { "link" ,              ROREG_FUNC(l_ulwip_link)},
    { "dhcp" ,              ROREG_FUNC(l_ulwip_dhcp)},
    { "ip" ,                ROREG_FUNC(l_ulwip_ip)},
    { "reg" ,               ROREG_FUNC(l_ulwip_reg)},
	{ NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_ulwip( lua_State *L ) {
    luat_newlib2(L, reg_ulwip);
    return 1;
}

