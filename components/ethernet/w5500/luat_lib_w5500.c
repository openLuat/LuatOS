/*
@module  w5500
@summary w5500
@version 1.0
@date    2022.04.11
*/

/*
@module  network_adapter
@summary 网络接口适配
@version 1.0
@date    2022.04.11
*/
#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_zbuff.h"
#include "luat_spi.h"
#define LUAT_LOG_TAG "w5500"
#include "luat_log.h"

#include "w5500_def.h"
/*
初始化w5500
@api w5500.init(spiid, speed, cs_pin, irq_pin, rst_pin, link_pin)
@int spi通道号
@int spi速度
@int cs pin
@int irq pin
@int reset pin
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
@api w5500.config(ip, submask, gateway, mac, RTR, RCR)
@string 静态ip地址，如果需要用DHCP获取，请写nil
@string 子网掩码，如果使用动态ip，则忽略
@string 网关，如果使用动态ip，则忽略
@string MAC，写nil则通过MCU唯一码自动生成，如果要写，长度必须是6byte
@int 重试间隔时间，默认2000，单位100us，不懂的不要改
@int 最大重试次数，默认8，不懂的不要改
@usage
w5500.config("192.168.1.2", "255.255.255.0", "192.168.1.1", string.fromHex("102a3b4c5d6e"))
*/
static int l_w5500_config(lua_State *L){
	if (!w5500_ready())
	{
		lua_pushboolean(L, 0);
		LLOGD("device no ready");
		return 1;
	}
	uint32_t RTR = luaL_optinteger(L, 5, 2000);
	uint32_t RCR = luaL_optinteger(L, 6, 8);
	w5500_request(W5500_CMD_SET_TO_PARAM, RTR, RCR, 0);
	if (lua_isstring(L, 4))
	{
		size_t mac_len = 0;
		const char *mac = luaL_checklstring(L, 4, &mac_len);
		uint32_t mac1;
		uint16_t mac2;
		w5500_array_to_mac(mac, &mac1, &mac2);
		w5500_request(W5500_CMD_SET_MAC, mac1, mac2, 0);
	}
	if (lua_isstring(L, 1))
	{
	    size_t ip_len = 0;
	    const char* ip = luaL_checklstring(L, 1, &ip_len);
	    size_t mask_len = 0;
	    const char* mask = luaL_checklstring(L, 2, &mask_len);
	    size_t gateway_len = 0;
	    const char* gateway = luaL_checklstring(L, 3, &gateway_len);
	    w5500_request(W5500_CMD_SET_IP, w5500_string_to_ip(ip, ip_len), w5500_string_to_ip(mask, mask_len), w5500_string_to_ip(gateway, gateway_len));
	}
	else
	{
		w5500_request(W5500_CMD_SET_IP, 0, 0, 0);
	}
	w5500_request(W5500_CMD_RE_INIT, 0, 0, 0);
	lua_pushboolean(L, 1);
	return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_w5500[] =
{
    { "init",           ROREG_FUNC(l_w5500_init)},
	{ "config",           ROREG_FUNC(l_w5500_config)},
	{ NULL,            {}}
};

LUAMOD_API int luaopen_w5500( lua_State *L ) {
    luat_newlib2(L, reg_w5500);
    return 1;
}
