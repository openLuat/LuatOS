#ifndef __PORT_H__
#define __PORT_H__
#include  "epdk.h"
#include "mod_orange.h"
#include "mod_cedar.h"
#include "gui_core.h"
#include "bsp_display.h"
#include "bsp_uart.h"
#include "drv_uart.h"
#define DBG(X,Y...) __log("%s %d:"X"\r\n", __FUNCTION__, __LINE__, ##Y)
#define SYS_TICK    (10)
extern int port_entry(void);
#define GPIO_PORTA 1
#define GPIO_PORTB 2
#define GPIO_PORTC 3
#define GPIO_PORTD 4
#define GPIO_PORTE 5
#define USER_MSG_ID_START 0x10000000
enum
{
    UART_MSG_ID_START = USER_MSG_ID_START + 0x1000,
    UART_MSG_INT_CALLBACK,
};
#endif
