/*
@module  uart
@summary 串口操作库
@version 1.0
@date    2020.03.30
@demo uart
@video https://www.bilibili.com/video/BV1er4y1p75y
@tag LUAT_USE_UART
*/
#include "luat_base.h"
#include "luat_uart.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "string.h"
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "uart"
#include "luat_log.h"

#define MAX_DEVICE_COUNT 9
#define MAX_USB_DEVICE_COUNT 1
typedef struct luat_uart_cb {
    int received;//回调函数
    int sent;//回调函数
} luat_uart_cb_t;
static luat_uart_cb_t uart_cbs[MAX_DEVICE_COUNT + MAX_USB_DEVICE_COUNT];
static luat_uart_recv_callback_t uart_app_recvs[MAX_DEVICE_COUNT + MAX_USB_DEVICE_COUNT];

void luat_uart_set_app_recv(int id, luat_uart_recv_callback_t cb) {
    if (luat_uart_exist(id)) {
        uart_app_recvs[id] = cb;
        luat_setup_cb(id, 1, 0); // 暂时覆盖
    }
}

int l_uart_handler(lua_State *L, void* ptr) {
    (void)ptr;
    //LLOGD("l_uart_handler");
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    int uart_id = msg->arg1;
    if (!luat_uart_exist(uart_id)) {
        //LLOGW("not exist uart id=%ld but event fired?!", uart_id);
        return 0;
    }
    int org_uart_id = uart_id;
    if (uart_id >= LUAT_VUART_ID_0)
    {
    	uart_id = MAX_DEVICE_COUNT + uart_id - LUAT_VUART_ID_0;
    }
    // sent event
    if (msg->arg2 == 0) {
        //LLOGD("uart%ld sent callback", uart_id);
        if (uart_cbs[uart_id].sent) {
            lua_geti(L, LUA_REGISTRYINDEX, uart_cbs[uart_id].sent);
            if (lua_isfunction(L, -1)) {
                lua_pushinteger(L, org_uart_id);
                lua_call(L, 1, 0);
            }
        }
    }
    else {
        if (uart_app_recvs[uart_id]) {
            uart_app_recvs[uart_id](uart_id, msg->arg2);
        }
        if (uart_cbs[uart_id].received) {
            lua_geti(L, LUA_REGISTRYINDEX, uart_cbs[uart_id].received);
            if (lua_isfunction(L, -1)) {
                lua_pushinteger(L, org_uart_id);
                lua_pushinteger(L, msg->arg2);
                lua_call(L, 2, 0);
            }
            else {
                //LLOGD("uart%ld received callback not function", uart_id);
            }
        }
        else {
            //LLOGD("uart%ld no received callback", uart_id);
        }
    }

    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}

/*
配置串口参数
@api    uart.setup(id, baud_rate, data_bits, stop_bits, partiy, bit_order, buff_size, rs485_gpio, rs485_level, rs485_delay)
@int 串口id, uart0写0, uart1写1, 如此类推, 最大值取决于设备
@int 波特率, 默认115200，可选择波特率表:{2000000,921600,460800,230400,115200,57600,38400,19200,9600,4800,2400}
@int 数据位，默认为8, 可选 7/8
@int 停止位，默认为1, 根据实际情况，可以有0.5/1/1.5/2等
@int 校验位，可选 uart.None/uart.Even/uart.Odd
@int 大小端，默认小端 uart.LSB, 可选 uart.MSB
@int 缓冲区大小，默认值1024
@int 485模式下的转换GPIO, 默认值0xffffffff
@int 485模式下的rx方向GPIO的电平, 默认值0
@int 485模式下tx向rx转换的延迟时间，默认值12bit的时间，单位us
@return int 成功返回0,失败返回其他值
@usage
-- 最常用115200 8N1
uart.setup(1, 115200, 8, 1, uart.NONE)
-- 可以简写为 uart.setup(1)

-- 485自动切换, 选取GPIO10作为收发转换脚
uart.setup(1, 115200, 8, 1, uart.NONE, uart.LSB, 1024, 10, 0, 100)
*/
static int l_uart_setup(lua_State *L)
{
    lua_Number stop_bits = luaL_optnumber(L, 4, 1);
    luat_uart_t uart_config = {
        .id = luaL_checkinteger(L, 1),
        .baud_rate = luaL_optinteger(L, 2, 115200),
        .data_bits = luaL_optinteger(L, 3, 8),
        .parity = luaL_optinteger(L, 5, LUAT_PARITY_NONE),
        .bit_order = luaL_optinteger(L, 6, LUAT_BIT_ORDER_LSB),
        .bufsz = luaL_optinteger(L, 7, 1024),
        .pin485 = luaL_optinteger(L, 8, 0xffffffff),
        .rx_level = luaL_optinteger(L, 9, 0),
    };
    if(stop_bits == 0.5)
        uart_config.stop_bits = LUAT_0_5_STOP_BITS;
    else if(stop_bits == 1.5)
        uart_config.stop_bits = LUAT_1_5_STOP_BITS;
    else
        uart_config.stop_bits = (uint8_t)stop_bits;

    uart_config.delay = luaL_optinteger(L, 10, 12000000/uart_config.baud_rate);

    int result = luat_uart_setup(&uart_config);
    lua_pushinteger(L, result);

    return 1;
}

