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

-- 开发中, 请关注 https://github.com/wendal/xt804-spinet
]]
*/

#include "luat_base.h"
#include "luat_ulwip.h"
#include "luat_crypto.h"
#include "luat_gpio.h"
#include "luat_spi.h"

#define LUAT_LOG_TAG "ulwip"
#include "luat_log.h"

static ulwip_ctx_t nets[USERLWIP_NET_COUNT];
extern struct netif *netif_default;

// 搜索adpater_index对应的netif
struct netif* ulwip_find_netif(uint8_t adapter_index) {
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

int ulwip_find_index(uint8_t adapter_index) {
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
    ulwip_ctx_t* ctx = (ulwip_ctx_t*)ptr;
    if (lua_isfunction(L, -1)) {
        if (msg->arg2) {
            lua_pushstring(L, "IP_READY");
            ipaddr_ntoa_r(&ctx->netif->ip_addr, buff,  32);
            LLOGD("IP_READY %d %s", ctx->adapter_index, buff);
            lua_pushstring(L, buff);
            lua_pushinteger(L, ctx->adapter_index);
            lua_call(L, 3, 0);
        }
        else {
            lua_pushstring(L, "IP_LOSE");
            LLOGD("IP_LOSE %d", ctx->adapter_index);
            lua_pushinteger(L, ctx->adapter_index);
            lua_call(L, 2, 0);
        }
    }
    return 0;
}

int ulwip_netif_ip_event(ulwip_ctx_t* ctx) {
    struct netif* netif = ctx->netif;
    int ready_now = !ip_addr_isany(&netif->ip_addr);
    ready_now &= netif_is_link_up(netif);
    ready_now &= netif_is_up(netif);

    net_lwip2_set_link_state(ctx->adapter_index, ready_now);
    if (ctx->ip_ready == ready_now) {
        return 0;
    }
    ctx->ip_ready = ready_now;
    rtos_msg_t msg = {0};
    msg.arg1 = ctx->adapter_index;
    msg.arg2 = ready_now;
    msg.ptr = ctx;
    msg.handler = netif_ip_event_cb;
    luat_msgbus_put(&msg, 0);
    return 0;
}

// 回调函数, 用于lwip的netif输出数据
int l_ulwip_netif_output_cb(lua_State *L, void* ptr) {
    // LLOGD("l_ulwip_netif_output_cb");
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    int idx = ulwip_find_index(msg->arg2);
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
                LLOGE("malloc failed for l_ulwip_netif_output_cb");
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
    msg.handler = l_ulwip_netif_output_cb;
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
-- zbuff_out 回调函数接受zbuff作为参数, 默认false
-- reverse 本地lwip设备,翻转调用逻辑, 默认false, 这个参数是为了拦截当前设备的硬件联网数据所设计的
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
    uint8_t reverse = 0;
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
        
        lua_getfield(L, 4, "reverse");
        if (lua_isinteger(L, -1)) {
            reverse = (uint8_t)luaL_checkinteger(L, -1);
        }
        if (lua_isboolean(L, -1)) {
            reverse = (uint8_t)lua_toboolean(L, -1);
        }
        lua_pop(L, 1);
    }

