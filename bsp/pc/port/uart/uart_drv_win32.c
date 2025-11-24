#include "luat_base.h"
#include "luat_mem.h"
#include "luat_msgbus.h"
#include "luat_uart.h"
#include "luat_log.h"
#include "luat_uart_drv.h"

#define LUAT_LOG_TAG           "uart"
#include "luat_log.h"


#ifdef LUA_USE_WINDOWS

#include "windows.h"


int l_uart_handler(lua_State *L, void* ptr);
static void luat_uart_recv_cb(int id, int len);

//检测串口存不存在
int (*luat_uart_exist_extern)(int id)  = NULL;
//打开串口
int (*luat_uart_open_extern)(int id,int br,int db, int sb, int para)  = NULL;
//关闭串口
int (*luat_uart_close_extern)(int id)  = NULL;
//读取数据
int (*luat_uart_read_extern)(int id,void* buff, size_t len)  = NULL;
//发送数据
int (*luat_uart_send_extern)(int id,void* buff, size_t len)  = NULL;
//配置接收回调
int (*luat_uart_recv_cb_extern)(int id,void (*)(int id, int len))  = NULL;
//配置发送回调
int (*luat_uart_sent_cb_extern)(int id,void (*)(int id, int len))  = NULL;
//获取可用串口列表
int (*luat_uart_get_list_extern)(uint8_t* list, size_t buff_len)  = NULL;

int luat_uart_initial_win32()
{
    HMODULE module = LoadLibraryA("luat_uart_i686.dll");
    if (module == NULL) {
        LLOGE("uart library initial error!");
        return -1;
    }
    luat_uart_exist_extern = (int (*)(int))GetProcAddress(module, "luat_uart_exist_extern");
    luat_uart_open_extern = (int (*)(int,int,int,int,int))GetProcAddress(module, "luat_uart_open_extern");
    luat_uart_close_extern = (int (*)(int))GetProcAddress(module, "luat_uart_close_extern");
    luat_uart_read_extern = (int (*)(int,void*,size_t))GetProcAddress(module, "luat_uart_read_extern");
    luat_uart_send_extern = (int (*)(int,void*,size_t))GetProcAddress(module, "luat_uart_send_extern");
    luat_uart_recv_cb_extern = (int (*)(int,void (*)(int, const char *, int)))GetProcAddress(module, "luat_uart_recv_cb_extern");
    luat_uart_sent_cb_extern = (int (*)(int,void (*)(int, int)))GetProcAddress(module, "luat_uart_sent_cb_extern");
    luat_uart_get_list_extern = (int (*)(uint8_t*,size_t))GetProcAddress(module, "luat_uart_get_list_extern");
    //FreeLibrary(module);//感觉用不到
    return 0;
}

static int luat_uart_exist(int uartid) 
{
    return luat_uart_exist_extern(uartid);
}

static int luat_uart_list(uint8_t* list, size_t buff_len){
    return luat_uart_get_list_extern(list,buff_len);
}

static int uart_setup_win32(void* userdata, luat_uart_t* uart)
{
    // LLOGD("执行uart_setup_win32");
    int ret = luat_uart_open_extern(uart->id,uart->baud_rate,uart->data_bits,uart->stop_bits,uart->parity);
    // LLOGD("执行uart_setup_win32 %d", ret);
    if (ret == 0) {
        luat_uart_recv_cb_extern(uart->id,luat_uart_recv_cb);
    }
    return ret;
}

static int uart_write_win32(void* userdata, int uartid, void* data, size_t length)
{
    return luat_uart_send_extern(uartid,data,length);
}

static int uart_read_win32(void* userdata, int uartid, void* buffer, size_t length)
{
    return luat_uart_read_extern(uartid,buffer,length);
}

static int uart_close_win32(void* userdata, int uartid)
{
    return luat_uart_close_extern(uartid);
}

static void luat_uart_recv_cb(int id, int len)
{
    rtos_msg_t msg;
    msg.handler = l_uart_handler;
    msg.ptr = NULL;
    msg.arg1 = id;
    msg.arg2 = len;
    luat_msgbus_put(&msg, 1);
}

static int luat_setup_cb(int uartid, int received, int sent) {
    if (!luat_uart_exist(uartid)) {
        LLOGW("uart id=%d not exist", uartid);
        return -1;
    }
    if (received) {
        return luat_uart_recv_cb_extern(uartid,luat_uart_recv_cb);
    }
    if (sent) {
        LLOGW("[waring] win32 uart lib do not support uart sent cb function %d", uartid);
        return 1;
    }
    return 0;
}



const luat_uart_drv_opts_t uart_win32 = {
    .setup = uart_setup_win32,
    .write = uart_write_win32,
    .read = uart_read_win32,
    .close = uart_close_win32,
};

#endif
