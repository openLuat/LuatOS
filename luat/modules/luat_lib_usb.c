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
@int 设备类,从机模式支持usb.CDC_ACM,usb.HID,usb.MSC,usb.WINUSB,主机模式支持usb.CAMERA
@int 数量,目前只有从机的usb.CDC_ACM允许至多3个,其他只允许1个,超过时会强制改成所允许的最大值
@return bool 成功返回true,否则返回false,总线id填错,所选设备类不支持时,端点数量超过芯片允许的最大值,USB外设正在工作等情况下返回失败
@usage
pm.power(pm.USB, false)
usb.add_class(0, usb.CDC_ACM, 3)	--使用3个CDC-ACM虚拟串口功能
usb.add_class(0, usb.WINUSB, 1)		--使用1个WINUSB功能
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
usb.add_class(0, usb.WINUSB, 1)		--使用1个WINUSB功能
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

static const rotable_Reg_t reg_usb[] =
{
	{ "mode" ,         ROREG_FUNC(l_usb_mode)},
	{ "vid" ,         ROREG_FUNC(l_usb_vid)},
	{ "pid" ,         ROREG_FUNC(l_usb_pid)},
	{ "add_class" ,         ROREG_FUNC(l_usb_add_class)},
	{ "clear_all_class" ,         ROREG_FUNC(l_usb_clear_all_class)},
	{ "get_free_ep_num" ,         ROREG_FUNC(l_usb_get_free_ep_num)},
	//@const HOST number USB主机模式
    { "HOST",        ROREG_INT(LUAT_USB_MODE_HOST)},
	//@const DEVICE number USB从机模式
    { "DEVICE",       ROREG_INT(LUAT_USB_MODE_DEVICE)},
	//@const OTG number USB otg模式
    { "OTG",       ROREG_INT(LUAT_USB_MODE_OTG)},
	//@const CDC_ACM number cdc_acm 虚拟串口类
    { "CDC_ACM",        ROREG_INT(LUAT_USB_CLASS_CDC_ACM)},
	//@const AUDIO number audio音频类
    { "AUDIO",       ROREG_INT(LUAT_USB_CLASS_AUDIO)},
	//@const CAMERA number 摄像头类
    { "CAMERA",        ROREG_INT(LUAT_USB_CLASS_CAMERA)},
	//@const HID number HID设备类，只支持键盘和自定义
    { "HID",       ROREG_INT(LUAT_USB_CLASS_HIB)},
	//@const MSC number 大容量存储类，也就是U盘，TF卡
    { "MSC",       ROREG_INT(LUAT_USB_CLASS_MSC)},
	//@const WINUSB number WINUSB类，透传数据
    { "WINUSB",       ROREG_INT(LUAT_USB_CLASS_MSC)},

    { NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_usb( lua_State *L )
{
    luat_newlib2(L, reg_usb);
    return 1;
}
