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
#include "luat_ulwip.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "ulwip"
#include "luat_log.h"

static ulwip_ctx_t nets[USERLWIP_NET_COUNT];

static void dhcp_client_cb(void *arg);
static err_t ulwip_etharp_output(struct netif *netif, struct pbuf *q, const ip4_addr_t *ipaddr);
static void ulwip_dhcp_recv(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port);
static int l_dhcp_client_cb(lua_State *L, void* ptr);

// 搜索adpater_index对应的netif
static struct netif* find_netif(uint8_t adapter_index) {
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

static int find_index(uint8_t adapter_index) {
    for (size_t i = 0; i < USERLWIP_NET_COUNT; i++)
    {
        if (nets[i].adapter_index == adapter_index)
        {
            return i;
        }
    }
    return -1;
}

static int netif_ip_event_cb(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    char buff[32] = {0};
    if (lua_isfunction(L, -1)) {
        if (msg->arg2) {
            lua_pushstring(L, "IP_READY");
            ipaddr_ntoa_r(&nets[msg->arg1].netif->ip_addr, buff,  32);
            LLOGD("IP_READY %d %s", nets[msg->arg1].adapter_index, buff);
            lua_pushstring(L, buff);
            lua_pushinteger(L, nets[msg->arg1].adapter_index);
            lua_call(L, 3, 0);
        }
        else {
            lua_pushstring(L, "IP_LOSE");
            LLOGD("IP_LOSE %d", nets[msg->arg1].adapter_index);
            lua_pushinteger(L, nets[msg->arg1].adapter_index);
            lua_call(L, 2, 0);
        }
    }
    return 0;
}

static int ulwip_netif_ip_event(int8_t adapter_index) {
    int idx = find_index(adapter_index);
    if (idx < 0) {
        return -1;
    }
    struct netif* netif = nets[idx].netif;
    int ready_now = !ip_addr_isany(&netif->ip_addr);
    ready_now &= netif_is_link_up(netif);
    ready_now &= netif_is_up(netif);

    net_lwip2_set_link_state(nets[idx].adapter_index, ready_now);
    if (nets[idx].ip_ready == ready_now) {
        return 0;
    }
    nets[idx].ip_ready = ready_now;
    rtos_msg_t msg = {0};
    msg.arg1 = idx;
    msg.arg2 = ready_now;
    msg.handler = netif_ip_event_cb;
    luat_msgbus_put(&msg, 0);
    return 0;
}

// 回调函数, 用于lwip的netif输出数据
static int netif_output_cb(lua_State *L, void* ptr) {
    // LLOGD("netif_output_cb");
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    int idx = find_index(msg->arg2);
    if (idx < 0 || nets[idx].netif == NULL) {
        LLOGE("非法的适配器索引号 %d", msg->arg2);
        return 0;
    }
    lua_geti(L, LUA_REGISTRYINDEX, nets[idx].output_lua_ref);
    if (lua_isfunction(L, -1)) {
        lua_pushinteger(L, msg->arg2);
        if (nets[idx].use_zbuff_out) {
            luat_zbuff_t* buff = lua_newuserdata(L, sizeof(luat_zbuff_t));
            if (buff == NULL)
            {
                LLOGE("malloc failed for netif_output_cb");
                return 0;
            }
            memset(buff, 0, sizeof(luat_zbuff_t));
            buff->addr = ptr;
            buff->len = msg->arg1;
            buff->used = msg->arg1;
            luaL_setmetatable(L, LUAT_ZBUFF_TYPE);
        }
        else {
            lua_pushlstring(L, (const char*)ptr, msg->arg1);
            luat_heap_free(ptr);
        }
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
            msg.arg2 = nets[i].adapter_index;
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

static err_t luat_netif_init(struct netif *netif) {
    for (size_t i = 0; i < USERLWIP_NET_COUNT; i++)
    {
    if (nets[i].netif == netif)
        {
            LLOGD("netif init %d %p", nets[i].adapter_index, netif);

            netif->linkoutput = netif_output;
            netif->output     = ulwip_etharp_output;
            #if LWIP_IPV6
            netif->output_ip6 = ethip6_output;
            #endif
            netif->mtu        = nets[i].mtu;
            netif->flags      = nets[i].flags;
            memcpy(netif->hwaddr, nets[i].hwaddr, ETH_HWADDR_LEN);
            netif->hwaddr_len = ETH_HWADDR_LEN;
            return 0;
        }
    }
    return ERR_IF;
}

/*
初始化lwip netif
@api ulwip.setup(adapter_index, mac, output_lua_ref, opts)
@int adapter_index 适配器编号
@string mac 网卡mac地址
@function output_lua_ref 回调函数, 参数为(adapter_index, data)
@table 额外参数, 例如 {mtu=1500, flags=(ulwip.FLAG_BROADCAST | ulwip.FLAG_ETHARP)}
@return boolean 成功与否
@usage
-- 初始化一个适配器, 并设置回调函数
ulwip.setup(socket.LWIP_STA, string.fromHex("18fe34a27b69"), function(adapter_index, data)
    log.info("ulwip", "output_lua_ref", adapter_index, data:toHex())
end)
-- 注意, setup之后, netif的状态是down, 调用ulwip.updown(adapter_index, true)后, 才能正常收发数据

-- 额外参数配置table可选值
-- mtu, 默认1460
-- flags, 默认 ulwip.FLAG_BROADCAST | ulwip.FLAG_ETHARP | ulwip.FLAG_ETHERNET | ulwip.FLAG_IGMP | ulwip.FLAG_MLD6
-- 即如下格式 {mtu=1460, flags=(ulwip.FLAG_BROADCAST | ulwip.FLAG_ETHARP | ulwip.FLAG_ETHERNET | ulwip.FLAG_IGMP | ulwip.FLAG_MLD6)}
*/
static int l_ulwip_setup(lua_State *L) {
    // 必须有适配器编号
    uint8_t adapter_index = (uint8_t)luaL_checkinteger(L, 1);
    // 设置MAC地址,必须的
    const char* mac = luaL_checkstring(L, 2);
    if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY)
    {
        LLOGE("非法的adapter_index %d", adapter_index);
        return 0;
    }
    if (!lua_isfunction(L, 3)) {
        LLOGE("output_lua_ref must be a function");
        return 0;
    }
    uint16_t mtu = 1460;
    uint8_t flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP | NETIF_FLAG_ETHERNET | NETIF_FLAG_IGMP | NETIF_FLAG_MLD6;
    uint16_t zbuff_out = 0;
    if (lua_istable(L, 4)) {
        lua_getfield(L, 4, "mtu");
        if (lua_isinteger(L, -1)) {
            mtu = (uint16_t)luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);
        
        lua_getfield(L, 4, "flags");
        if (lua_isinteger(L, -1)) {
            flags = (uint8_t)luaL_checkinteger(L, -1);
        }
        lua_pop(L, 1);

        lua_getfield(L, 4, "zbuff_out");
        if (lua_isboolean(L, -1)) {
            zbuff_out = lua_toboolean(L, -1);
            if (zbuff_out) {
                LLOGD("使用zbuff作为netif out的回调函数");
            }
        }
        lua_pop(L, 1);
    }
    struct netif *netif = NULL;
    struct netif *tmp = NULL;
    for (size_t i = 0; i < USERLWIP_NET_COUNT; i++)
    {
        if (nets[i].netif == NULL)
        {
            netif = luat_heap_malloc(sizeof(struct netif));
            if (netif) {
                memset(netif, 0, sizeof(struct netif));
                nets[i].adapter_index = adapter_index;
                nets[i].netif = netif;
                nets[i].mtu = mtu;
                nets[i].flags = flags;
                nets[i].use_zbuff_out = zbuff_out;
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
    tmp = netif_add(netif, IP4_ADDR_ANY4, IP4_ADDR_ANY4, IP4_ADDR_ANY4, NULL, luat_netif_init, netif_input);
    netif->name[0] = 'u';
    netif->name[1] = 's';
    if (NULL == tmp) {
        LLOGE("netif_add 返回异常!!!");
    }
    #if LWIP_IPV6
    netif_create_ip6_linklocal_address(netif, 1);
    netif->ip6_autoconfig_enabled = 1;
    #endif

    net_lwip2_set_netif(adapter_index, netif);
    
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
    uint8_t adapter_index = (uint8_t)luaL_checkinteger(L, 1);
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
        ulwip_netif_ip_event(adapter_index);
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
static int l_ulwip_link(lua_State *L) {
    // 必须有适配器编号
    uint8_t adapter_index = (uint8_t)luaL_checkinteger(L, 1);
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
        ulwip_netif_ip_event(adapter_index);
    }
    lua_pushboolean(L, netif_is_link_up(netif));
    return 1;
}

static void netif_input_cb(void *ptr) {
    netif_cb_ctx_t* ctx = (netif_cb_ctx_t*)ptr;
    if (ERR_OK != ctx->netif->input(ctx->p, ctx->netif)) {
        LLOGW("ctx->netif->input 失败 %d", ctx->p->tot_len);
        pbuf_free(ctx->p);
    }
    luat_heap_free(ctx);
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
    uint8_t adapter_index = (uint8_t)luaL_checkinteger(L, 1);
    int ret = 0;
    struct pbuf *q = NULL;
    const char* data = NULL;
    size_t len = 0;
    size_t offset = 0;
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
        luat_zbuff_t* zb = (luat_zbuff_t*)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE);
        data = (const char*)zb->addr;
        if (lua_isinteger(L, 3)) {
            len = luaL_checkinteger(L, 3);
            offset = luaL_checkinteger(L, 4);
            data += offset;
        }
        else {
            len = zb->used;
        }
    }
    else {
        LLOGE("未知的数据格式, 当前仅支持zbuff和string");
        return 0;
    }
    // LLOGD("输入的mac帧 %d %02X:%02X:%02X:%02X:%02X:%02X", len, data[0], data[1], data[2], data[3], data[4], data[5]);
    struct pbuf *p = pbuf_alloc(PBUF_RAW, (uint16_t)len, PBUF_RAM);
    if (p == NULL) {
        LLOGE("pbuf_alloc failed");
        return 0;
    }
    for (q = p; q != NULL; q = q->next) {
        memcpy(q->payload, data, q->len);
        data += q->len;
    }
    #if NO_SYS
    ret = netif->input(p, netif);
    #else
    netif_cb_ctx_t* ctx = (netif_cb_ctx_t*)luat_heap_malloc(sizeof(netif_cb_ctx_t));
    if (ctx == NULL) {
        LLOGE("netif->input ret %d", ret);
        LWIP_DEBUGF(NETIF_DEBUG, ("l_ulwip_input: IP input error\n"));
        pbuf_free(p);
        return 0;
    }
    memset(ctx, 0, sizeof(netif_cb_ctx_t));
    ctx->netif = netif;
    ctx->p = p;
    ret = tcpip_callback(netif_input_cb, ctx);
    if(ret != ERR_OK) {
        luat_heap_free(ctx);
    }
    #endif
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
    uint8_t adapter_index = (uint8_t)luaL_checkinteger(L, 1);
    struct netif* netif = find_netif(adapter_index);
    if (netif == NULL) {
        LLOGE("没有找到netif");
        return 0;
    }
    int dhcp_enable = lua_toboolean(L, 2);
    #if 0
    if (dhcp_enable)
    {
        dhcp_start(netif);
    }
    else {
        dhcp_stop(netif);
    }
    lua_pushboolean(L, 1);
    return 1;
    #else
    int i = find_index(adapter_index);
    if (i < 0)
    {
        LLOGE("没有找到adapter_index %d", adapter_index);
        return 0;
    }
    if (dhcp_enable && nets[i].dhcp_client == NULL) {
        nets[i].dhcp_client = luat_heap_malloc(sizeof(dhcp_client_info_t));
        memset(nets[i].dhcp_client, 0, sizeof(dhcp_client_info_t));
        memcpy(nets[i].dhcp_client->mac, netif->hwaddr, 6);
        luat_crypto_trng((char*)&nets[i].dhcp_client->xid, sizeof(nets[i].dhcp_client->xid));
        sprintf_(nets[i].dhcp_client->name, "airm2m-%02x%02x%02x%02x%02x%02x",
			nets[i].dhcp_client->mac[0],nets[i].dhcp_client->mac[1], nets[i].dhcp_client->mac[2],
			nets[i].dhcp_client->mac[3],nets[i].dhcp_client->mac[4], nets[i].dhcp_client->mac[5]);
        luat_rtos_timer_create(&nets[i].dhcp_timer);
        nets[i].dhcp_pcb = udp_new();
        ip_set_option(nets[i].dhcp_pcb, SOF_BROADCAST);
        udp_bind(nets[i].dhcp_pcb, IP4_ADDR_ANY, 68);
        udp_connect(nets[i].dhcp_pcb, IP4_ADDR_ANY, 67);
        udp_recv(nets[i].dhcp_pcb, ulwip_dhcp_recv, (void*)i);
    }
    if (nets[i].dhcp_timer != NULL)
    {
        if (dhcp_enable)
        {
            nets[i].ip_static = 0;
            ip_addr_set_any(0, &nets[i].netif->ip_addr);
            if (!luat_rtos_timer_is_active(nets[i].dhcp_timer))
            {
                nets[i].dhcp_client->state = DHCP_STATE_DISCOVER;
                nets[i].dhcp_client->discover_cnt = 0;
                luat_rtos_timer_start(nets[i].dhcp_timer, 1000, 1, dhcp_client_cb, (void*)i);
                dhcp_client_cb((void*)i);
            }
        }
        else {
            if (luat_rtos_timer_is_active(nets[i].dhcp_timer)) {
                luat_rtos_timer_stop(nets[i].dhcp_timer);
            }
        }
        lua_pushboolean(L, 1);
        return 1;
    }
    return 0;
    #endif
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
    uint8_t adapter_index = (uint8_t)luaL_checkinteger(L, 1);
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
        tmp = luaL_checkstring(L, 4);
        ipaddr_aton(tmp, &netif->gw);
        
        int idx = find_index(adapter_index);
        nets[idx].ip_static = !ip_addr_isany(&netif->ip_addr);
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
    uint8_t adapter_index = (uint8_t)luaL_checkinteger(L, 1);
    struct netif* netif = find_netif(adapter_index);
    if (netif == NULL) {
        LLOGE("没有找到netif %d", adapter_index);
        return 0;
    }
    net_lwip2_register_adapter(adapter_index);
    lua_pushboolean(L, 1);
    return 1;
}

/*
设置默认netif网卡
@api ulwip.dft(adapter_index)
@int/boolean adapter_index 适配器编号或还原默认网卡
@return boolean 成功与否
@usage
-- 将默认网卡设置为socket.LWIP_ETH
ulwip.dft(socket.LWIP_ETH)
-- 还原默认网卡
ulwip.dft(true)
*/
static struct netif* prev_netif;
extern struct netif *netif_default;
static int l_ulwip_dft(lua_State *L) {
    // 必须有适配器编号
    if (lua_type(L, 1) == LUA_TNUMBER)
    {
        uint8_t adapter_index = (uint8_t)luaL_checkinteger(L, 1);
        struct netif* netif = find_netif(adapter_index);
        if (netif == NULL) {
            LLOGE("没有找到netif %d", adapter_index);
            return 0;
        }
        if (prev_netif == NULL && netif_default != NULL) {
            LLOGD("保存系统默认网卡 %.2s %p", netif_default->name, netif_default);
            prev_netif = netif_default;
        }
        LLOGD("设置默认网卡 %.2s %p", netif->name, netif);
        netif_set_default(netif);
    }
    else if (lua_type(L, 1) == LUA_TBOOLEAN) {
        if (lua_toboolean(L, 1) && prev_netif != NULL) {
            LLOGD("还原系统默认网卡 %.2s %p", prev_netif->name, prev_netif);
            netif_set_default(prev_netif);
        }
        else {
            LLOGE("没有找到系统默认网卡");
        }
    }
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
    { "dft" ,               ROREG_FUNC(l_ulwip_dft)},

    // 网卡FLAGS,默认
    // NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP | NETIF_FLAG_ETHERNET | NETIF_FLAG_IGMP | NETIF_FLAG_MLD6

    // @const FLAG_BROADCAST number 支持广播
    { "FLAG_BROADCAST",     ROREG_INT(NETIF_FLAG_BROADCAST)}, 
    // @const FLAG_ETHARP number 支持ARP
    { "FLAG_ETHARP",        ROREG_INT(NETIF_FLAG_ETHARP)}, 
    // @const FLAG_ETHERNET number 以太网模式
    { "FLAG_ETHERNET",      ROREG_INT(NETIF_FLAG_ETHERNET)}, 
    // @const FLAG_IGMP number 支持IGMP
    { "FLAG_IGMP",          ROREG_INT(NETIF_FLAG_IGMP)}, 
    // @const FLAG_MLD6 number 支持_MLD6
    { "FLAG_MLD6",          ROREG_INT(NETIF_FLAG_MLD6)}, 
	{ NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_ulwip( lua_State *L ) {
    luat_newlib2(L, reg_ulwip);
    return 1;
}

// -------------------------------------
//           DHCP 相关的逻辑
// -------------------------------------


// timer回调, 或者是直接被调用, arg是nets的索引号
static void dhcp_client_cb(void *arg) {
    int i = (int)arg;
    // 简单防御一下
    if (i < 0 || i >= USERLWIP_NET_COUNT) {
        return;
    }
    if (nets[i].netif == NULL || nets[i].dhcp_client == NULL) {
        return;
    }
    // 压入lua线程进行处理
    rtos_msg_t msg = {
        .handler = l_dhcp_client_cb,
        .arg1 = i
    };
    luat_msgbus_put(&msg, 0);
}

static int dhcp_task_run(int idx, char* rxbuff, size_t len) {
    PV_Union uIP;
    // 检查dhcp的状态
    dhcp_client_info_t* dhcp = nets[idx].dhcp_client;
    struct netif* netif = nets[idx].netif;

    Buffer_Struct rx_msg_buf = {0,0,0};
    Buffer_Struct tx_msg_buf = {0,0,0};
	uint32_t remote_ip = 0;
    int result = 0;

    if (rxbuff) {
        rx_msg_buf.Data = (uint8_t*)rxbuff;
        rx_msg_buf.Pos = len;
        rx_msg_buf.MaxLen = len;
    }

    // 看看是不是获取成功了
    if (DHCP_STATE_CHECK == dhcp->state) {
        uIP.u32 = dhcp->ip;
		LLOGD("动态IP:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		uIP.u32 = dhcp->submask;
		LLOGD("子网掩码:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		uIP.u32 = dhcp->gateway;
		LLOGD("网关:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		LLOGD("租约时间:%u秒", dhcp->lease_time);

        // 设置到netif
        ip_addr_set_ip4_u32(&netif->ip_addr, dhcp->ip);
        ip_addr_set_ip4_u32(&netif->netmask, dhcp->submask);
        ip_addr_set_ip4_u32(&netif->gw,      dhcp->gateway);
        dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
        if (rxbuff) {
            luat_heap_free(rxbuff);
        }
        ulwip_netif_ip_event(nets[idx].adapter_index);
        return 0;
    }
    result = ip4_dhcp_run(dhcp, rxbuff == NULL ? NULL : &rx_msg_buf, &tx_msg_buf, &remote_ip);
    if (rxbuff) {
        luat_heap_free(rxbuff);
    }
    if (result) {
        LLOGE("ip4_dhcp_run error %d", result);
        return 0;
    }
    if (!tx_msg_buf.Pos) {
        return 0; // 没有数据需要发送
    }
    // 通过UDP发出来
    struct pbuf *p;
    struct pbuf *q;
    // LLOGD("待发送DHCP包长度 %d 前4个字节分别是 %02X%02X%02X%02X", tx_msg_buf.Pos, 
    //     tx_msg_buf.Data[0], tx_msg_buf.Data[1], tx_msg_buf.Data[2], tx_msg_buf.Data[3]);
    p = pbuf_alloc(PBUF_TRANSPORT, tx_msg_buf.Pos, PBUF_RAM);
    char* data = (char*)tx_msg_buf.Data;
    for (q = p; q != NULL; q = q->next) {
        memcpy(q->payload, data, q->len);
        data += q->len;
    }
    data = p->payload;
    // LLOGI("dhcp payload len %d %02X%02X%02X%02X", p->tot_len, data[0], data[1], data[2], data[3]);
    udp_sendto_if(nets[idx].dhcp_pcb, p, IP_ADDR_BROADCAST, 67, netif);
    pbuf_free(p);
    return 0;
}

static int l_dhcp_client_cb(lua_State *L, void* ptr) {
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    int idx = msg->arg1;
    dhcp_task_run(idx, ptr, msg->arg2);
    return 0;
}

static void ulwip_dhcp_recv(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port) {
    LLOGD("收到DHCP数据包(len=%d)", p->tot_len);
    int idx = (int)arg;
    char* ptr = luat_heap_malloc(p->tot_len);
    if (!ptr) {
        return;
    }
    rtos_msg_t msg = {
        .ptr = ptr,
        .handler = l_dhcp_client_cb,
    };
    msg.arg1 = idx;
    msg.arg2 = p->tot_len;
    size_t offset = 0;
    do {
        memcpy((char*)msg.ptr + offset, p->payload, p->len);
        offset += p->len;
        p = p->next;
    } while (p);
    luat_msgbus_put(&msg, 0);
    LLOGD("传递DHCP数据包");
    return;
}

// ARP 修正

static err_t ulwip_etharp_output(struct netif *netif, struct pbuf *q, const ip4_addr_t *ipaddr) {
  const struct eth_addr *dest;
  struct eth_addr mcastaddr;
  const ip4_addr_t *dst_addr = ipaddr;

  /* Determine on destination hardware address. Broadcasts and multicasts
   * are special, other IP addresses are looked up in the ARP table. */

  /* broadcast destination IP address? */
  if (ip4_addr_isbroadcast(ipaddr, netif)) {
    /* broadcast on Ethernet also */
    dest = (const struct eth_addr *)&ethbroadcast;
  /* multicast destination IP address? */
  } else if (ip4_addr_ismulticast(ipaddr)) {
    /* Hash IP multicast address to MAC address.*/
    mcastaddr.addr[0] = LL_IP4_MULTICAST_ADDR_0;
    mcastaddr.addr[1] = LL_IP4_MULTICAST_ADDR_1;
    mcastaddr.addr[2] = LL_IP4_MULTICAST_ADDR_2;
    mcastaddr.addr[3] = ip4_addr2(ipaddr) & 0x7f;
    mcastaddr.addr[4] = ip4_addr3(ipaddr);
    mcastaddr.addr[5] = ip4_addr4(ipaddr);
    /* destination Ethernet address is multicast */
    dest = &mcastaddr;
  /* unicast destination IP address? */
  } else {
    // s8_t i;
#if 1
    /* outside local network? if so, this can neither be a global broadcast nor
       a subnet broadcast. */
    if (!ip4_addr_netcmp(ipaddr, netif_ip4_addr(netif), netif_ip4_netmask(netif)) &&
        !ip4_addr_islinklocal(ipaddr)) {
#if LWIP_AUTOIP
      struct ip_hdr *iphdr = LWIP_ALIGNMENT_CAST(struct ip_hdr*, q->payload);
      /* According to RFC 3297, chapter 2.6.2 (Forwarding Rules), a packet with
         a link-local source address must always be "directly to its destination
         on the same physical link. The host MUST NOT send the packet to any
         router for forwarding". */
      if (!ip4_addr_islinklocal(&iphdr->src))
#endif /* LWIP_AUTOIP */
      {
#ifdef LWIP_HOOK_ETHARP_GET_GW
        /* For advanced routing, a single default gateway might not be enough, so get
           the IP address of the gateway to handle the current destination address. */
        dst_addr = LWIP_HOOK_ETHARP_GET_GW(netif, ipaddr);
        if (dst_addr == NULL)
#endif /* LWIP_HOOK_ETHARP_GET_GW */
        {
          /* interface has default gateway? */
          if (!ip4_addr_isany_val(*netif_ip4_gw(netif))) {
            /* send to hardware address of default gateway IP address */
            dst_addr = netif_ip4_gw(netif);
          /* no default gateway available */
          } else {
            /* no route to destination error (default gateway missing) */
            return ERR_RTE;
          }
        }
      }
    }
#endif

    /* no stable entry found, use the (slower) query function:
       queue on destination Ethernet address belonging to ipaddr */
    return etharp_query(netif, dst_addr, q);
  }

  /* continuation for multicast/broadcast destinations */
  /* obtain source Ethernet address of the given interface */
  /* send packet directly on the link */
  return ethernet_output(netif, q, (struct eth_addr*)(netif->hwaddr), dest, ETHTYPE_IP);
}
