/*
@module  can
@summary can操作库
@version 1.0
@date    2025.2.24
@demo can
@tag LUAT_USE_CAN
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_can.h"
#include "luat_zbuff.h"

#include "rotable2.h"
static const rotable_Reg_t reg_can[] =
{
//    { "init",      ROREG_FUNC(l_uart_write)},
//    { "read",       ROREG_FUNC(l_uart_read)},
//    { "wait485",    ROREG_FUNC(l_uart_wait485_tx_done)},
//    { "tx",      	ROREG_FUNC(l_uart_tx)},
//    { "rx",       	ROREG_FUNC(l_uart_rx)},
//	{ "rxClear",	ROREG_FUNC(l_uart_rx_clear)},
//	{ "rxSize",		ROREG_FUNC(l_uart_rx_size)},
//	{ "rx_size",	ROREG_FUNC(l_uart_rx_size)},
//	{ "createSoft",	ROREG_FUNC(l_uart_soft)},
//    { "close",      ROREG_FUNC(l_uart_close)},
//    { "on",         ROREG_FUNC(l_uart_on)},
//    { "setup",      ROREG_FUNC(l_uart_setup)},
//    { "exist",      ROREG_FUNC(l_uart_exist)},
//
//	//@const Odd number 奇校验,大小写兼容性
//    { "Odd",        ROREG_INT(LUAT_PARITY_ODD)},
//	//@const Even number 偶校验,大小写兼容性
//    { "Even",       ROREG_INT(LUAT_PARITY_EVEN)},
//	//@const None number 无校验,大小写兼容性
//    { "None",       ROREG_INT(LUAT_PARITY_NONE)},
//    //@const ODD number 奇校验
//    { "ODD",        ROREG_INT(LUAT_PARITY_ODD)},
//    //@const EVEN number 偶校验
//    { "EVEN",       ROREG_INT(LUAT_PARITY_EVEN)},
//    //@const NONE number 无校验
//    { "NONE",       ROREG_INT(LUAT_PARITY_NONE)},
//    //高低位顺序
//    //@const LSB number 小端模式
//    { "LSB",        ROREG_INT(LUAT_BIT_ORDER_LSB)},
//    //@const MSB number 大端模式
//    { "MSB",        ROREG_INT(LUAT_BIT_ORDER_MSB)},
//
//    //@const VUART_0 number 虚拟串口0
//	{ "VUART_0",       ROREG_INT(LUAT_VUART_ID_0)},
//    //@const ERROR_DROP number 遇到错误时抛弃缓存的数据
//	{ "ERROR_DROP",       ROREG_INT(LUAT_UART_RX_ERROR_DROP_DATA)},
//    //@const DEBUG number 开启调试功能
//	{ "DEBUG",       ROREG_INT(LUAT_UART_DEBUG_ENABLE)},

    { NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_can( lua_State *L )
{
    luat_newlib2(L, reg_can);
    return 1;
}