/*
写串口
@api    uart.write(id, data)
@int 串口id, uart0写0, uart1写1
@string/zbuff 待写入的数据，如果是zbuff会从指针起始位置开始读
@int 可选，要发送的数据长度，默认全发
@return int 成功的数据长度
@usage
-- 写入可见字符串
uart.write(1, "rdy\r\n")
-- 写入十六进制的数据串
uart.write(1, string.char(0x55,0xAA,0x4B,0x03,0x86))
*/
static int l_uart_write(lua_State *L)
{
    size_t len;
    const char *buf;
    uint8_t id = luaL_checkinteger(L, 1);
    if(lua_isuserdata(L, 2))
    {
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        len = buff->len - buff->cursor;
        buf = (const char *)(buff->addr + buff->cursor);
    }
    else
    {
        buf = lua_tolstring(L, 2, &len);//取出字符串数据
    }
    if(lua_isinteger(L, 3))
    {
        size_t l = luaL_checkinteger(L, 3);
        if(len > l)
            len = l;
    }
    int result = luat_uart_write(id, (char*)buf, len);
    lua_pushinteger(L, result);
    return 1;
}

/*
读串口
@api    uart.read(id, len)
@int 串口id, uart0写0, uart1写1
@int 读取长度
@file/zbuff 可选：文件句柄或zbuff对象
@return string 读取到的数据 / 传入zbuff时，返回读到的长度，并把zbuff指针后移
@usage
uart.read(1, 16)
*/
static int l_uart_read(lua_State *L)
{
    uint8_t id = luaL_checkinteger(L, 1);
    uint32_t length = luaL_optinteger(L, 2, 1024);
    if(lua_isuserdata(L, 3)){//zbuff对象特殊处理
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE));
        uint8_t* recv = buff->addr+buff->cursor;
        if(length > buff->len - buff->cursor)
            length = buff->len - buff->cursor;
        int result = luat_uart_read(id, recv, length);
        if(result < 0)
            result = 0;
        buff->cursor += result;
        lua_pushinteger(L, result);
        return 1;
    }
    if (length < 512)
        length = 512;
    uint8_t* recv = luat_heap_malloc(length);
    if (recv == NULL) {
        LLOGE("system is out of memory!!!");
        lua_pushstring(L, "");
        return 1;
    }

    uint32_t read_length = 0;
    while(read_length < length)//循环读完
    {
        int result = luat_uart_read(id, (void*)(recv + read_length), length - read_length);
        if (result > 0) {
            read_length += result;
        }
        else
        {
            break;
        }
    }
    if(read_length > 0)
    {
        if (lua_isinteger(L, 3)) {
            uint32_t fd = luaL_checkinteger(L, 3);
            luat_fs_fwrite(recv, 1, read_length, (FILE*)fd);
        }
        else {
            lua_pushlstring(L, (const char*)recv, read_length);
        }
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
@api    uart.close(id)
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
@api    uart.on(id, event, func)
@int 串口id, uart0写0, uart1写1
@string 事件名称
@function 回调方法
@return nil 无返回值
@usage
uart.on(1, "receive", function(id, len)
    local data = uart.read(id, len)
    log.info("uart", id, len, data)
end)
*/
static int l_uart_on(lua_State *L) {
    int uart_id = luaL_checkinteger(L, 1);
    int org_uart_id = uart_id;
    if (!luat_uart_exist(uart_id)) {
        lua_pushliteral(L, "no such uart id");
        return 1;
    }
    if (uart_id >= LUAT_VUART_ID_0)
    {
    	uart_id = MAX_DEVICE_COUNT + uart_id - LUAT_VUART_ID_0;
    }

    const char* event = luaL_checkstring(L, 2);
    if (!strcmp("receive", event) || !strcmp("recv", event)) {
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
    luat_setup_cb(org_uart_id, uart_cbs[uart_id].received, uart_cbs[uart_id].sent);
    return 0;
}


/*
等待485模式下TX完成，mcu不支持串口发送移位寄存器空或者类似中断时才需要，在sent事件回调后使用
@api uart.wait485(id)
@int 串口id, uart0写0, uart1写1
@return int 等待了多少次循环才等到tx完成，用于粗劣的观察delay时间是否足够，返回不为0说明还需要放大delay
 */
static int l_uart_wait485_tx_done(lua_State *L) {
    int uart_id = luaL_checkinteger(L, 1);
    if (!luat_uart_exist(uart_id)) {
    	lua_pushinteger(L, 0);
        return 1;
    }
#ifdef LUAT__UART_TX_NEED_WAIT_DONE
    lua_pushinteger(L, luat_uart_wait_485_tx_done(uart_id));
#else
    lua_pushinteger(L, 0);
#endif
    return 1;
}

/*
检查串口号是否存在
@api    uart.exist(id)
@int 串口id, uart0写0, uart1写1, 如此类推
@return bool 存在返回true
*/
static int l_uart_exist(lua_State *L)
{
    lua_pushboolean(L, luat_uart_exist(luaL_checkinteger(L,1)));
    return 1;
}


/*
buff形式读串口，一次读出全部数据存入buff中，如果buff空间不够会自动扩展，目前只有air105支持这个操作
@api    uart.rx(id, buff)
@int 串口id, uart0写0, uart1写1
@zbuff zbuff对象
@return int 返回读到的长度，并把zbuff指针后移
@usage
uart.rx(1, buff)
*/
static int l_uart_rx(lua_State *L)
{
    uint8_t id = luaL_checkinteger(L, 1);

    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
    	luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        int result = luat_uart_read(id, NULL, 0);	//读出当前缓存的长度，目前只有105支持这个操作
        if (result > (buff->len - buff->used))
        {
        	__zbuff_resize(buff, buff->len + result);
        }
        luat_uart_read(id, buff->addr + buff->used, result);
        lua_pushinteger(L, result);
        buff->used += result;
        return 1;
    }
    else
    {
        lua_pushinteger(L, 0);
        return 1;
    }
    return 1;
}

/*
读串口Rx缓存中剩余数据量，目前只有air105支持这个操作
@api    uart.rx_size(id)
@int 串口id, uart0写0, uart1写1
@return int 返回读到的长度
@usage
local size = uart.rx_size(1)
*/
static int l_uart_rx_size(lua_State *L)
{
    uint8_t id = luaL_checkinteger(L, 1);
    lua_pushinteger(L, luat_uart_read(id, NULL, 0));//读出当前缓存的长度，目前只有105支持这个操作
    return 1;
}


/*
buff形式写串口,等同于c语言uart_tx(uart_id, &buff[start], len);
@api    uart.tx(id, buff, start, len)
@int 串口id, uart0写0, uart1写1
@zbuff 待写入的数据，如果是zbuff会从指针起始位置开始读
@int 可选，要发送的数据起始位置，默认为0
@int 可选，要发送的数据长度，默认为zbuff内有效数据，最大值不超过zbuff的最大空间
@return int 成功的数据长度
@usage
uart.tx(1, buf)
*/
static int l_uart_tx(lua_State *L)
{
    size_t start, len;
    // const char *buf;
    luat_zbuff_t *buff;
    uint8_t id = luaL_checkinteger(L, 1);
    if(lua_isuserdata(L, 2))
    {
        buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
    }
    else
    {
    	lua_pushinteger(L, 0);
    	return 1;
    }
    start = luaL_optinteger(L, 3, 0);
    len = luaL_optinteger(L, 4, buff->used);
    if (start >= buff->len)
    {
    	lua_pushinteger(L, 0);
    	return 1;
    }
    if ((start + len)>= buff->len)
    {
    	len = buff->len - start;
    }
    int result = luat_uart_write(id, buff->addr + start, len);
    lua_pushinteger(L, result);
    return 1;
}


/*
获取可用串口号列表，当前仅限win32
@api    uart.list(max)
@int    可选，默认256，最多获取多少个串口
@return table 获取到的可用串口号列表
*/
#ifdef LUAT_FORCE_WIN32
static int l_uart_list(lua_State *L)
{
    size_t len = luaL_optinteger(L,1,256);
    lua_newtable(L);//返回用的table
    uint8_t* buff = (uint8_t*)luat_heap_malloc(len);
    if (!buff)
        return 1;
    int rlen = luat_uart_list(buff, len);
    for(int i = 0;i<rlen;i++)
    {
        lua_pushinteger(L,i+1);
        lua_pushinteger(L,buff[i]);
        lua_settable(L,-3);
    }
    luat_heap_free(buff);
    return 1;
}
#endif

#include "rotable2.h"
static const rotable_Reg_t reg_uart[] =
{
    { "setup",      ROREG_FUNC(l_uart_setup)},
    { "close",      ROREG_FUNC(l_uart_close)},
    { "write",      ROREG_FUNC(l_uart_write)},
    { "read",       ROREG_FUNC(l_uart_read)},
    { "on",         ROREG_FUNC(l_uart_on)},
    { "wait485",    ROREG_FUNC(l_uart_wait485_tx_done)},
    { "exist",      ROREG_FUNC(l_uart_exist)},
#ifdef LUAT_FORCE_WIN32
    { "list",       ROREG_FUNC(l_uart_list)},
#endif
	//@const Odd number 奇校验,大小写兼容性
    { "Odd",        ROREG_INT(LUAT_PARITY_ODD)},
	//@const Even number 偶校验,大小写兼容性
    { "Even",       ROREG_INT(LUAT_PARITY_EVEN)},
	//@const None number 无校验,大小写兼容性
    { "None",       ROREG_INT(LUAT_PARITY_NONE)},
    //@const ODD number 奇校验
    { "ODD",        ROREG_INT(LUAT_PARITY_ODD)},
    //@const EVEN number 偶校验
    { "EVEN",       ROREG_INT(LUAT_PARITY_EVEN)},
    //@const NONE number 无校验
    { "NONE",       ROREG_INT(LUAT_PARITY_NONE)},
    //高低位顺序
    //@const LSB number 小端模式
    { "LSB",        ROREG_INT(LUAT_BIT_ORDER_LSB)},
    //@const MSB number 大端模式
    { "MSB",        ROREG_INT(LUAT_BIT_ORDER_MSB)},

    { "tx",      ROREG_FUNC(l_uart_tx)},
    { "rx",       ROREG_FUNC(l_uart_rx)},
	{ "rx_size",	ROREG_FUNC(l_uart_rx_size)},

    //@const VUART_0 number 虚拟串口0
	{ "VUART_0",        ROREG_INT(LUAT_VUART_ID_0)},
    { NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_uart(lua_State *L)
{
    luat_newlib2(L, reg_uart);
    return 1;
}
