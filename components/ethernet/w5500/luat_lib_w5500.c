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
#define LUAT_LOG_TAG "w5500"
#include "luat_log.h"

/*
初始化w5500
@api w5500.init(spiid, speed, cs_pin, irq_pin, rst_pin, link_pin)
@int spi通道号
@int spi速度
@int cs pin
@int irq pin
@int reset pin
@int link pin 如果不填，则不适用link变化中断，只会轮询状态
@usage
w5500.init(spi.SPI_0, 24000000, pin.PB13, pin.PC08, pin.PC09)
*/

static int l_w5500_init(lua_State *L){
	luat_spi_t spi = {0};
	spi.id = luaL_checkinteger(L, 1);
	spi.bandrate = luaL_checkinteger(L, 2);
	spi.mode = luaL_checkinteger(L, 3);
	int cs_pin = luaL_checkinteger(L, 4);
	int irq_pin = luaL_checkinteger(L, 5);
	int reset_pin = luaL_checkinteger(L, 6);
	int link_pin = luaL_optinteger(L, 7, 0xff);
	return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_w5500[] =
{
    { "init",           ROREG_FUNC(l_w5500_init)},
	{ NULL,            {}}
};

LUAMOD_API int luaopen_w5500( lua_State *L ) {
    luat_newlib2(L, reg_w5500);
    return 1;
}
