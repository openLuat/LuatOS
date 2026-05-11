
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_mcu.h"
#include "luat_uart_drv.h"

#include "luat_pcconf.h"

#define LUAT_LOG_TAG "pc"
#include "luat_log.h"

luat_pcconf_t g_pcconf;
extern const luat_uart_drv_opts_t* uart_drvs[];
extern const luat_uart_drv_opts_t uart_udp;
extern const luat_uart_drv_opts_t uart_win32;
extern const luat_uart_drv_opts_t uart_linux;

int luat_uart_initial_win32();

void luat_pcconf_init(void) {
    #ifdef LUA_USE_WINDOWS
    // LLOGD("执行uart_win32初始化");
    if (luat_uart_initial_win32() == 0) {
        for (size_t i = 0; i < 128; i++)
        {
            uart_drvs[i] = &uart_win32;
        }
        // LLOGD("执行uart_win32初始化成功, 驱动已注册 %p", uart_drvs[1]);
        return;
    }
    #endif
    #ifdef LUA_USE_LINUX
    for (size_t i = 0; i < 128; i++)
    {
        uart_drvs[i] = &uart_linux;
    }
    return;
    #endif
    for (size_t i = 0; i < 128; i++)
    {
        uart_drvs[i] = &uart_udp;
    }
}

void luat_pcconf_save(void) {

}
