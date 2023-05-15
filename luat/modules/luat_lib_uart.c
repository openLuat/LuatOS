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
#include "luat_gpio.h"
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
#ifdef LUAT_USE_SOFT_UART
#ifndef __LUAT_C_CODE_IN_RAM__
#define __LUAT_C_CODE_IN_RAM__
#endif
#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif
#define LUAT_UART_SOFT_FIFO_CNT (128)
typedef struct
{
	llist_head tx_node;
	uint8_t *data;
	uint32_t len;
}luat_uart_soft_tx_node_t;

typedef struct
{
	uint32_t tx_period;
	uint32_t rx_period;
	uint32_t stop_period;
	int tx_adjust_period;
	int rx_adjust_period;
	Buffer_Struct rx_buffer;
	Buffer_Struct tx_buffer;
	llist_head tx_queue_head;
	uint16_t rx_bit;
	uint16_t rx_buffer_size;
	uint16_t tx_bit;
	uint8_t rx_fifo[LUAT_UART_SOFT_FIFO_CNT];
	uint8_t rx_fifo_cnt;
	uint8_t tx_shift_bits;
	uint8_t rx_shift_bits;
	uint8_t data_bits;
	uint8_t total_bits;
	uint8_t rx_parity_bit;
	uint8_t parity;             /**< 奇偶校验位 */
	uint8_t parity_odd;             /**< 奇偶校验位 */
	uint8_t tx_pin;
	uint8_t rx_pin;
	uint8_t tx_hwtimer_id;
	uint8_t rx_hwtimer_id;
	uint8_t pin485;
    uint8_t rs485_rx_level;           /**< 接收方向的电平 */
    uint8_t uart_id;
    uint8_t is_inited;
    uint8_t is_tx_busy;
    uint8_t is_rx_busy;
}luat_uart_soft_t;
static luat_uart_soft_t *prv_uart_soft;

static int32_t luat_uart_soft_del_tx_queue(void *pdata, void *param)
{
	luat_uart_soft_tx_node_t *node = (luat_uart_soft_tx_node_t *)pdata;
	luat_heap_alloc(NULL, node->data, 0, 0);
	return LIST_DEL;
}

static uint16_t __LUAT_C_CODE_IN_RAM__ luat_uart_soft_check_party(uint8_t data, uint8_t data_bits, uint8_t is_odd)
{
	uint16_t data_bits2 = data_bits;
	uint8_t party_bits = is_odd;
	while(party_bits)
	{
		party_bits += (data & 0x01);
		data >>= 1;
		party_bits--;
	};
	if (party_bits & 0x01)
	{
		return 1 << data_bits2;
	}
	return 0;
}

static int __LUAT_C_CODE_IN_RAM__ luat_uart_soft_recv_start_irq(int pin, void *param)
{
	luat_uart_soft_hwtimer_onoff(prv_uart_soft->rx_hwtimer_id, prv_uart_soft->rx_period + (prv_uart_soft->rx_period >> 4));
	prv_uart_soft->rx_shift_bits = 0;
	prv_uart_soft->rx_parity_bit = prv_uart_soft->parity_odd;
	luat_uart_soft_gpio_fast_irq_set(pin, 0);
	luat_uart_soft_sleep_enable(0);
	return 0;
}

