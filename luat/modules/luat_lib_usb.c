/*
@module  usb
@summary usb操作库
@version 1.0
@date    2025.12.15
@demo usb
@tag LUAT_USE_USB
@usage
--[[
--简单举例
pm.power(pm.USB, false)		--确保USB外设是掉电状态
--usb.vid(0, 0x1234)		--配置VID,不是必须的
--usb.pvid(0, 0x5678)		--配置PID,不是必须的
usb.clear_all_class(0)				--清除掉之前配置的设备类
usb.mode(0, usb.DEVICE)		--usb设置成从机模式
usb.add_class(0, usb.CDC_ACM, 1)	--使用1个CDC-ACM虚拟串口功能
usb.add_class(0, usb.WINUSB, 1)		--使用1个WINUSB功能
pm.power(pm.USB, true)		--USB上电初始化开始工作
--说明
目前设备类只有usb.HID和usb.WINUSB可以通过usb操作库api和对端通讯,usb.CDC-ACM虚拟串口直接使用uart api
]]
*/
#include "luat_base.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_usb.h"
#include "luat_zbuff.h"
#define LUAT_LOG_TAG "usb"
#include "luat_log.h"
#include "rotable2.h"


static int l_usb_cb[MAX_USB_DEVICE_COUNT];

int l_usb_handler(lua_State *L, void* ptr) {
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    int usb_id = msg->arg1 & 0x000000ff;
    int class_id = (msg->arg1 & 0x0000ff00) >> 8;
    if (l_usb_cb[usb_id] && usb_id < MAX_USB_DEVICE_COUNT)
    {
        lua_geti(L, LUA_REGISTRYINDEX, l_usb_cb[usb_id]);
        lua_pushinteger(L, usb_id);
        lua_pushinteger(L, msg->arg2);
        if (class_id != 0x000000ff)
        {
        	lua_pushinteger(L, class_id);
        }
        else
        {
        	lua_pushnil(L);
        }
        lua_call(L, 3, 0);
    }
    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}


/*
USB发送数据,目前仅限于HID设备,CDC-ACM虚拟串口直接使用串口API操作
@api usb.tx(id, data, class)
@int 设备id,默认为0
@zbuff or string 需要发送的数据
@int 设备类
@return bool 成功返回true,否则返回false,总线id填错,所填设备类不支持直接发送数据等情况下返回错误
@usage
-- HID上传数据
usb.tx(0, "1234", usb.HID_KB) -- usb hid上传0x31 0x32 0x33 0x34  + N个0
*/
static int l_usb_tx(lua_State* L) {
	int result;
    uint8_t class = luaL_optinteger(L, 3, LUAT_USB_CLASS_HID_CUSTOMER);
    int usb_id = luaL_optinteger(L, 1, 0);
    const char *buf;
    luat_zbuff_t *buff = NULL;
    if(lua_isuserdata(L, 2)) {
        buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        result = luat_usb_tx(usb_id, class, buff->addr, buff->used);
    } else {
    	size_t len;
    	buf = luaL_checklstring(L, 2, &len);
    	switch(class)
    	{
    	case LUAT_USB_CLASS_HID_CUSTOMER:
    		result = luat_usb_hid_tx(usb_id, buf, len, 0);
    		break;
    	case LUAT_USB_CLASS_HID_KEYBOARD:
    		result = luat_usb_hid_tx(usb_id, buf, len, 1);
    		break;
    	default:
    		result = luat_usb_tx(usb_id, class, buf, len);
    		break;
    	}
        lua_pushboolean(L, !result);
    }
    return 1;
}

