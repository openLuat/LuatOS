/*
@module  lora2
@summary lora2驱动模块(支持多挂)
@version 1.0
@date    2022.06.24
@demo lora
@tag LUAT_USE_LORA2
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

enum{
LORA_TX_DONE,
LORA_RX_DONE,
LORA_TX_TIMEOUT,
LORA_RX_TIMEOUT,
LORA_RX_ERROR,
};

#define LUAT_LORA_TYPE "LORA*"

static lora_device_t * get_lora_device(lua_State *L){
	if (luaL_testudata(L, 1, LUAT_LORA_TYPE)){
		return ((lora_device_t *)luaL_checkudata(L, 1, LUAT_LORA_TYPE));
	}else{
		return ((lora_device_t *)lua_touserdata(L, 1));
	}
}

typedef struct lora_data{
    uint16_t size;
    uint8_t payload[];
}lora_data_t;

static int l_lora_handler(lua_State* L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lora_device_t *lora_device =(lora_device_t *)msg->ptr;
    int event = msg->arg1;

    lua_geti(L, LUA_REGISTRYINDEX, lora_device->lora_cb);
    if (lua_isfunction(L, -1)) {
        lua_geti(L, LUA_REGISTRYINDEX, lora_device->lora_ref);
        switch (event){
            case LORA_TX_DONE:
                lua_pushstring(L, "tx_done");
                lua_call(L, 2, 0);
                break;
            case LORA_RX_DONE:
                lua_pushstring(L, "rx_done");
                lora_data_t* rx_buff = (lora_data_t*)msg->arg2;
                lua_pushlstring(L, rx_buff->payload,rx_buff->size);
                lua_pushinteger(L, rx_buff->size);
                lua_call(L, 4, 0);
                luat_heap_free(rx_buff);
                break;
            case LORA_TX_TIMEOUT:
                lua_pushstring(L, "tx_timeout");
                lua_call(L, 2, 0);
                break;
            case LORA_RX_TIMEOUT:
                lua_pushstring(L, "rx_timeout");
                lua_call(L, 2, 0);
                break;
            case LORA_RX_ERROR:
                lua_pushstring(L, "rx_error");
                lua_call(L, 2, 0);
                break;
        }
    }
    return 0;
}

static void OnTxDone( lora_device_t* lora_device ){
    rtos_msg_t msg = {0};
    msg.handler = l_lora_handler;
    msg.ptr = lora_device;
    msg.arg1 = LORA_TX_DONE;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 1);
}

static void OnRxDone( lora_device_t* lora_device,uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr ){
    // LLOGD("RxDone size:%d rssi:%d snr:%d",size,rssi,snr);
    // LLOGD("RxDone payload: %.*s",size,payload);
    lora_data_t* rx_buff = luat_heap_malloc(sizeof(lora_data_t)+ size);
    rx_buff->size = size;
    memcpy( rx_buff->payload, payload, size );

    rtos_msg_t msg = {0};
    msg.handler = l_lora_handler;
    msg.ptr = lora_device;
    msg.arg1 = LORA_RX_DONE;
    msg.arg2 = rx_buff;
    luat_msgbus_put(&msg, 1);
}

static void OnTxTimeout( lora_device_t* lora_device ){
    rtos_msg_t msg = {0};
    msg.handler = l_lora_handler;
    msg.ptr = lora_device;
    msg.arg1 = LORA_TX_TIMEOUT;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 1);
}

static void OnRxTimeout( lora_device_t* lora_device ){
    rtos_msg_t msg = {0};
    msg.handler = l_lora_handler;
    msg.ptr = lora_device;
    msg.arg1 = LORA_RX_TIMEOUT;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 1);
}

static void OnRxError( lora_device_t* lora_device ){
    rtos_msg_t msg = {0};
    msg.handler = l_lora_handler;
    msg.ptr = lora_device;
    msg.arg1 = LORA_RX_ERROR;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 1);
}

#define META_SPI "SPI*"
/*
lora初始化
@api lora2.init(ic, loraconfig,spiconfig)
@string lora 型号，当前支持：<br>llcc68<br>sx1268
@table lora配置参数,与具体设备有关
@return userdata 若成功会返回lora对象,否则返回nil
@usage
spi_lora = spi.deviceSetup(spi_id,pin_cs,0,0,8,10*1000*1000,spi.MSB,1,0)
lora_device = lora2.init("llcc68",{res = pin_reset,busy = pin_busy,dio1 = pin_dio1},spi_lora)
*/
static int luat_lora_init(lua_State *L){
    size_t len = 0;
    const char* lora_ic = luaL_checklstring(L, 1, &len);
    if(strcmp("llcc68",lora_ic)== 0||strcmp("LLCC68",lora_ic)== 0||strcmp("sx1268",lora_ic)== 0||strcmp("SX1268",lora_ic)== 0){

        lora_device_t *lora_device = (lora_device_t *)lua_newuserdata(L, sizeof(lora_device_t));
        if (!lora_device){
            LLOGE("out of memory when malloc lora_device");
            return 0;
        }
        RadioEvents_t RadioEvents;
        uint8_t id = 0,cs = 0,res = 0,busy = 0,dio1 = 0;
        lora_device->lora_init = true;
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
                lora_device->lora_init = lua_toboolean(L, -1);
            }
            lua_pop(L, 1);
        }

        if (luaL_testudata(L, 3, META_SPI)){
            lora_device->lora_spi_id = 255;
            lora_device->lora_spi_device = (luat_spi_device_t*)lua_touserdata(L, 3);
        }else{
            lora_device->lora_spi_id = id;
            lora_device->lora_pin_cs = cs;
            luat_gpio_mode(lora_device->lora_pin_cs, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
        }

        lora_device->lora_pin_rst = res;
        lora_device->lora_pin_busy = busy;
        lora_device->lora_pin_dio1 = dio1;

        luat_gpio_mode(lora_device->lora_pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_PULLUP, Luat_GPIO_HIGH);
        luat_gpio_mode(lora_device->lora_pin_busy, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);
        luat_gpio_mode(lora_device->lora_pin_dio1, Luat_GPIO_INPUT, Luat_GPIO_PULLUP, Luat_GPIO_LOW);

        RadioEvents.TxDone = OnTxDone;
        RadioEvents.RxDone = OnRxDone;
        RadioEvents.TxTimeout = OnTxTimeout;
        RadioEvents.RxTimeout = OnRxTimeout;
        RadioEvents.RxError = OnRxError;
        RadioEventsInit2(lora_device,&RadioEvents);
        if (lora_device->lora_init) Radio2.Init( lora_device,&RadioEvents );

        luat_rtos_timer_create(&lora_device->timer);
        luat_rtos_timer_start(lora_device->timer, 10, 1, Radio2.IrqProcess, lora_device);

        luaL_setmetatable(L, LUAT_LORA_TYPE);
        lua_pushvalue(L, -1);
        lora_device->lora_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        return 1;
    }
    else {
        LLOGE("no such ic %s", lora_ic);
    }
    return 0;
}