static int luat_uart_soft_setup(luat_uart_t *uart)
{
	prv_uart_soft->rx_buffer_size = uart->bufsz;
	luat_heap_alloc(NULL, prv_uart_soft->rx_buffer.Data, 0, 0);
	prv_uart_soft->rx_buffer.Data = luat_heap_alloc(NULL, NULL, 0, prv_uart_soft->rx_buffer_size);
	if (!prv_uart_soft->rx_buffer.Data)
	{
		LLOGE("soft uart no mem!");
		prv_uart_soft->is_inited = 0;
		return -1;
	}
	prv_uart_soft->is_inited = 1;
	prv_uart_soft->data_bits = uart->data_bits;
	switch(uart->parity)
	{
	case LUAT_PARITY_NONE:
		prv_uart_soft->parity = 0;
		break;
	case LUAT_PARITY_ODD:
		prv_uart_soft->parity = 1;
		prv_uart_soft->parity_odd = 1;
		break;
	case LUAT_PARITY_EVEN:
		prv_uart_soft->parity = 1;
		prv_uart_soft->parity_odd = 0;
		break;
	}
	prv_uart_soft->parity = uart->parity;
	if (prv_uart_soft->tx_adjust_period < 0)
	{
		prv_uart_soft->tx_period = luat_uart_soft_cal_baudrate(uart->baud_rate) - (-prv_uart_soft->tx_adjust_period);
	}
	else
	{
		prv_uart_soft->tx_period = luat_uart_soft_cal_baudrate(uart->baud_rate) + prv_uart_soft->tx_adjust_period;
	}
	if (prv_uart_soft->rx_adjust_period < 0)
	{
		prv_uart_soft->rx_period = luat_uart_soft_cal_baudrate(uart->baud_rate) - (-prv_uart_soft->rx_adjust_period);
	}
	else
	{
		prv_uart_soft->rx_period = luat_uart_soft_cal_baudrate(uart->baud_rate) + prv_uart_soft->rx_adjust_period;
	}

//	LLOGD("soft uart period %u,%u!", prv_uart_soft->tx_period, prv_uart_soft->rx_period);
	switch(uart->stop_bits)
	{
	case 2:
		prv_uart_soft->total_bits = prv_uart_soft->data_bits + prv_uart_soft->parity + 4;
		prv_uart_soft->stop_period = luat_uart_soft_cal_baudrate(uart->baud_rate) * 3;
		break;
	default:
		prv_uart_soft->total_bits = prv_uart_soft->data_bits + prv_uart_soft->parity + 2;
		prv_uart_soft->stop_period = luat_uart_soft_cal_baudrate(uart->baud_rate) * 2;
		break;
	}
	if (uart->pin485 != 0xffffffff)
	{
		prv_uart_soft->pin485 = uart->pin485;
		prv_uart_soft->rs485_rx_level = uart->rx_level;
	}
	else
	{
		prv_uart_soft->pin485 = 0xff;
	}

	luat_gpio_t conf = {0};
	conf.pin = prv_uart_soft->rx_pin;
	conf.mode = Luat_GPIO_IRQ;
	conf.irq_cb = luat_uart_soft_recv_start_irq;
	conf.pull = LUAT_GPIO_PULLUP;
	conf.irq = LUAT_GPIO_FALLING_IRQ;
	luat_gpio_setup(&conf);
	conf.pin = prv_uart_soft->tx_pin;
	conf.mode = Luat_GPIO_OUTPUT;
	luat_gpio_setup(&conf);
	luat_uart_soft_gpio_fast_output(prv_uart_soft->tx_pin, 1);
	if (prv_uart_soft->pin485 != 0xff)
	{
		conf.pin = prv_uart_soft->pin485;
		conf.mode = Luat_GPIO_OUTPUT;
		luat_gpio_set(prv_uart_soft->pin485, prv_uart_soft->rs485_rx_level);
		luat_gpio_setup(&conf);
	}
	prv_uart_soft->rx_shift_bits = 0;
	prv_uart_soft->tx_shift_bits = 0;
	prv_uart_soft->rx_fifo_cnt = 0;
	prv_uart_soft->is_tx_busy = 0;
	prv_uart_soft->is_rx_busy= 0;
	luat_uart_soft_sleep_enable(1);
	return 0;
}

static void luat_uart_soft_close(void)
{
	luat_uart_soft_hwtimer_onoff(prv_uart_soft->tx_hwtimer_id, 0);
	luat_uart_soft_hwtimer_onoff(prv_uart_soft->rx_hwtimer_id, 0);
	luat_uart_soft_setup_hwtimer_callback(prv_uart_soft->tx_hwtimer_id, NULL);
	luat_uart_soft_setup_hwtimer_callback(prv_uart_soft->rx_hwtimer_id, NULL);
	prv_uart_soft->is_inited = 0;
	llist_traversal(&prv_uart_soft->tx_queue_head, luat_uart_soft_del_tx_queue, NULL);
	luat_gpio_close(prv_uart_soft->rx_pin);
	luat_gpio_close(prv_uart_soft->tx_pin);
	if (prv_uart_soft->pin485 != 0xff)
	{
		luat_gpio_close(prv_uart_soft->pin485);
	}
	luat_heap_alloc(NULL, prv_uart_soft->rx_buffer.Data, 0, 0);
	memset(&prv_uart_soft->rx_buffer, 0, sizeof(Buffer_Struct));
	prv_uart_soft->is_tx_busy = 0;
	prv_uart_soft->is_rx_busy= 0;
	luat_uart_soft_sleep_enable(1);
}

