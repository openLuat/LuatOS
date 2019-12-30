

#ifndef _PLATFORM_RTOS_H_
#define _PLATFORM_RTOS_H_

#define LuatVersion "1.0.0"

LUAMOD_API int luaopen_rtos( lua_State *L );

typedef enum PlatformMsgIdTag
{
    RTOS_MSG_WAIT_MSG_TIMEOUT, // receive message timeout
    RTOS_MSG_TIMER,
    RTOS_MSG_UART_RX_DATA,
    RTOS_MSG_UART_TX_DONE,
    RTOS_MSG_INT,
    RTOS_MSG_PMD,
    NumOfMsgIds
}PlatformMsgId;

typedef struct{
    PlatformMsgId id;
    UINT32 data;
}PlatformMsg;

#endif
