/*
@module  w5500
@summary w5500以太网驱动
@version 1.0
@date    2022.04.11
@tag LUAT_USE_W5500
*/

#include "luat_base.h"
#ifdef LUAT_USE_W5500
#include "luat_rtos.h"
#include "luat_zbuff.h"
#include "luat_spi.h"
#define LUAT_LOG_TAG "w5500"
#include "luat_log.h"
#include "luat_msgbus.h"

#include "w5500_def.h"
#include "luat_network_adapter.h"
/*
初始化w5500
@api w5500.init(spiid, speed, cs_pin, irq_pin, rst_pin, link_pin)
@int spi通道号, 例如 0, 1, 5, 按设备实际情况选
@int spi速度, 可以设置到对应SPI的最高速度
@int cs pin, 片选脚, 对应W5500的SCS
@int irq pin, 中断脚, 对应W5500的INT
@int reset pin, 复位脚, 对应W5500的RST
@int link 状态 pin，可以留空不使用，默认不使用
@usage
w5500.init(spi.SPI_0, 24000000, pin.PB13, pin.PC08, pin.PC09)
*/
static int l_w5500_init(lua_State *L){
	luat_spi_t spi = {0};
	spi.id = luaL_checkinteger(L, 1);
	spi.bandrate = luaL_checkinteger(L, 2);
	spi.cs = luaL_checkinteger(L, 3);
	spi.CPHA = 0;
	spi.CPOL = 0;
	spi.master = 1;
	spi.mode = 1;
	spi.dataw = 8;
	spi.bit_dict = 1;
	uint32_t irq_pin = luaL_checkinteger(L, 4);
	uint32_t reset_pin = luaL_checkinteger(L, 5);
	uint32_t link_pin = luaL_optinteger(L, 6, 0xff);
	w5500_init(&spi, irq_pin, reset_pin, link_pin);
	return 0;
}

/*
w5500配置网络信息
@api w5500.config(ip, submask, gateway, mac, RTR, RCR, speed)
@string 静态ip地址，如果需要用DHCP获取，请写nil
@string 子网掩码，如果使用动态ip，则忽略
@string 网关，如果使用动态ip，则忽略
@string MAC，写nil则通过MCU唯一码自动生成，如果要写，长度必须是6byte
@int 重试间隔时间，默认2000，单位100us，不懂的不要改
@int 最大重试次数，默认8，不懂的不要改
@int 速度类型，目前只有0硬件配置，1自适应，默认为0
@usage
w5500.config("192.168.1.2", "255.255.255.0", "192.168.1.1", string.fromHex("102a3b4c5d6e"))
*/
static int l_w5500_config(lua_State *L){
	if (!w5500_device_ready())
	{
		lua_pushboolean(L, 0);
		LLOGD("device no ready");
		return 1;
	}

	if (lua_isstring(L, 1))
	{
	    size_t ip_len = 0;
	    const char* ip = luaL_checklstring(L, 1, &ip_len);
	    size_t mask_len = 0;
	    const char* mask = luaL_checklstring(L, 2, &mask_len);
	    size_t gateway_len = 0;
	    const char* gateway = luaL_checklstring(L, 3, &gateway_len);
#ifdef LUAT_USE_LWIP
	    ip_addr_t lwip_ip,lwip_mask,lwip_gateway;
	    ipaddr_aton(ip, &lwip_ip);
	    ipaddr_aton(mask, &lwip_mask);
	    ipaddr_aton(gateway, &lwip_gateway);
	    w5500_set_static_ip(ip_addr_get_ip4_u32(&lwip_ip), ip_addr_get_ip4_u32(&lwip_mask), ip_addr_get_ip4_u32(&lwip_gateway));
#else
	    w5500_set_static_ip(network_string_to_ipv4(ip, ip_len), network_string_to_ipv4(mask, mask_len), network_string_to_ipv4(gateway, gateway_len));
#endif
	}
	else
	{
		w5500_set_static_ip(0, 0, 0);
	}

	if (lua_isstring(L, 4))
	{
		size_t mac_len = 0;
		const char *mac = luaL_checklstring(L, 4, &mac_len);
		w5500_set_mac((uint8_t*)mac);
	}

	w5500_set_param(luaL_optinteger(L, 5, 2000), luaL_optinteger(L, 6, 8), luaL_optinteger(L, 7, 0), 0);


	w5500_reset();
	lua_pushboolean(L, 1);
	return 1;
}
/*
将w5500注册进通用网络接口
@api w5500.bind(id)
@int 通用网络通道号
@usage
-- 若使用的版本不带socket库, 改成 network.ETH0
w5500.bind(socket.ETH0)
*/
static int l_w5500_network_register(lua_State *L){

	int index = luaL_checkinteger(L, 1);
	w5500_register_adapter(index);
	return 0;
}

/*
获取w5500当前的MAC，必须在init之后用，如果config中设置了自己的MAC，需要延迟一点时间再读
@api w5500.getMac()
@return string 当前的MAC
@usage
local mac = w5500.getMac()
log.info("w5500 mac", mac:toHex())
*/
static int l_w5500_get_mac(lua_State *L){
	uint8_t mac[6] = {0};
	w5500_get_mac(mac);
	lua_pushlstring(L, (const char*)mac, 6);
	return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_w5500[] =
{
    { "init",           ROREG_FUNC(l_w5500_init)},
	{ "config",           ROREG_FUNC(l_w5500_config)},
	{ "bind",           ROREG_FUNC(l_w5500_network_register)},
	{ "getMac",           ROREG_FUNC(l_w5500_get_mac)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_w5500( lua_State *L ) {
    luat_newlib2(L, reg_w5500);
    return 1;
}

static int l_nw_state_handler(lua_State *L, void* ptr) {
	(void)ptr;
	rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
	lua_getglobal(L, "sys_pub");
	if (msg->arg1) {
/*
@sys_pub w5500
已联网
IP_READY
@usage
-- 联网后会发一次这个消息
sys.subscribe("IP_READY", function(ip, adapter)
    log.info("w5500", "IP_READY", ip, (adapter or -1) == socket.LWIP_GP)
end)
*/
		lua_pushliteral(L, "IP_READY");
		uint32_t ip = msg->arg2;
		lua_pushfstring(L, "%d.%d.%d.%d", (ip) & 0xFF, (ip >> 8) & 0xFF, (ip >> 16) & 0xFF, (ip >> 24) & 0xFF);
		lua_pushinteger(L, NW_ADAPTER_INDEX_ETH0);
		lua_call(L, 3, 0);
	}
	else {
/*
@sys_pub w5500
已断网
IP_LOSE
@usage
-- 断网后会发一次这个消息
sys.subscribe("IP_LOSE", function(adapter)
    log.info("w5500", "IP_LOSE", (adapter or -1) == socket.ETH0)
end)
*/
		lua_pushliteral(L, "IP_LOSE");
		lua_pushinteger(L, NW_ADAPTER_INDEX_ETH0);
		lua_call(L, 2, 0);
	}
	return 0;
}

// W5500的状态回调函数
void w5500_nw_state_cb(int state, uint32_t ip) {
	rtos_msg_t msg = {0};
	msg.handler = l_nw_state_handler;
	msg.arg1 = state; // READY
	msg.arg2 = ip;
	luat_msgbus_put(&msg, 0);
}

#endif