static uint32_t luat_uart_soft_read(uint8_t *data, uint32_t len)
{
//	if (!data) return prv_uart_soft->rx_buffer.Pos;
	uint32_t read_len = (len > prv_uart_soft->rx_buffer.Pos)?prv_uart_soft->rx_buffer.Pos:len;
	memcpy(data, prv_uart_soft->rx_buffer.Data, read_len);
	if (read_len >= prv_uart_soft->rx_buffer.Pos)
	{
		prv_uart_soft->rx_buffer.Pos = 0;
		if (prv_uart_soft->rx_buffer.MaxLen > prv_uart_soft->rx_buffer_size)
		{
			luat_heap_alloc(NULL, prv_uart_soft->rx_buffer.Data, 0, 0);
			prv_uart_soft->rx_buffer.Data = luat_heap_alloc(NULL, NULL, 0, prv_uart_soft->rx_buffer_size);
		}
	}
	else
	{
		uint32_t rest = prv_uart_soft->rx_buffer.Pos - read_len;
		memmove(prv_uart_soft->rx_buffer.Data, prv_uart_soft->rx_buffer.Data + read_len, rest);
		prv_uart_soft->rx_buffer.Pos = rest;
	}
	return read_len;
}

static int luat_uart_soft_write(const uint8_t *data, uint32_t len)
{
	luat_uart_soft_tx_node_t *node = luat_heap_alloc(NULL, NULL, 0, sizeof(luat_uart_soft_tx_node_t));
	if (!node)
	{
		return -1;
	}
	node->data = luat_heap_alloc(NULL, NULL, 0, len);
	if (!data)
	{
		luat_heap_alloc(NULL, node, 0, 0);
		return -1;
	}
	memcpy(node->data, data, len);
	node->len = len;
	llist_add_tail(&node->tx_node, &prv_uart_soft->tx_queue_head);
	if (!prv_uart_soft->tx_buffer.Data)
	{
		if (prv_uart_soft->pin485 != 0xff)
		{
			luat_gpio_set(prv_uart_soft->pin485, !prv_uart_soft->rs485_rx_level);
		}
		node = (luat_uart_soft_tx_node_t *)prv_uart_soft->tx_queue_head.next;
		Buffer_StaticInit(&prv_uart_soft->tx_buffer, node->data, node->len);
		prv_uart_soft->tx_shift_bits = 0;
		luat_uart_soft_hwtimer_onoff(prv_uart_soft->tx_hwtimer_id, prv_uart_soft->tx_period);
		luat_uart_soft_gpio_fast_output(prv_uart_soft->tx_pin, 0);
		if (prv_uart_soft->parity)
		{
			prv_uart_soft->tx_bit = (0xffff << prv_uart_soft->data_bits) | luat_uart_soft_check_party(prv_uart_soft->tx_buffer.Data[0], prv_uart_soft->data_bits, prv_uart_soft->parity_odd) | prv_uart_soft->tx_buffer.Data[0];
		}
		else
		{
			prv_uart_soft->tx_bit = (0xffff << prv_uart_soft->data_bits) | prv_uart_soft->tx_buffer.Data[0];
		}
	}
	prv_uart_soft->is_tx_busy = 1;
	luat_uart_soft_sleep_enable(0);
	return 0;
}
#endif
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
#ifdef LUAT_USE_SOFT_UART
    int result;
    if (prv_uart_soft && (prv_uart_soft->uart_id == uart_config.id))
    {
    	result = luat_uart_soft_setup(&uart_config);
    }
    else
    {
    	result = luat_uart_setup(&uart_config);
    }
    lua_pushinteger(L, result);
#else
    int result = luat_uart_setup(&uart_config);
    lua_pushinteger(L, result);
#endif
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
#ifdef LUAT_USE_SOFT_UART
    int result;
    if (prv_uart_soft && (prv_uart_soft->uart_id == id))
    {
    	result = luat_uart_soft_write((const uint8_t*)buf, len);
    }
    else
    {
    	result = luat_uart_write(id, (char*)buf, len);
    }
    lua_pushinteger(L, result);
#else
    int result = luat_uart_write(id, (char*)buf, len);
    lua_pushinteger(L, result);
#endif
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
#ifdef LUAT_USE_SOFT_UART
		int result;
		if (prv_uart_soft && (prv_uart_soft->uart_id == id))
		{
			result = luat_uart_soft_read(recv, length);
		}
		else
		{
			result = luat_uart_read(id, recv, length);
		}