/*
buff形式读接收到的数据，一次读出全部数据存入buff中，如果buff空间不够会自动扩展
@api usb.rx(id, buff, class)
@int 设备id,默认为0
@zbuff zbuff对象
@int 设备类
@return int 返回读到的长度，并把zbuff指针后移
@usage
usb.rx(0, buff, usb.HID_CM)
*/
static int l_usb_rx(lua_State *L)
{
    uint8_t class = luaL_optinteger(L, 3, LUAT_USB_CLASS_HID_CUSTOMER);
    int usb_id = luaL_optinteger(L, 1, 0);

    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
    	luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        int result = luat_usb_rx(usb_id, class, NULL, 0);	//读出当前缓存的长度
        if (result > (buff->len - buff->used))
        {
        	__zbuff_resize(buff, buff->len + result);
        }
        result = luat_usb_rx(usb_id, class, buff->addr + buff->used, result);
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
设置USB工作模式，必须在USB外设掉电不工作时进行设置
@api usb.mode(id, mode)
@int usb总线id,默认0,如果芯片只有1条USB线,填0
@int 工作模式,只有3种,usb.HOST主机模式,usb.DEVICE从机模式,usb.OTG协商模式,默认是从机模式
@return bool 成功返回true,否则返回false,总线id填错,所选模式不支持时,USB外设正在工作等情况下返回失败
@usage
pm.power(pm.USB, false)
usb.mode(0, usb.DEVICE)
pm.power(pm.USB, true)
*/
static int l_usb_mode(lua_State* L) {
	int result = luat_usb_set_mode(luaL_optinteger(L, 1, 0), luaL_optinteger(L, 2, LUAT_USB_MODE_DEVICE));
	lua_pushboolean(L, !result);
    return 1;
}

/*
注册USB事件回调
@api usb.on(id, func)
@int usb总线id,默认0,如果芯片只有1条USB线,填0
@function 回调方法
@return nil 无返回值
@usage
usb.on(0, function(id, class, event)
    log.info("usb", id, class, event)
end)
--回调参数有3个
1、usb总线id
2、event,见usb.EV_XXX
3、如果event是usb.EV_RX或usb.EV_TX,则第三个参数表示哪个设备类,目前只有usb.HID和usb.WINUSB
*/
static int l_usb_on(lua_State *L) {
    int usb_id = luaL_optinteger(L, 1, 0);
    if (usb_id >= MAX_USB_DEVICE_COUNT) return 0;
    if (l_usb_cb[usb_id])
    {
    	luaL_unref(L, LUA_REGISTRYINDEX, l_usb_cb[usb_id]);
    }
	if (lua_isfunction(L, 2)) {
		lua_pushvalue(L, 2);
		l_usb_cb[usb_id] = luaL_ref(L, LUA_REGISTRYINDEX);
	}
    return 0;
}



/*
设置/获取USB的VID,必须在USB外设掉电不工作时进行设置,获取没有限制
@api usb.vid(id, vid)
@int usb总线id,默认0,如果芯片只有1条USB线,填0
@int 想要设置的VID值,留空则不做设置
@return bool 成功或者获取VID时返回true,否则返回false,总线id填错,芯片不支持设置,USB外设正在工作等情况下返回失败
@return int 当前VID值
@usage
pm.power(pm.USB, false)
usb.vid(0, 0x1234)
pm.power(pm.USB, true)
*/
static int l_usb_vid(lua_State* L) {
	int result1 = 0;
	int result2 = -1;
	int bus_id = luaL_optinteger(L, 1, 0);
	uint16_t vid;
	if (lua_isinteger(L, 2))
	{
		result1 = luat_usb_set_vid(bus_id, lua_tointeger(L, 2));
	}
	result2 = luat_usb_get_vid(bus_id, &vid);

	lua_pushboolean(L, !(result1 || result2));
	lua_pushinteger(L, vid);
    return 2;
}

/*
设置/获取USB的PID,必须在USB外设掉电不工作时进行设置,获取没有限制
@api usb.pid(id, pid)
@int usb总线id,默认0,如果芯片只有1条USB线,填0
@int 想要设置的PID值,留空则不做设置
@return bool 成功或者获取VID时返回true,否则返回false,总线id填错,芯片不支持设置,USB外设正在工作等情况下返回失败
@return int 当前PID值
@usage
pm.power(pm.USB, false)
usb.pid(0, 0x1234)
pm.power(pm.USB, true)
*/
static int l_usb_pid(lua_State* L) {
	int result1 = 0;
	int result2 = -1;
	int bus_id = luaL_optinteger(L, 1, 0);
	uint16_t pid;
	if (lua_isinteger(L, 2))
	{
		result1 = luat_usb_set_pid(bus_id, lua_tointeger(L, 2));
	}
	result2 = luat_usb_get_pid(bus_id, &pid);

	lua_pushboolean(L, !(result1 || result2));
	lua_pushinteger(L, pid);
    return 2;
}

/*
设置USB支持的设备类和数量，必须在USB外设掉电不工作时进行设置
@api usb.add_class(id, class, num)
@int usb总线id,默认0,如果芯片只有1条USB线,填0
@int 设备类,从机模式支持usb.CDC_ACM,usb.HID_CM,usb.HID_KB,usb.MSC,主机模式不需要配置
@int 数量,目前只有从机的usb.CDC_ACM允许至多3个,其他只允许1个,超过时会强制改成所允许的最大值
@return bool 成功返回true,否则返回false,总线id填错,所选设备类不支持时,端点数量超过芯片允许的最大值,USB外设正在工作等情况下返回失败
@usage
pm.power(pm.USB, false)
usb.add_class(0, usb.CDC_ACM, 3)	--使用3个CDC-ACM虚拟串口功能
usb.add_class(0, usb.HID_CM, 1)		--使用1个自定义HID功能
pm.power(pm.USB, true)
*/
static int l_usb_add_class(lua_State* L) {
	int result = luat_usb_add_class(luaL_optinteger(L, 1, 0), luaL_optinteger(L, 2, LUAT_USB_CLASS_CDC_ACM), luaL_optinteger(L, 3, 1));
	lua_pushboolean(L, !result);
    return 1;
}

/*
清除掉当前配置的设备类,必须在USB外设掉电不工作时进行设置
@api usb.clear_all_class(id)
@int usb总线id,默认0,如果芯片只有1条USB线,填0
@return bool 成功返回true,否则返回false,总线id填错,USB外设正在工作等情况下返回失败
@usage
pm.power(pm.USB, false)
usb.clear_all_class(0)				--清除掉之前配置的设备类
usb.add_class(0, usb.CDC_ACM, 3)	--使用3个CDC-ACM虚拟串口功能
usb.add_class(0, usb.HID_KB, 1)		--使用1个标准键盘功能
pm.power(pm.USB, true)
*/
static int l_usb_clear_all_class(lua_State* L) {
	int result = luat_usb_clear_class(luaL_optinteger(L, 1, 0));
	lua_pushboolean(L, !result);
    return 1;
}

/*
返回当前剩余的端点数
@api usb.get_free_ep_num(id)
@int usb总线id,默认0,如果芯片只有1条USB线,填0
@return int 剩余的端点数,总线id填错时直接返回0
@usage
log.info(usb.get_free_ep_num(0))
*/
static int l_usb_get_free_ep_num(lua_State* L) {
	int result = luat_usb_get_free_ep_num(luaL_optinteger(L, 1, 0));
	if (result < 0)
	{
		lua_pushinteger(L, 0);
	}
	else
	{
		lua_pushinteger(L, result);
	}
    return 1;
}

/*
配置调试信息输出开关
@api usb.debug(id, on_off)
@int usb总线id,默认0,如果芯片只有1条USB线,填0
@boolean true开 false关
@return
@usage
usb.debug(0,true)	--开启调试信息输出
usb.debug(0,false)	--关闭调试信息输出
*/
static int l_usb_set_debug(lua_State* L) {
	luat_usb_debug(luaL_optinteger(L, 1, 0), lua_toboolean(L, 2));
    return 0;
}

static const rotable_Reg_t reg_usb[] =
{
	{ "tx",					ROREG_FUNC(l_usb_tx)},
	{ "rx",					ROREG_FUNC(l_usb_rx)},
	{ "mode",				ROREG_FUNC(l_usb_mode)},
	{ "add_class",      	ROREG_FUNC(l_usb_add_class)},
	{ "on",         		ROREG_FUNC(l_usb_on)},
	{ "vid",         		ROREG_FUNC(l_usb_vid)},
	{ "pid",         		ROREG_FUNC(l_usb_pid)},
	{ "clear_all_class" ,   ROREG_FUNC(l_usb_clear_all_class)},
	{ "get_free_ep_num" ,   ROREG_FUNC(l_usb_get_free_ep_num)},
	{ "debug",         		ROREG_FUNC(l_usb_set_debug)},
	//@const HOST number USB主机模式
    { "HOST",        		ROREG_INT(LUAT_USB_MODE_HOST)},
	//@const DEVICE number USB从机模式
    { "DEVICE",       		ROREG_INT(LUAT_USB_MODE_DEVICE)},
	//@const OTG number USB otg模式
    { "OTG",       			ROREG_INT(LUAT_USB_MODE_OTG)},
	//@const CDC_ACM number cdc_acm 虚拟串口类
    { "CDC_ACM",        	ROREG_INT(LUAT_USB_CLASS_CDC_ACM)},
	//@const AUDIO number audio音频类
    { "AUDIO",       		ROREG_INT(LUAT_USB_CLASS_AUDIO)},
	//@const CAMERA number 摄像头类
    { "CAMERA",        		ROREG_INT(LUAT_USB_CLASS_CAMERA)},
	//@const HID_CM number HID设备类，自定义类型，用于透传数据，不能和标准键盘同时使用
    { "HID_CM",       			ROREG_INT(LUAT_USB_CLASS_HID_CUSTOMER)},
	//@const HID_KB number HID设备类，标准键盘，常见扫码枪，不能和自定义类型同时使用
    { "HID_KB",       			ROREG_INT(LUAT_USB_CLASS_HID_KEYBOARD)},
	//@const MSC number 大容量存储类，也就是U盘，TF卡
    { "MSC",       			ROREG_INT(LUAT_USB_CLASS_MSC)},


	//@const EV_RX number  有新的数据到来
    { "EV_RX",       		ROREG_INT(LUAT_USB_EVENT_NEW_RX)},
	//@const EV_TX number 所有数据都已发送
    { "EV_TX",        		ROREG_INT(LUAT_USB_EVENT_TX_DONE)},
	//@const EV_CONNECT number usb从机已经连接上并且枚举成功
    { "EV_CONNECT",       	ROREG_INT(LUAT_USB_EVENT_CONNECT)},
	//@const EV_DISCONNECT number usb从机断开
    { "EV_DISCONNECT",      ROREG_INT(LUAT_USB_EVENT_DISCONNECT)},
	//@const EV_SUSPEND number usb从机挂起
    { "EV_SUSPEND",       	ROREG_INT(LUAT_USB_EVENT_SUSPEND)},
	//@const EV_RESUME number usb从机恢复
    { "EV_RESUME",       	ROREG_INT(LUAT_USB_EVENT_RESUME)},
    { NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_usb( lua_State *L )
{
    luat_newlib2(L, reg_usb);
    return 1;
}