    struct netif *netif = NULL;
    struct netif *tmp = NULL;
    for (size_t i = 0; i < USERLWIP_NET_COUNT; i++)
    {
        if (nets[i].netif == NULL)
        {
            
            if (reverse) {
                #if defined(CHIP_EC718) || defined(CHIP_EC618) || defined(CHIP_EC716)
                extern struct netif * net_lwip_get_netif(uint8_t adapter_index);
                netif = net_lwip_get_netif(adapter_index);
                #else
                netif = netif_default;
                #endif
                if (netif == NULL) {
                    LLOGE("当前设备的netif不存在,无法启用reverse参数!!");
                    return 0;
                }
                nets[i].adapter_index = adapter_index;
                nets[i].netif = netif;
                nets[i].mtu = netif->mtu; // 其实没有意义
                nets[i].flags = netif->flags;
                nets[i].use_zbuff_out = zbuff_out;
                nets[i].reverse = reverse;
                lua_pushvalue(L, 3);
                memcpy(nets[i].hwaddr, netif->hwaddr, ETH_HWADDR_LEN);
                nets[i].output_lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
                lua_pushboolean(L, 1);
                LLOGD("挂载netif(reverse模式) %p %d %d", netif, i, adapter_index);
                return 1;
            }

            netif = luat_heap_malloc(sizeof(struct netif));
            if (netif) {
                memset(netif, 0, sizeof(struct netif));
                nets[i].adapter_index = adapter_index;
                nets[i].netif = netif;
                nets[i].mtu = mtu;
                nets[i].flags = flags;
                nets[i].use_zbuff_out = zbuff_out;
                nets[i].reverse = reverse;
                lua_pushvalue(L, 3);
                memcpy(nets[i].hwaddr, mac, ETH_HWADDR_LEN);
                nets[i].output_lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
                LLOGD("挂载netif(普通模式) %p %d %d", netif, i, adapter_index);
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
    int idx = ulwip_find_index(adapter_index);
    if (idx < 0) {
        LLOGE("没有找到netif");
        return 0;
    }
    if (lua_isboolean(L, 2)) {
        if (lua_toboolean(L, 2)) {
            netif_set_up(nets[idx].netif);
        }
        else {
            netif_set_down(nets[idx].netif);
        }
        ulwip_netif_ip_event(&nets[idx]);
    }
    lua_pushboolean(L, netif_is_up(nets[idx].netif));
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
    int idx = ulwip_find_index(adapter_index);
    if (idx < 0) {
        LLOGE("没有找到netif");
        return 0;
    }
    if (lua_isboolean(L, 2))
    {
        int new_status = lua_toboolean(L, 2);
        int old_status = netif_is_link_up(nets[idx].netif);
        if (new_status != old_status)
        {
            if (new_status) {
                netif_set_link_up(nets[idx].netif);
                if (!nets[idx].ip_static) {
                    ulwip_dhcp_client_start(&nets[idx]);
                }
            }
            else {
                netif_set_link_down(nets[idx].netif);
                ulwip_dhcp_client_stop(&nets[idx]);
            }
        }
        ulwip_netif_ip_event(&nets[idx]);
    }
    lua_pushboolean(L, netif_is_link_up(nets[idx].netif));
    return 1;
}

static void netif_input_cb(void *ptr) {
    netif_cb_ctx_t* cb_ctx = (netif_cb_ctx_t*)ptr;
    if (ERR_OK != cb_ctx->ctx->netif->input(cb_ctx->p, cb_ctx->ctx->netif)) {
        LLOGW("ctx->netif->input 失败 %d", cb_ctx->p->tot_len);
        pbuf_free(cb_ctx->p);
    }
    luat_heap_free(cb_ctx);
}

/*
往netif输入数据
@api ulwip.input(adapter_index, data, len, offset)
@int adapter_index 适配器编号
@string/userdata data 输入的数据
@int 如果data是zbuff, len默认是zbuff的used, 对string无效
@int 如果data是zbuff, offset为数据起始位置, 默认是0, 对string无效
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
    int idx = ulwip_find_index(adapter_index);
    if (idx < 0) {
        LLOGE("没有找到netif %d", adapter_index);
        return 0;
    }
    if (nets[idx].netif == NULL || nets[idx].netif->input == NULL) {
        LLOGE("该netif 不支持input操作 %d", adapter_index);
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
    ret = nets[idx].netif->input(p, nets[idx].netif);
    #else
    netif_cb_ctx_t* cb_ctx = (netif_cb_ctx_t*)luat_heap_malloc(sizeof(netif_cb_ctx_t));
    if (cb_ctx == NULL) {
        LLOGE("netif->input ret %d", ret);
        LWIP_DEBUGF(NETIF_DEBUG, ("l_ulwip_input: IP input error\n"));
        pbuf_free(p);
        return 0;
    }
    memset(cb_ctx, 0, sizeof(netif_cb_ctx_t));
    cb_ctx->ctx = &nets[idx];
    cb_ctx->p = p;
    ret = tcpip_callback(netif_input_cb, cb_ctx);
    if(ret != ERR_OK) {
        luat_heap_free(cb_ctx);
        cb_ctx = NULL;
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
    struct netif* netif = ulwip_find_netif(adapter_index);
    if (netif == NULL) {
        LLOGE("没有找到netif");
        return 0;
    }
    int dhcp_enable = lua_toboolean(L, 2);
    int i = ulwip_find_index(adapter_index);
    if (i < 0)
    {
        LLOGE("没有找到adapter_index %d", adapter_index);
        return 0;
    }
    nets[i].dhcp_enable = dhcp_enable;
    if (dhcp_enable) {
        nets[i].ip_static = 0;
        ulwip_dhcp_client_start(&nets[i]);
    }
    else {
        ulwip_dhcp_client_stop(&nets[i]);
    }
    lua_pushboolean(L, 1);
    return 1;
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
    struct netif* netif = ulwip_find_netif(adapter_index);
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
        
        int idx = ulwip_find_index(adapter_index);
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
    struct netif* netif = ulwip_find_netif(adapter_index);
    if (netif == NULL) {
        LLOGE("没有找到netif %d", adapter_index);
        return 0;
    }
    net_lwip2_register_adapter(adapter_index);
    lua_pushboolean(L, 1);
    return 1;
}

/*
操作XT804进行SPI快速收发
@api ulwip.xt804_xfer(spi_id, cs_pin, addr, zbuff, len, offset, auto_seek, auto_len)
@int spi_id SPI的ID号
@int cs_pin CS脚的GPIO号
@int addr 寄存器地址
@zbuff zbuff对象
@int len 长度
@int offset 偏移量, 默认buff:used()
@boolean auto_seek 是否自动移动偏移量, 默认false
@int auto_len 自动分片长度, 默认按寄存器自动选择
@return nil 无返回值
@usage
-- 本函数属于辅助函数
*/
static int l_ulwip_xt804_xfer(lua_State *L) {
    int spi_id = luaL_checkinteger(L, 1);  // SPI的ID号
    int cs_pin = luaL_checkinteger(L, 2);  // CS脚的GPIO号
    int addr = luaL_checkinteger(L, 3);    // 寄存器地址
    luat_zbuff_t* zbuff = ((luat_zbuff_t *)luaL_checkudata(L, 4, LUAT_ZBUFF_TYPE));
    size_t len = luaL_checkinteger(L, 5);
    size_t offset = luaL_optinteger(L, 6, zbuff->used);
    int auto_seek = lua_toboolean(L, 7);
    size_t auto_len = luaL_optinteger(L, 8, 0);
    if (auto_len == 0) {
        int tmpaddr = addr & 0x7F;
        if (tmpaddr == 0x00 || tmpaddr == 0x10 || tmpaddr == 0x01 || tmpaddr == 0x11)
            auto_len = 4;
        else
            auto_len = 2;
    }
    if (len % auto_len != 0) {
        len = (len + auto_len - 1) / auto_len * auto_len;
    }

    char tmp[5] = {0};
    tmp[0] = addr & 0xFF;
    int is_write = addr & 0x80;
    
    if (is_write) {
        for (size_t i = 0; i < len / auto_len; i++) {
            memcpy(tmp+1, zbuff->addr + offset, auto_len);
            luat_gpio_set(cs_pin, 0);
            luat_spi_send(spi_id, (const char*)tmp, auto_len + 1);
            luat_gpio_set(cs_pin, 1);
            offset += auto_len;
        }
    }
    else {
        for (size_t i = 0; i < len / auto_len; i++) {
            luat_gpio_set(cs_pin, 0);
            memcpy(tmp+1, zbuff->addr + offset, auto_len);
            luat_spi_send(spi_id, (const char*)tmp, 1);
            luat_spi_recv(spi_id, (char*)(zbuff->addr + offset), auto_len);
            luat_gpio_set(cs_pin, 1);
            offset += auto_len;
        }
    }
    if (auto_seek) {
        zbuff->used += len;
    }
    return 0;
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

    { "xt804_xfer" ,        ROREG_FUNC(l_ulwip_xt804_xfer)},

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