#else
        int result = luat_uart_read(id, recv, length);
#endif
        if(result < 0)
            result = 0;
        buff->cursor += result;
        lua_pushinteger(L, result);
        return 1;
    }
	// 不再限制最小读取数量
    // if (length < 512)
    //     length = 512;
	// 若读取0字节, 直接返回空串
	if (length < 1) {
		lua_pushliteral(L, "");
		return 1;
	}
	uint8_t tmpbuff[128];
	uint8_t* recv = tmpbuff;
	uint8_t* rr = NULL;
	if (length > 128) { // 如果读取量比较大,就malloc
		rr = luat_heap_malloc(length);
		recv = rr;
	}
    if (recv == NULL) {
        LLOGE("system is out of memory!!!");
        lua_pushstring(L, "");
        return 1;
    }

    uint32_t read_length = 0;
    while(read_length < length)//循环读完
    {
#ifdef LUAT_USE_SOFT_UART
		int result;
		if (prv_uart_soft && (prv_uart_soft->uart_id == id))
		{
			result = luat_uart_soft_read((void*)(recv + read_length), length - read_length);
		}
		else
		{
			result = luat_uart_read(id, (void*)(recv + read_length), length - read_length);
		}
#else
        int result = luat_uart_read(id, (void*)(recv + read_length), length - read_length);
#endif
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
	if (rr != NULL)
    	luat_heap_free(rr);
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
#ifdef LUAT_USE_SOFT_UART
	uint8_t id = luaL_checkinteger(L,1);
	if (prv_uart_soft && (prv_uart_soft->uart_id == id))
	{
		luat_uart_soft_close();
	}
	else
	{
		luat_uart_close(id);
	}
	return 0;
#else
//    uint8_t result = luat_uart_close(luaL_checkinteger(L, 1));
//    lua_pushinteger(L, result);
	luat_uart_close(luaL_checkinteger(L, 1));
    return 0;
#endif
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
#ifdef LUAT_USE_SOFT_UART
	if (prv_uart_soft && (prv_uart_soft->uart_id == (uint8_t)uart_id))
	{
		;
	}
	else
	{
		if (!luat_uart_exist(uart_id)) {
			lua_pushliteral(L, "no such uart id");
			return 1;
		}
	}
#else
    if (!luat_uart_exist(uart_id)) {
        lua_pushliteral(L, "no such uart id");
        return 1;
    }
#endif
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
#ifdef LUAT_USE_SOFT_UART
	uint8_t id = luaL_checkinteger(L,1);
	if (prv_uart_soft && (prv_uart_soft->uart_id == id))
	{
		lua_pushboolean(L, 1);
	}
	else
	{
		lua_pushboolean(L, luat_uart_exist(id));
	}
	return 1;
#else
    lua_pushboolean(L, luat_uart_exist(luaL_checkinteger(L,1)));
    return 1;
#endif
}


/*
buff形式读串口，一次读出全部数据存入buff中，如果buff空间不够会自动扩展，目前air105,air780e支持这个操作
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
#ifdef LUAT_USE_SOFT_UART
		int result;
		if (prv_uart_soft && (prv_uart_soft->uart_id == id))
		{
			result = prv_uart_soft->rx_buffer.Pos;
		}
		else
		{
			result = luat_uart_read(id, NULL, 0);
		}
#else
    	int result = luat_uart_read(id, NULL, 0);
#endif
        if (result > (buff->len - buff->used))
        {
        	__zbuff_resize(buff, buff->len + result);
        }
#ifdef LUAT_USE_SOFT_UART
		if (prv_uart_soft && (prv_uart_soft->uart_id == id))
		{
			luat_uart_soft_read(buff->addr + buff->used, result);
		}
		else
		{
			luat_uart_read(id, buff->addr + buff->used, result);
		}
#else
        luat_uart_read(id, buff->addr + buff->used, result);
#endif
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
读串口Rx缓存中剩余数据量，目前air105,air780e支持这个操作
@api    uart.rxSize(id)
@int 串口id, uart0写0, uart1写1
@return int 返回读到的长度
@usage
local size = uart.rxSize(1)
*/
static int l_uart_rx_size(lua_State *L)
{
    uint8_t id = luaL_checkinteger(L, 1);
#ifdef LUAT_USE_SOFT_UART
	int result;
	if (prv_uart_soft && (prv_uart_soft->uart_id == id))
	{
		result = prv_uart_soft->rx_buffer.Pos;
	}
	else
	{
		result = luat_uart_read(id, NULL, 0);
	}
	lua_pushinteger(L, result);
#else
    lua_pushinteger(L, luat_uart_read(id, NULL, 0));
#endif
    return 1;
}

