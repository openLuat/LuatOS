/*
@module  uart
@summary 串口操作库
@version 1.0
@data    2020.03.30
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_uart.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "string.h"

#define MAX_DEVICE_COUNT 10

typedef struct luat_uart_cb {
    int received;//回调函数
    int sent;//回调函数
} luat_uart_cb_t;
static luat_uart_cb_t uart_cbs[MAX_DEVICE_COUNT];

int l_uart_handler(lua_State *L, void* ptr) {
    //luat_log_debug("luat.uart", "l_uart_handler");
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    int uart_id = msg->arg1;
    if (!luat_uart_exist(uart_id)) {
        //luat_log_warn("luat.uart", "not exist uart id=%ld but event fired?!", uart_id);
        return 0;
    }
    // sent event
    if (msg->arg2 == 0) {
        //luat_log_debug("luat.uart", "uart%ld sent callback", uart_id);
        if (uart_cbs[uart_id].sent) {
            lua_geti(L, LUA_REGISTRYINDEX, uart_cbs[uart_id].sent);
            if (lua_isfunction(L, -1)) {
                lua_pushinteger(L, uart_id);
                lua_call(L, 1, 0);
            }
        }
    }
    else {
        if (uart_cbs[uart_id].received) {
            lua_geti(L, LUA_REGISTRYINDEX, uart_cbs[uart_id].received);
            if (lua_isfunction(L, -1)) {
                lua_pushinteger(L, uart_id);
                lua_pushinteger(L, msg->arg2);
                lua_call(L, 2, 0);
            }
            else {
                //luat_log_debug("luat.uart", "uart%ld received callback not function", uart_id);
            }
        }
        else {
            //luat_log_debug("luat.uart", "uart%ld no received callback", uart_id);
        }
    }

    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}

/*
配置串口参数
@function    uart.setup(id, baud_rate, data_bits, stop_bits, partiy, bit_order, buff_size)
@int 串口id, uart0写0, uart1写1
@int 波特率 9600~115200
@int 数据位 7或8, 一般是8
@int 停止位 1或0, 一般是1
@int 校验位, 可选 uart.None/uart.Even/uart.Odd
@int 大小端, 默认小端 uart.LSB, 可选 uart.MSB
@int 缓冲区大小, 默认值1024
@return int 成功返回0,失败返回其他值
@usage
-- 最常用115200 8N1
uart.setup(1, 115200, 8, 1, uart.NONE)
-- 可以简写为 uart.setup(1)
*/
static int l_uart_setup(lua_State *L)
{
    luat_uart_t *uart_config = (luat_uart_t *)luat_heap_malloc(sizeof(luat_uart_t));
    uart_config->id = luaL_checkinteger(L, 1);
    uart_config->baud_rate = luaL_optinteger(L, 2, 115200);
    uart_config->data_bits = luaL_optinteger(L, 3, 8);
    uart_config->stop_bits = luaL_optinteger(L, 4, 1);
    uart_config->parity = luaL_optinteger(L, 5, LUAT_PARITY_NONE);
    uart_config->bit_order = luaL_optinteger(L, 6, LUAT_BIT_ORDER_LSB);
    uart_config->bufsz = luaL_optinteger(L, 7, 1024);

    int result = luat_uart_setup(uart_config);
    lua_pushinteger(L, result);

    luat_heap_free(uart_config);
    return 1;
}

/*
写串口
@function    uart.write(id, data)
@int 串口id, uart0写0, uart1写1
@string 待写入的数据
@return int 成功的数据长度
@usage
uart.write(1, "rdy\r\n")
*/
static int l_uart_write(lua_State *L)
{
    size_t len;
    const char *buf;
    uint8_t id = luaL_checkinteger(L, 1);
    buf = lua_tolstring(L, 2, &len);//取出字符串数据
    //uint32_t length = len;
    uint8_t result = luat_uart_write(id, (char*)buf, len);
    lua_pushinteger(L, result);
    return 1;
}

/*
读串口
@function    uart.read(id, len)
@int 串口id, uart0写0, uart1写1
@int 读取长度
@return string 读取到的数据
@usage
uart.read(1, 16)
*/
static int l_uart_read(lua_State *L)
{
    uint8_t id = luaL_checkinteger(L, 1);
    uint32_t length = luaL_optinteger(L, 2, 1024);
    if (length > 1024) {
        length = 1024;
    }
    void *recv = luat_heap_malloc(length);
    if (recv == NULL) {
        luat_log_error("luat.uart", "system is out of memory!!!");
        lua_pushstring(L, "");
        return 1;
    }
    int result = luat_uart_read(id, recv, length);
    lua_gc(L, LUA_GCCOLLECT, 0);
    if (result > 0) {
        lua_pushlstring(L, (const char*)recv, result);
    }
    else
    {
        lua_pushstring(L, "");
    }
    luat_heap_free(recv);
    return 1;
}

/*
关闭串口
@function    uart.close(id)
@int 串口id, uart0写0, uart1写1
@return nil 无返回值
@usage
uart.close(1)
*/
static int l_uart_close(lua_State *L)
{
    uint8_t result = luat_uart_close(luaL_checkinteger(L, 1));
    lua_pushinteger(L, result);
    return 1;
}

/*
注册串口事件回调
@function    uart.on(id, event, func)
@int 串口id, uart0写0, uart1写1
@string 事件名称
@function 回调方法
@return nil 无返回值
@usage
uart.on("receive", function(id, len)
    local data = uart.read(id, len)
    log.info("uart", id, len, data)
end)
*/
static int l_uart_on(lua_State *L) {
    int uart_id = luaL_checkinteger(L, 1);
    if (!luat_uart_exist(uart_id)) {
        lua_pushliteral(L, "no such uart id");
        return 1;
    }
    const char* event = luaL_checkstring(L, 2);
    if (!strcmp("receive", event)) {
        if (uart_cbs[uart_id].received != 0) {
            luaL_unref(L, LUA_REGISTRYINDEX, uart_cbs[uart_id].received);
            uart_cbs[uart_id].received = 0;
        }
        if (lua_isfunction(L, 3)) {
            lua_pushvalue(L, 3);
            uart_cbs[uart_id].received = luaL_ref(L, LUA_REGISTRYINDEX);
        }
    }
    else if (!strcmp("sent", event)) {
        if (uart_cbs[uart_id].sent != 0) {
            luaL_unref(L, LUA_REGISTRYINDEX, uart_cbs[uart_id].sent);
            uart_cbs[uart_id].sent = 0;
        }
        if (lua_isfunction(L, 3)) {
            lua_pushvalue(L, 3);
            uart_cbs[uart_id].sent = luaL_ref(L, LUA_REGISTRYINDEX);
        }
    }
    luat_setup_cb(uart_id, uart_cbs[uart_id].received, uart_cbs[uart_id].sent);
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_uart[] =
{
    { "setup",  l_uart_setup,0},
    { "close",  l_uart_close,0},
    { "write",  l_uart_write,0},
    { "read",   l_uart_read,0},
    { "on",     l_uart_on, 0},
    //校验位
    { "Odd",            NULL,           LUAT_PARITY_ODD},
    { "Even",           NULL,           LUAT_PARITY_EVEN},
    { "None",           NULL,           LUAT_PARITY_NONE},
    //高低位顺序
    { "LSB",            NULL,           LUAT_BIT_ORDER_LSB},
    { "MSB",            NULL,           LUAT_BIT_ORDER_MSB},
    { NULL,             NULL ,          0}
};

LUAMOD_API int luaopen_uart(lua_State *L)
{
    rotable_newlib(L, reg_uart);
    return 1;
}