/*
设置频道频率
@api    lora_device:set_channel(freq)
@number 频率
@usage
lora_device:set_channel(433000000)
*/
static int luat_lora_set_channel(lua_State *L){
    lora_device_t  * lora_device = get_lora_device(L);
    uint32_t freq = luaL_optinteger(L, 2,433000000);
    Radio2.SetChannel(lora_device,freq);
    return 0;
}

/*
lora配置发送参数
@api lora_device:set_txconfig(txconfig)
@table lora发送配置参数,与具体设备有关
@usage
lora_device:set_txconfig(
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
    uint8_t mode = 1,power = 0,fdev = 0,bandwidth = 0,datarate = 9,coderate = 4,preambleLen = 8,freqHopOn = 0,hopPeriod = 0;
    uint32_t timeout = 0;
    bool fixLen = false,crcOn = true,iqInverted = false,rateOptimize = false;
    lora_device_t  * lora_device = get_lora_device(L);

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
    
    Radio2.SetTxConfig( lora_device,mode, power, fdev, bandwidth,
                        datarate, coderate,
                        preambleLen, fixLen,
                        crcOn, freqHopOn, hopPeriod, iqInverted, timeout ,rateOptimize);

    return 0;
}

/*
lora配置接收参数
@api lora_device:set_rxconfig(set_rxconfig)
@table lora接收配置参数,与具体设备有关
@usage
lora_device:set_rxconfig(
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
    uint8_t mode = 1,bandwidth = 0,datarate = 9,coderate = 4,bandwidthAfc = 0,preambleLen = 8,symbTimeout = 0,payloadLen = 0,freqHopOn = 0,hopPeriod = 0;
    uint32_t frequency = 433000000,timeout = 0;
    bool fixLen = false,crcOn = true,iqInverted = false,rxContinuous = false,rateOptimize = false;
    lora_device_t  * lora_device = get_lora_device(L);
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

    Radio2.SetRxConfig( lora_device,mode, bandwidth, datarate,
                        coderate, bandwidthAfc, preambleLen,
                        symbTimeout, fixLen,
                        payloadLen, crcOn, freqHopOn, hopPeriod, iqInverted, rxContinuous ,rateOptimize);

    return 0;
}

/*
发数据
@api    lora_device:send(data)
@string 写入的数据
@usage
lora_device:send("PING")
*/
static int luat_lora_send(lua_State *L){
    lora_device_t  * lora_device = get_lora_device(L);
    size_t len;
    const char* send_buff = luaL_checklstring(L, 2, &len);
    Radio2.Standby(lora_device);
    Radio2.Send( lora_device,send_buff, len);
    return 0;
}