LUAT_WEAK void luat_uart_clear_rx_cache(int uart_id)
{

}
/*
清除串口Rx缓存中剩余数据量，目前air105,air780e支持这个操作
@api    uart.rxClear(id)
@int 串口id, uart0写0, uart1写1
@usage
uart.rxClear(1)
*/
static int l_uart_rx_clear(lua_State *L)
{
    uint8_t id = luaL_checkinteger(L, 1);
#ifdef LUAT_USE_SOFT_UART

	if (prv_uart_soft && (prv_uart_soft->uart_id == id))
	{
		prv_uart_soft->rx_buffer.Pos = 0;
	}
	else
	{
		luat_uart_clear_rx_cache(id);
	}

#else
	luat_uart_clear_rx_cache(id);
#endif
    return 0;
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
#ifdef LUAT_USE_SOFT_UART
    int result;
    if (prv_uart_soft && (prv_uart_soft->uart_id == id))
    {
    	result = luat_uart_soft_write((const uint8_t*)(buff->addr + start), len);
    }
    else
    {
    	result = luat_uart_write(id, buff->addr + start, len);
    }
    lua_pushinteger(L, result);
#else
    int result = luat_uart_write(id, buff->addr + start, len);
    lua_pushinteger(L, result);
#endif
    return 1;
}


#ifdef LUAT_USE_SOFT_UART
static int l_uart_soft_handler_tx_done(lua_State *L, void* ptr)
{
	rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
	lua_pop(L, 1);
	if (prv_uart_soft->is_inited)
	{
		luat_uart_soft_tx_node_t *node = (luat_uart_soft_tx_node_t *)(prv_uart_soft->tx_queue_head.next);
		llist_del(&node->tx_node);
		luat_heap_alloc(NULL, node->data, 0, 0);
		luat_heap_alloc(NULL, node, 0, 0);
		if (llist_empty(&prv_uart_soft->tx_queue_head))
		{
			Buffer_StaticInit(&prv_uart_soft->tx_buffer, NULL, 0);
			prv_uart_soft->is_tx_busy = 0;
			if (!prv_uart_soft->is_rx_busy)
			{
				luat_uart_soft_sleep_enable(1);
			}
			if (prv_uart_soft->pin485 != 0xff)
			{
				luat_gpio_set(prv_uart_soft->pin485, prv_uart_soft->rs485_rx_level);
			}
	        if (uart_cbs[prv_uart_soft->uart_id].sent) {
	            lua_geti(L, LUA_REGISTRYINDEX, uart_cbs[prv_uart_soft->uart_id].sent);
	            if (lua_isfunction(L, -1)) {
	                lua_pushinteger(L, prv_uart_soft->uart_id);
	                lua_call(L, 1, 0);
	            }
	        }
		}
		else
		{
			node = (luat_uart_soft_tx_node_t *)prv_uart_soft->tx_queue_head.next;
			Buffer_StaticInit(&prv_uart_soft->tx_buffer, node->data, node->len);
			prv_uart_soft->tx_shift_bits = 0;
			luat_uart_soft_gpio_fast_output(prv_uart_soft->tx_pin, 0);
			luat_uart_soft_hwtimer_onoff(prv_uart_soft->tx_hwtimer_id, prv_uart_soft->tx_period);
			if (prv_uart_soft->parity)
			{
				prv_uart_soft->tx_bit = (0xffff << prv_uart_soft->data_bits) | luat_uart_soft_check_party(prv_uart_soft->tx_buffer.Data[0], prv_uart_soft->data_bits, prv_uart_soft->parity_odd) | prv_uart_soft->tx_buffer.Data[0];
			}
			else
			{
				prv_uart_soft->tx_bit = (0xffff << prv_uart_soft->data_bits) | prv_uart_soft->tx_buffer.Data[0];
			}
		}
	}

    lua_pushinteger(L, 0);
    return 1;
}

