/*
@module  natp
@summary 网络地址端口转换(开发中)
@version 1.0
@date    2024.4.22
@auther  wendal
@tag     LUAT_USE_NAPT
@usage
-- 开发中, 请关注 https://github.com/wendal/xt804-spinet
*/

#include "luat_base.h"
#include "luat_ulwip.h"
#include "luat_napt.h"
#include "luat_crypto.h"
#include "luat_zbuff.h"
#include "luat_network_adapter.h"

#define LUAT_LOG_TAG "napt"
#include "luat_log.h"

extern uint8_t napt_target_adapter;

/*
初始化NAPT
@api napt.init(adapter)
@int adapter 目标网卡索引, 默认是socket.LWIP_AP, 这里指内网
@return nil 无返回值
*/
static int l_napt_init(lua_State *L) {
    if (lua_isinteger(L, 1)) {
        napt_target_adapter = lua_tointeger(L, 1);
    }
    else {
        napt_target_adapter = NW_ADAPTER_INDEX_LWIP_WIFI_AP;
    }
    return 0;
}

// EC618/EC7XX的特殊逻辑
#if ENABLE_PSIF

#ifndef UINT8
#define UINT8  uint8_t
#endif
#ifndef UINT16
#define UINT16 uint16_t
#endif
#ifndef UINT32
#define UINT32 uint32_t
#endif
#ifndef BOOL
#define BOOL   uint8_t
#endif
static void toPs(void *ctx)
{
    extern BOOL PsifRawUlOutput(UINT8, UINT8 *, UINT16);

    uint8_t *pkt = (uint8_t *)((void **)ctx)[0];
    uint32_t len = (uint32_t)((void **)ctx)[1];

    uint8_t ipv = pkt[0];
    ipv = ((ipv >> 4) & 0x0F);
    UINT8 cid = ipv == 4 ? 1 : 2;

    int rc = PsifRawUlOutput(cid, pkt, len);
    if (rc) {
        LLOGE("PsifRawUlOutput rc %d", rc);
    }

    luat_heap_free(ctx);
    luat_heap_free(pkt);
}

static void sendIp2Ps(uint8_t *pkt, uint32_t len, struct netif* netif)
{
    void **param = (void **)luat_heap_malloc(sizeof(void *) * 2);
    if (param == NULL) {
        LLOGE("no mem for sendIp2Ps");
        return;
    }
    param[0] = (void *)pkt;
    param[1] = (void *)len;
    int rc = tcpip_callback(toPs, param);
    if (rc) {
        luat_heap_free(param);
        luat_heap_free(pkt);
    }
}
#endif

/*
重建MAC包
@api napt.rebuild(buff, is_inet, adapter)
@userdata 待处理的MAC包,必须是zbuff对象
@bool 来源是不是内网
@int 目标网络适配器的索引, 例如socket.LWIP_GP
@return bool 成功返回true,失败返回false
*/
static int l_napt_rebuild(lua_State *L) {
    luat_zbuff_t* zbuff = tozbuff(L);
    u8 is_inet = lua_toboolean(L, 2);
    ip_addr_t gw_ip = {0};
    struct netif* netif = NULL;
    int ip = -1;
    ip = luaL_checkinteger(L, 3);
    if (ip < 0) {
        return 0;
    }
    if (ip >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        return 0;
    }
    netif = ulwip_find_netif(ip);
    if (netif == NULL) {
        return 0;
    }
    ip_addr_set_ip4_u32(&gw_ip, ip_addr_get_ip4_u32(&netif->ip_addr));
    int dlen = zbuff->len - zbuff->used;
    uint8_t* data = (uint8_t*)zbuff->addr + zbuff->used;
    int rc = luat_napt_input(is_inet, (u8*)data, dlen, &gw_ip);
    if (!rc) {
        if (is_inet)
            memcpy(data, netif->hwaddr, 6);
        else {
            // LLOGD("赋值mac %02x:%02x:%02x:%02x:%02x:%02x", netif->hwaddr[0], netif->hwaddr[1], netif->hwaddr[2],
            // netif->hwaddr[3], netif->hwaddr[4], netif->hwaddr[5]);
            memcpy(data + 6, netif->hwaddr, 6);
        }
        #if ENABLE_PSIF
        if (ip == NW_ADAPTER_INDEX_LWIP_GPRS) {
            char* tmp = luat_heap_malloc(dlen - 14);
            if (!tmp) {
                LLOGE("no mem for sendIp2Ps");
                return 0;
            }
            memcpy(tmp, data + 14, dlen - 14);
            sendIp2Ps((uint8_t*)tmp, dlen - 14, netif);
            lua_pushboolean(L, 1);
            return 1;
        }
        #endif
        lua_pushboolean(L, 1);
        return 1;
    }
    return 0;
}

/*
检查和清理NAT表
@api napt.check()
@return nil
@usage
-- 需要周期性调用, 30秒一次
*/
static int l_napt_check(lua_State *L) {
    luat_napt_table_check(NULL);
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_napt[] =
{
    { "init" ,              ROREG_FUNC(l_napt_init)},
    { "rebuild",            ROREG_FUNC(l_napt_rebuild)},
    { "check",              ROREG_FUNC(l_napt_check)},
	{ NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_napt( lua_State *L ) {
    luat_napt_init();
    luat_newlib2(L, reg_napt);
    return 1;
}