/*
开启收数据
@api    lora_device:recv(timeout)
@number 超时时间，默认1000 单位ms
@usage
sys.subscribe("LORA_RX_DONE", function(data, size)
    log.info("LORA_RX_DONE: ", data, size)
    lora_device:send("PING")
end)
lora_device:recv(1000)
*/
static int luat_lora_recv(lua_State *L){
    lora_device_t  * lora_device = get_lora_device(L);
    int rx_timeout = luaL_optinteger(L, 2, 1000);
    Radio2.Standby(lora_device);
    Radio2.Rx(lora_device,rx_timeout);
    return 0;
}

/*
设置进入模式(休眠，正常等)
@api    lora_device:mode(mode)
@number 模式 正常模式:lora.STANDBY 休眠模式:lora.SLEEP 默认为正常模式
@usage
lora_device:mode(lora.STANDBY)
*/
static int luat_lora_mode(lua_State *L){
    lora_device_t  * lora_device = get_lora_device(L);
    int mode = luaL_optinteger(L, 2, 1);
    if (mode == 1){
        Radio2.Standby(lora_device);
    }else if (mode == 0){
        Radio2.Sleep(lora_device);
    }
    return 0;
}

/*
注册lora回调
@api lora_device:on(cb)
@function cb lora回调,参数包括lora_device, event, data, size
@return nil 无返回值
@usage 
lora_device:on(function(lora_device, event, data, size)
    log.info("lora", "event", event, lora_device, data, size)
    if event == "tx_done" then
        lora_device:recv(1000)
    elseif event == "rx_done" then
        lora_device:send("PING")
    elseif event == "tx_timeout" then

    elseif event == "rx_timeout" then
        lora_device:recv(1000)
    elseif event == "rx_error" then

    end
end)
--[[
event可能出现的值有
    tx_done         -- 发送完成
    rx_done         -- 接收完成
    tx_timeout      -- 发送超时
    rx_timeout      -- 接收超时
    rx_error        -- 接收错误
]]
*/
static int luat_lora_on(lua_State *L){
    lora_device_t *lora_device = get_lora_device(L);
	if (lora_device->lora_cb != 0) {
		luaL_unref(L, LUA_REGISTRYINDEX, lora_device->lora_cb);
		lora_device->lora_cb = 0;
	}
	if (lua_isfunction(L, 2)) {
		lua_pushvalue(L, 2);
		lora_device->lora_cb = luaL_ref(L, LUA_REGISTRYINDEX);
	}
	return 0;
}

static int _lora_struct_newindex(lua_State *L);

void luat_lora_struct_init(lua_State *L) {
    luaL_newmetatable(L, LUAT_LORA_TYPE);
    lua_pushcfunction(L, _lora_struct_newindex);
    lua_setfield( L, -2, "__index" );
    lua_pop(L, 1);
}

#include "rotable2.h"
static const rotable_Reg_t reg_lora[] =
{
    { "init",        ROREG_FUNC(luat_lora_init)},
    { "set_channel", ROREG_FUNC(luat_lora_set_channel)},
    { "set_txconfig",ROREG_FUNC(luat_lora_set_txconfig)},
    { "set_rxconfig",ROREG_FUNC(luat_lora_set_rxconfig)},
    { "on",          ROREG_FUNC(luat_lora_on)},
    { "send",        ROREG_FUNC(luat_lora_send)},
    { "recv",        ROREG_FUNC(luat_lora_recv)},
    { "mode",        ROREG_FUNC(luat_lora_mode)},

    //@const SLEEP number SLEEP模式
    { "SLEEP",       ROREG_INT(0)},
    //@const STANDBY number STANDBY模式
    { "STANDBY",     ROREG_INT(1)},
	{ NULL,          ROREG_INT(0)}
};

static int _lora_struct_newindex(lua_State *L) {
	const rotable_Reg_t* reg = reg_lora;
    const char* key = luaL_checkstring(L, 2);
	while (1) {
		if (reg->name == NULL)
			return 0;
		if (!strcmp(reg->name, key)) {
			lua_pushcfunction(L, reg->value.value.func);
			return 1;
		}
		reg ++;
	}
}

LUAMOD_API int luaopen_lora2( lua_State *L ) {
    luat_newlib2(L, reg_lora);
    luat_lora_struct_init(L);
    return 1;
}
