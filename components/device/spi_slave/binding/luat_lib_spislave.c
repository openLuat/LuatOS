/*
@module spislave
@summary SPI从机(开发中)
@version 1.0
@date    2024.3.27
@demo spislave
@tag LUAT_USE_SPI_SLAVE
@usage
-- 请查阅demo
 */
#include "luat_base.h"
#include "rotable2.h"
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "spislave"
#include "luat_log.h"

/*
初始化SPI从机
@api spislave.setup(id, opts)
@int 从机SPI的编号,注意与SPI主机的编号的差异,这个与具体设备相关
@table opts 扩展配置参数,当前无参数
@return boolean true表示成功,其他失败
@usage
-- 当前仅XT804系列支持, 例如 Air101/Air103/Air601/Air690
-- Air101为例, 初始化SPI从机, 编号为2, SPI模式
spislave.setup(2)
-- Air101为例, 初始化SPI从机, 编号为3, SDIO模式
spislavve.setup(3)
*/
static int l_spi_slave_setup(lua_State *L) {
    return 0;
}

/*
是否可写
@api spislave.ready()
@return boolean true表示可写,其他不可写
*/
static int l_spi_slave_ready(lua_State *L) {
}

static const rotable_Reg_t reg_spi_slave[] = {
    { "setup",              ROREG_FUNC(l_spi_slave_setup)},
    { "ready",              ROREG_FUNC(l_spi_slave_ready)},
    { NULL,                 ROREG_INT(0)}
};

LUAMOD_API int luaopen_spislave(lua_State *L)
{
    luat_newlib2(L, reg_spi_slave);
    return 1;
}