static int l_uart_soft_handler_rx_done(lua_State *L, void* ptr)
{
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
	if (prv_uart_soft->is_inited)
	{
		if (msg->ptr && msg->arg1)
		{
			if (((uint32_t)msg->arg1 + prv_uart_soft->rx_buffer.Pos) > prv_uart_soft->rx_buffer.MaxLen)
			{
				uint8_t *new = luat_heap_alloc(NULL, NULL, 0, (prv_uart_soft->rx_buffer.MaxLen + (uint32_t)msg->arg1) * 2);
				if (new)
				{
					prv_uart_soft->rx_buffer.MaxLen = (prv_uart_soft->rx_buffer.MaxLen + (uint32_t)msg->arg1) * 2;
					memcpy(new, prv_uart_soft->rx_buffer.Data, prv_uart_soft->rx_buffer.Pos);
					luat_heap_alloc(NULL, prv_uart_soft->rx_buffer.Data, 0, 0);
					prv_uart_soft->rx_buffer.Data = new;
					memcpy(prv_uart_soft->rx_buffer.Data + prv_uart_soft->rx_buffer.Pos, msg->ptr, (uint32_t)msg->arg1);
					prv_uart_soft->rx_buffer.Pos += (uint32_t)msg->arg1;
				}
				else
				{
					LLOGE("soft uart resize no mem!");
				}
			}
			else
			{
				memcpy(prv_uart_soft->rx_buffer.Data + prv_uart_soft->rx_buffer.Pos, msg->ptr, (uint32_t)msg->arg1);
				prv_uart_soft->rx_buffer.Pos += (uint32_t)msg->arg1;
			}
		}
		if ((prv_uart_soft->rx_buffer.Pos > prv_uart_soft->rx_buffer_size) || msg->arg2)
		{
			if (uart_app_recvs[prv_uart_soft->uart_id]) {
				uart_app_recvs[prv_uart_soft->uart_id](prv_uart_soft->uart_id, msg->arg2);
			}
			if (uart_cbs[prv_uart_soft->uart_id].received) {
				lua_geti(L, LUA_REGISTRYINDEX, uart_cbs[prv_uart_soft->uart_id].received);
				if (lua_isfunction(L, -1)) {
					lua_pushinteger(L, prv_uart_soft->uart_id);
					lua_pushinteger(L, prv_uart_soft->rx_buffer.Pos);
					lua_call(L, 2, 0);
				}
			}
		}
		if (msg->arg2)
		{
			prv_uart_soft->is_rx_busy = 0;
			if (!prv_uart_soft->is_tx_busy)
			{
				luat_uart_soft_sleep_enable(1);
			}
		}

	}
	if (msg->ptr)
	{
		luat_heap_alloc(NULL, msg->ptr, 0, 0);
	}
    lua_pushinteger(L, 0);
    return 1;
}

static void __LUAT_C_CODE_IN_RAM__ luat_uart_soft_send_hwtimer_irq(void)
{
	if (prv_uart_soft->tx_shift_bits >= prv_uart_soft->total_bits)
	{
		//发送完了
		if (prv_uart_soft->tx_buffer.Pos >= prv_uart_soft->tx_buffer.MaxLen)
		{
			luat_uart_soft_hwtimer_onoff(prv_uart_soft->tx_hwtimer_id, 0);
			rtos_msg_t msg;
			msg.handler = l_uart_soft_handler_tx_done;
			msg.ptr = NULL;
			msg.arg1 = NULL;
			msg.arg2 = NULL;
			luat_msgbus_put(&msg, 0);
		}
		else
		{
			//发送新的字节的起始位
			luat_uart_soft_gpio_fast_output(prv_uart_soft->tx_pin, 0);
			luat_uart_soft_hwtimer_onoff(prv_uart_soft->tx_hwtimer_id, prv_uart_soft->tx_period);
			prv_uart_soft->tx_shift_bits = 0;
		}
		return;
	}

	luat_uart_soft_gpio_fast_output(prv_uart_soft->tx_pin, (prv_uart_soft->tx_bit >> prv_uart_soft->tx_shift_bits) & 0x01);
	prv_uart_soft->tx_shift_bits++;

	if (prv_uart_soft->tx_shift_bits > prv_uart_soft->data_bits)
	{
		luat_uart_soft_hwtimer_onoff(prv_uart_soft->tx_hwtimer_id, prv_uart_soft->stop_period);
		prv_uart_soft->tx_shift_bits = prv_uart_soft->total_bits;
		prv_uart_soft->tx_buffer.Pos++;
		if (prv_uart_soft->tx_buffer.Pos < prv_uart_soft->tx_buffer.MaxLen)
		{
			if (prv_uart_soft->parity)
			{
				prv_uart_soft->tx_bit = (0xffff << prv_uart_soft->data_bits) | luat_uart_soft_check_party(prv_uart_soft->tx_buffer.Data[prv_uart_soft->tx_buffer.Pos], prv_uart_soft->data_bits, prv_uart_soft->parity_odd) | prv_uart_soft->tx_buffer.Data[prv_uart_soft->tx_buffer.Pos];
			}
			else
			{
				prv_uart_soft->tx_bit = (0xffff << prv_uart_soft->data_bits) | prv_uart_soft->tx_buffer.Data[prv_uart_soft->tx_buffer.Pos];
			}
		}

	}
}

