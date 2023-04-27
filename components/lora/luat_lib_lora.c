/*
@module  lora
@summary lora驱动模块
@version 1.0
@date    2022.06.24
@demo lora
@tag LUAT_USE_LORA
*/

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"

#include "sx126x/radio.h"
#include "sx126x/sx126x.h"
#include "sx126x/sx126x-board.h"

#define LUAT_LOG_TAG "lora"
#include "luat_log.h"

extern uint8_t SX126xSpi;
extern uint8_t SX126xCsPin;
extern uint8_t SX126xResetPin;
extern uint8_t SX126xBusyPin;
extern uint8_t SX126xDio1Pin;
static RadioEvents_t RadioEvents;

enum{
LORA_TX_DONE,
LORA_RX_DONE,
LORA_TX_TIMEOUT,
LORA_RX_TIMEOUT,
LORA_RX_ERROR,
};

static int l_lora_handler(lua_State* L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    int event = msg->arg1;
    lua_getglobal(L, "sys_pub");
    if (lua_isnil(L, -1)) {
        lua_pushinteger(L, 0);
        return 1;
    }
    switch (event){
    case LORA_TX_DONE:
/*
@sys_pub lora
LORA 发送完成
LORA_TX_DONE
@usage
sys.subscribe("LORA_TX_DONE", function()
    lora.recive(1000)
end)
*/
        lua_pushstring(L, "LORA_TX_DONE");
        lua_call(L, 1, 0);
        break;
    case LORA_RX_DONE:
/*
@sys_pub lora
LORA 接收完成
LORA_RX_DONE
@usage
sys.subscribe("LORA_RX_DONE", function(data, size)
    log.info("LORA_RX_DONE: ", data, size)
    lora.send("PING")
end)
*/
        lua_pushstring(L, "LORA_RX_DONE");
        lua_pushlstring(L, (const char *)msg->ptr,msg->arg2);
        lua_pushinteger(L, msg->arg2);
        lua_call(L, 3, 0);
        luat_heap_free(msg->ptr);
        break;
    case LORA_TX_TIMEOUT:
/*
@sys_pub lora
LORA 发送超时
LORA_TX_TIMEOUT
@usage
sys.subscribe("LORA_TX_TIMEOUT", function()
    lora.recive(1000)
end)
*/
        lua_pushstring(L, "LORA_TX_TIMEOUT");
        lua_call(L, 1, 0);
        break;
    case LORA_RX_TIMEOUT:
/*
@sys_pub lora
LORA 接收超时
LORA_RX_TIMEOUT
@usage
sys.subscribe("LORA_RX_TIMEOUT", function()
    lora.recive(1000)
end)
*/
        lua_pushstring(L, "LORA_RX_TIMEOUT");
        lua_call(L, 1, 0);
        break;
    case LORA_RX_ERROR:
/*
@sys_pub lora
LORA 接收错误
LORA_RX_ERROR
@usage
sys.subscribe("LORA_RX_ERROR", function()
    lora.recive(1000)
end)
*/
        lua_pushstring(L, "LORA_RX_ERROR");
        lua_call(L, 1, 0);
        break;
    }
    return 0;
}

static void OnTxDone( void ){
    rtos_msg_t msg = {0};
    msg.handler = l_lora_handler;
    msg.ptr = NULL;
    msg.arg1 = LORA_TX_DONE;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 1);
}

static void OnRxDone( uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr ){
    // printf("RxDone size:%d rssi:%d snr:%d\n",size,rssi,snr);
    // printf("RxDone payload: %.*s",size,payload);
    char* rx_buff = luat_heap_malloc(size);
    memcpy( rx_buff, payload, size );

    rtos_msg_t msg = {0};
    msg.handler = l_lora_handler;
    msg.ptr = rx_buff;
    msg.arg1 = LORA_RX_DONE;
    msg.arg2 = size;
    luat_msgbus_put(&msg, 1);
}

static void OnTxTimeout( void ){
    rtos_msg_t msg = {0};
    msg.handler = l_lora_handler;
    msg.ptr = NULL;
    msg.arg1 = LORA_TX_TIMEOUT;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 1);
}

