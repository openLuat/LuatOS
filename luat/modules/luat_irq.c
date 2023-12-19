#include "luat_base.h"
#include "luat_irq.h"
#include "luat_msgbus.h"
#include "luat_gpio.h"
#include "luat_uart.h"
#include "luat_mem.h"

int luat_irq_fire(int tp, int arg, void* args);
int l_gpio_handler(lua_State *L, void* ptr) ;
int l_uart_handler(lua_State *L, void* ptr);

int luat_irq_gpio_cb(int pin, void* args) {
    rtos_msg_t msg = {0};
    msg.handler = l_gpio_handler;
    msg.ptr = NULL;
    msg.arg1 = pin;
    msg.arg2 = luat_gpio_get(pin);
    return luat_msgbus_put(&msg, 0);
}

int luat_irq_uart_cb(int id, void* args) {
    int len = (int)(args);
    rtos_msg_t msg = {0};
    msg.handler = l_uart_handler;
    msg.ptr = NULL;
    msg.arg1 = id;
    msg.arg2 = len;
    return luat_msgbus_put(&msg, 0);
}

int luat_irq_spi_cb(int id);

static int luat_irq_topic_cb_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    if (lua_isfunction(L, -1)) {
        lua_pushstring(L, msg->ptr);
        lua_pushinteger(L, msg->arg1);
        lua_pushboolean(L, !msg->arg2);
        lua_pushinteger(L, msg->arg2);
        lua_call(L, 4, 0);
    }
    luat_heap_free(msg->ptr);
    return 0;
}

//pdata 为 result << 16 | device_id, result 为0 则表示成功，其他失败
//param 为回调topic
int32_t luat_irq_hardware_cb_handler(void *pdata, void *param)
{
    rtos_msg_t msg;
    msg.handler = luat_irq_topic_cb_handler;
    msg.ptr = param;
    msg.arg1 = (uint32_t)pdata & 0x0000ffff;
    msg.arg2 = ((uint32_t)pdata >> 16);
    luat_msgbus_put(&msg, 0);
    return 0;
}