static void __LUAT_C_CODE_IN_RAM__ luat_uart_soft_recv_hwtimer_irq(void)
{
	uint8_t bit = luat_uart_soft_gpio_fast_input(prv_uart_soft->rx_pin);
	uint8_t is_end = 0;
	if (!prv_uart_soft->rx_shift_bits) //检测起始位
	{
		luat_uart_soft_hwtimer_onoff(prv_uart_soft->rx_hwtimer_id, prv_uart_soft->rx_period);
		prv_uart_soft->rx_bit = bit;
		prv_uart_soft->rx_shift_bits++;
		prv_uart_soft->rx_parity_bit += bit;
		return ;
	}
	else if (0xef == prv_uart_soft->rx_shift_bits)	//RX检测超时了，没有新的起始位
	{
		is_end = 1;
		goto UART_SOFT_RX_DONE;
	}
	if (prv_uart_soft->rx_shift_bits < prv_uart_soft->data_bits)
	{
		prv_uart_soft->rx_bit |= (bit << prv_uart_soft->rx_shift_bits);
		prv_uart_soft->rx_shift_bits++;
		prv_uart_soft->rx_parity_bit += bit;
		if (prv_uart_soft->rx_shift_bits >= prv_uart_soft->data_bits)
		{
			if (!prv_uart_soft->parity)	//如果不做奇偶校验，就直接开始下一个字节
			{
				goto UART_SOFT_RX_BYTE_DONE;
			}
		}
		return;
	}
	if ((prv_uart_soft->rx_parity_bit & 0x01) != bit) //奇偶校验错误
	{
		is_end = 1;
		goto UART_SOFT_RX_DONE;
	}
UART_SOFT_RX_BYTE_DONE:
	prv_uart_soft->rx_fifo[prv_uart_soft->rx_fifo_cnt] = prv_uart_soft->rx_bit;
	prv_uart_soft->rx_fifo_cnt++;
	luat_uart_soft_gpio_fast_irq_set(prv_uart_soft->rx_pin, 1);
	prv_uart_soft->rx_shift_bits = 0xef;
	luat_uart_soft_hwtimer_onoff(prv_uart_soft->rx_hwtimer_id, prv_uart_soft->stop_period * 20);	//这里做接收超时检测
	if (prv_uart_soft->rx_fifo_cnt < LUAT_UART_SOFT_FIFO_CNT)	//接收fifo没有满，继续接收
	{
		return;
	}
UART_SOFT_RX_DONE:

	if (prv_uart_soft->rx_fifo_cnt || is_end)
	{
        rtos_msg_t msg;
        msg.handler = l_uart_soft_handler_rx_done;
        msg.ptr = luat_heap_alloc(0, 0, 0, prv_uart_soft->rx_fifo_cnt);
        msg.arg1 = prv_uart_soft->rx_fifo_cnt;
        msg.arg2 = is_end;
        if (msg.ptr)
        {
        	memcpy(msg.ptr, prv_uart_soft->rx_fifo, prv_uart_soft->rx_fifo_cnt);
        }
        prv_uart_soft->rx_fifo_cnt = 0;
        luat_msgbus_put(&msg, 0);
	}
	if (is_end)
	{
		luat_uart_soft_gpio_fast_irq_set(prv_uart_soft->rx_pin, 1);
		luat_uart_soft_hwtimer_onoff(prv_uart_soft->rx_hwtimer_id, 0);
	}
	return;
}
#endif