static void OnRxTimeout( void ){
    rtos_msg_t msg = {0};
    msg.handler = l_lora_handler;
    msg.ptr = NULL;
    msg.arg1 = LORA_RX_TIMEOUT;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 1);
}

static void OnRxError( void ){
    rtos_msg_t msg = {0};
    msg.handler = l_lora_handler;
    msg.ptr = NULL;
    msg.arg1 = LORA_RX_ERROR;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 1);
}

extern void RadioEventsInit(RadioEvents_t *events);
/*
lora初始化
@api lora.init(ic, loraconfig,spiconfig)
@string lora 型号，当前支持：<br>llcc68<br>sx1268
@table lora配置参数,与具体设备有关
@usage
lora.init("llcc68",
    {
        id = 0,           -- SPI id
        cs = pin.PB04,    -- SPI 片选的GPIO号,如果没有pin库,填GPIO数字编号就行
        res = pin.PB00,   -- 复位脚连接的GPIO号,如果没有pin库,填GPIO数字编号就行
        busy = pin.PB01,  -- 忙检测脚的GPIO号
        dio1 = pin.PB06,  -- 数据输入中断脚
        lora_init = true  -- 是否发送初始化命令. 如果是唤醒后直接读取, 就传false
    }
)
*/
static int luat_lora_init(lua_State *L){
    size_t len = 0;
    const char* lora_ic = luaL_checklstring(L, 1, &len);
    if(strcmp("llcc68",lora_ic)== 0||strcmp("LLCC68",lora_ic)== 0||strcmp("sx1268",lora_ic)== 0||strcmp("SX1268",lora_ic)== 0){
        uint8_t id = 0,cs = 0,res = 0,busy = 0,dio1 = 0;
        bool lora_init = true;
        if (lua_istable(L, 2)) {
            lua_pushstring(L, "id");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                id = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "cs");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                cs = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "res");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                res = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "busy");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                busy = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "dio1");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                dio1 = luaL_checkinteger(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "lora_init");
            if (LUA_TBOOLEAN == lua_gettable(L, 2)) {
                lora_init = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
        }

        luat_spi_t sx126x_spi = {0};
        sx126x_spi.id = id;
        sx126x_spi.CPHA = 0;
        sx126x_spi.CPOL = 0;
        sx126x_spi.dataw = 8;
        sx126x_spi.bit_dict = 1;
        sx126x_spi.master = 1;
        sx126x_spi.mode = 0;
        sx126x_spi.bandrate = 20000000;
        sx126x_spi.cs = Luat_GPIO_MAX_ID;
        luat_spi_setup(&sx126x_spi);

        SX126xSpi = id;
        SX126xCsPin = cs;
        SX126xResetPin = res;
        SX126xBusyPin = busy;
        SX126xDio1Pin = dio1;

        luat_gpio_mode(SX126xCsPin, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
        luat_gpio_mode(SX126xResetPin, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
        luat_gpio_mode(SX126xBusyPin, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
        luat_gpio_mode(SX126xDio1Pin, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);

        RadioEvents.TxDone = OnTxDone;
        RadioEvents.RxDone = OnRxDone;
        RadioEvents.TxTimeout = OnTxTimeout;
        RadioEvents.RxTimeout = OnRxTimeout;
        RadioEvents.RxError = OnRxError;

        RadioEventsInit(&RadioEvents);
        if (lora_init) Radio.Init( &RadioEvents );

        luat_start_rtos_timer(luat_create_rtos_timer(Radio.IrqProcess, NULL, NULL), 10, 1);
    }
    else {
        LLOGE("no such ic %s", lora_ic);
    }
    return 0;
}

/*
设置频道频率
@api    lora.set_channel(freq)
@number 频率
@usage
lora.set_channel(433000000)
*/
static int luat_lora_set_channel(lua_State *L){
    uint32_t freq = luaL_optinteger(L, 1,433000000);
    Radio.SetChannel(freq);
    return 0;
}

/*
lora配置发送参数
@api lora.set_txconfig(ic, txconfig)
@string lora 型号，当前支持：<br>llcc68<br>sx1268
@table lora发送配置参数,与具体设备有关
@usage
lora.set_txconfig("llcc68",
    {
        mode=1,
        power=22,
        fdev=0,
        bandwidth=0,
        datarate=9,
        coderate=4,
        preambleLen=8,
        fixLen=false,
        crcOn=true,
        freqHopOn=0,
        hopPeriod=0,
        iqInverted=false,
        timeout=3000
    }
)
*/
static int luat_lora_set_txconfig(lua_State *L){
    size_t len = 0;
    const char* lora_ic = luaL_checklstring(L, 1, &len);
    if(strcmp("llcc68",lora_ic)== 0||strcmp("LLCC68",lora_ic)== 0||strcmp("sx1268",lora_ic)== 0||strcmp("SX1268",lora_ic)== 0){
        uint8_t mode = 1,power = 0,fdev = 0,bandwidth = 0,datarate = 9,coderate = 4,preambleLen = 8,freqHopOn = 0,hopPeriod = 0;
        uint32_t timeout = 0;
        bool fixLen = false,crcOn = true,iqInverted = false,rateOptimize = false;

        if (lua_istable(L, 2)) {
            lua_pushstring(L, "mode");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                mode = luaL_optinteger(L, -1,1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "power");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                power = luaL_optinteger(L, -1,22);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "fdev");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                fdev = luaL_optinteger(L, -1,0);
            }
            lua_pop(L, 1);

            lua_pushstring(L, "bandwidth");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                bandwidth = luaL_optinteger(L, -1,0);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "datarate");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                datarate = luaL_optinteger(L, -1,9);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "coderate");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                coderate = luaL_optinteger(L, -1,4);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "preambleLen");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                preambleLen = luaL_optinteger(L, -1,8);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "fixLen");
            if (LUA_TBOOLEAN == lua_gettable(L, 2)) {
                fixLen = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "crcOn");
            if (LUA_TBOOLEAN == lua_gettable(L, 2)) {
                crcOn = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "freqHopOn");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                freqHopOn = luaL_optinteger(L, -1,0);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "hopPeriod");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                hopPeriod = luaL_optinteger(L, -1,0);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "iqInverted");
            if (LUA_TBOOLEAN == lua_gettable(L, 2)) {
                iqInverted = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "timeout");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                timeout = luaL_optinteger(L, -1,3000);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "rateOptimize");
            if (LUA_TBOOLEAN == lua_gettable(L, 2)) {
                rateOptimize = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
        }
        Radio.SetTxConfig( mode, power, fdev, bandwidth,
                            datarate, coderate,
                            preambleLen, fixLen,
                            crcOn, freqHopOn, hopPeriod, iqInverted, timeout ,rateOptimize);
    }
    else {
        LLOGE("no such ic %s", lora_ic);
    }
    return 0;
}

/*
lora配置接收参数
@api lora.set_rxconfig(ic, set_rxconfig)
@string lora 型号，当前支持：<br>llcc68<br>sx1268
@table lora接收配置参数,与具体设备有关
@usage
lora.set_rxconfig("llcc68",
    {
        mode=1,
        bandwidth=0,
        datarate=9,
        coderate=4,
        bandwidthAfc=0,
        preambleLen=8,
        symbTimeout=0,
        fixLen=false,
        payloadLen=0,
        crcOn=true,
        freqHopOn=0,
        hopPeriod=0,
        iqInverted=false,
        rxContinuous=false
    }
)
*/
static int luat_lora_set_rxconfig(lua_State *L){
    size_t len = 0;
    const char* lora_ic = luaL_checklstring(L, 1, &len);
    if(strcmp("llcc68",lora_ic)== 0||strcmp("LLCC68",lora_ic)== 0||strcmp("sx1268",lora_ic)== 0||strcmp("SX1268",lora_ic)== 0){
        uint8_t mode = 1,bandwidth = 0,datarate = 9,coderate = 4,bandwidthAfc = 0,preambleLen = 8,symbTimeout = 0,payloadLen = 0,freqHopOn = 0,hopPeriod = 0;
        uint32_t frequency = 433000000,timeout = 0;
        bool fixLen = false,crcOn = true,iqInverted = false,rxContinuous = false,rateOptimize = false;

        if (lua_istable(L, 2)) {
            lua_pushstring(L, "mode");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                mode = luaL_optinteger(L, -1,1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "bandwidth");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                bandwidth = luaL_optinteger(L, -1,0);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "datarate");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                datarate = luaL_optinteger(L, -1,9);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "coderate");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                coderate = luaL_optinteger(L, -1,4);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "bandwidthAfc");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                bandwidthAfc = luaL_optinteger(L, -1,0);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "preambleLen");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                preambleLen = luaL_optinteger(L, -1,8);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "symbTimeout");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                symbTimeout = luaL_optinteger(L, -1,0);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "fixLen");
            if (LUA_TBOOLEAN == lua_gettable(L, 2)) {
                fixLen = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "payloadLen");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                payloadLen = luaL_optinteger(L, -1,0);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "crcOn");
            if (LUA_TBOOLEAN == lua_gettable(L, 2)) {
                crcOn = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "freqHopOn");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                freqHopOn = luaL_optinteger(L, -1,0);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "hopPeriod");
            if (LUA_TNUMBER == lua_gettable(L, 2)) {
                hopPeriod = luaL_optinteger(L, -1,0);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "iqInverted");
            if (LUA_TBOOLEAN == lua_gettable(L, 2)) {
                iqInverted = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "rxContinuous");
            if (LUA_TBOOLEAN == lua_gettable(L, 2)) {
                rxContinuous = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
            lua_pushstring(L, "rateOptimize");
            if (LUA_TBOOLEAN == lua_gettable(L, 2)) {
                rateOptimize = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
        }

        Radio.SetRxConfig( mode, bandwidth, datarate,
                            coderate, bandwidthAfc, preambleLen,
                            symbTimeout, fixLen,
                            payloadLen, crcOn, freqHopOn, hopPeriod, iqInverted, rxContinuous ,rateOptimize);
    }
    else {
        LLOGE("no such ic %s", lora_ic);
    }
    return 0;
}