/**
设置软件uart的硬件配置，只有支持硬件定时器的SOC才能使用，目前只能设置一个，波特率根据平台的软硬件配置有不同的极限，建议9600，接收缓存不超过65535，不支持MSB，支持485自动控制。后续仍要setup操作
@api uart.createSoft(tx_pin, tx_hwtimer_id, rx_pin, rx_hwtimer_id, adjust_period)
@int 发送引脚编号
@int 发送用的硬件定时器ID
@int 接收引脚编号
@int 接收用的硬件定时器ID
@int 发送时序调整，单位是定时器时钟周期，默认是0，需要根据示波器或者逻辑分析仪进行微调
@int 接收时序调整，单位是定时器时钟周期，默认是0，需要根据示波器或者逻辑分析仪进行微调
@return int 软件uart的id，如果失败则返回nil
@usage
-- 初始化软件uart
local uart_id = uart.createSoft(21, 0, 1, 2) --air780e建议用定时器0和2，tx_pin最好用AGPIO，防止休眠时误触发对端RX
*/
static int l_uart_soft(lua_State *L) {
#ifdef LUAT_USE_SOFT_UART
	if (!prv_uart_soft)
	{
		prv_uart_soft = luat_heap_alloc(NULL, NULL, 0, sizeof(luat_uart_soft_t));
		if (prv_uart_soft)
		{
			memset(prv_uart_soft, 0, sizeof(luat_uart_soft_t));
			INIT_LLIST_HEAD(&prv_uart_soft->tx_queue_head);
			prv_uart_soft->uart_id = 0xff;
		}
		else
		{
			lua_pushnil(L);
			goto CREATE_DONE;
		}
	}
	if (prv_uart_soft->is_inited)
	{
		lua_pushnil(L);
		goto CREATE_DONE;
	}
	for(int uart_id = 1; uart_id < MAX_DEVICE_COUNT; uart_id++)
	{
		if (!luat_uart_exist(uart_id))
		{
			LLOGD("find free uart id, %d", uart_id);
			prv_uart_soft->is_inited = 1;
			prv_uart_soft->uart_id = uart_id;
			break;
		}
	}
	if (!prv_uart_soft->is_inited)
	{
		lua_pushnil(L);
		goto CREATE_DONE;
	}

	prv_uart_soft->tx_pin = luaL_optinteger(L, 1, 0xff);
	prv_uart_soft->tx_hwtimer_id = luaL_optinteger(L, 2, 0xff);
	prv_uart_soft->rx_pin = luaL_optinteger(L, 3, 0xff);
	prv_uart_soft->rx_hwtimer_id = luaL_optinteger(L, 4, 0xff);
	prv_uart_soft->tx_adjust_period = luaL_optinteger(L, 5, 0);
	prv_uart_soft->rx_adjust_period = luaL_optinteger(L, 6, 0);
	if (luat_uart_soft_setup_hwtimer_callback(prv_uart_soft->tx_hwtimer_id, luat_uart_soft_send_hwtimer_irq))
	{
		prv_uart_soft->is_inited = 0;
	}
	if (luat_uart_soft_setup_hwtimer_callback(prv_uart_soft->rx_hwtimer_id, luat_uart_soft_recv_hwtimer_irq))
	{
		luat_uart_soft_setup_hwtimer_callback(prv_uart_soft->tx_hwtimer_id, NULL);
		prv_uart_soft->is_inited = 0;
	}
	if (!prv_uart_soft->is_inited)
	{
		lua_pushnil(L);
		goto CREATE_DONE;
	}
	lua_pushinteger(L, prv_uart_soft->uart_id);
#else
	LLOGE("not support soft uart");
	lua_pushnil(L);
#endif
#ifdef LUAT_USE_SOFT_UART
CREATE_DONE:
#endif
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
    { "write",      ROREG_FUNC(l_uart_write)},
    { "read",       ROREG_FUNC(l_uart_read)},
    { "wait485",    ROREG_FUNC(l_uart_wait485_tx_done)},
    { "tx",      	ROREG_FUNC(l_uart_tx)},
    { "rx",       	ROREG_FUNC(l_uart_rx)},
	{ "rxClear",	ROREG_FUNC(l_uart_rx_clear)},
	{ "rxSize",		ROREG_FUNC(l_uart_rx_size)},
	{ "rx_size",	ROREG_FUNC(l_uart_rx_size)},
	{ "createSoft",	ROREG_FUNC(l_uart_soft)},
    { "close",      ROREG_FUNC(l_uart_close)},
    { "on",         ROREG_FUNC(l_uart_on)},
    { "setup",      ROREG_FUNC(l_uart_setup)},
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

    //@const VUART_0 number 虚拟串口0
	{ "VUART_0",       ROREG_INT(LUAT_VUART_ID_0)},
    { NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_uart(lua_State *L)
{
    luat_newlib2(L, reg_uart);
    return 1;
}