/*
发数据
@api    lora.send(data)
@string 写入的数据
@usage
lora.send("PING")
*/
static int luat_lora_send(lua_State *L){
    size_t len;
    const char* send_buff = luaL_checklstring(L, 1, &len);
    Radio.Standby();
    Radio.Send( send_buff, len);
    return 0;
}

/*
开启收数据
@api    lora.recv(timeout)
@number 超时时间，默认1000 单位ms
@usage
sys.subscribe("LORA_RX_DONE", function(data, size)
    log.info("LORA_RX_DONE: ", data, size)
    lora.send("PING")
end)
-- 老版本没有recv, 可以改成 lora.recive
lora.recv(1000)
*/
static int luat_lora_recive(lua_State *L){
    int rx_timeout = luaL_optinteger(L, 1, 1000);
    Radio.Standby();
    Radio.Rx(rx_timeout);
    return 0;
}

/*
设置进入模式(休眠，正常等)
@api    lora.mode(mode)
@number 模式 正常模式:lora.STANDBY 休眠模式:lora.SLEEP 默认为正常模式
@usage
lora.mode(lora.STANDBY)
*/
static int luat_lora_mode(lua_State *L){
    int mode = luaL_optinteger(L, 1, 1);
    if (mode == 1){
        Radio.Standby();
    }else if (mode == 0){
        Radio.Sleep();
    }
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_lora[] =
{
    { "init",        ROREG_FUNC(luat_lora_init)},
    { "set_channel", ROREG_FUNC(luat_lora_set_channel)},
    { "set_txconfig",ROREG_FUNC(luat_lora_set_txconfig)},
    { "set_rxconfig",ROREG_FUNC(luat_lora_set_rxconfig)},
    { "send",        ROREG_FUNC(luat_lora_send)},
    { "recv",        ROREG_FUNC(luat_lora_recive)},
    { "recive",      ROREG_FUNC(luat_lora_recive)},
    { "mode",        ROREG_FUNC(luat_lora_mode)},

    //@const SLEEP number SLEEP模式
    { "SLEEP",       ROREG_INT(0)},
    //@const STANDBY number STANDBY模式
    { "STANDBY",     ROREG_INT(1)},
	{ NULL,          ROREG_INT(0)}
};

LUAMOD_API int luaopen_lora( lua_State *L ) {
    luat_newlib2(L, reg_lora);
    return 1;
}
