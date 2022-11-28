/*
@module  usbapp
@summary USB功能操作
@version 1.0
@date    2022.01.17
@demo usb_hid
@tag LUAT_USE_USB
*/
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"

#define USB_ID0 0

enum
{
	USB_HID_NOT_READY,
	USB_HID_READY,
	USB_HID_SEND_DONE,
	USB_HID_NEW_DATA,
};

static int l_usb_app_vhid_cb(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    if (lua_isfunction(L, -1)) {
        lua_pushstring(L, "USB_HID_INC");
        lua_pushinteger(L, msg->arg1);
        lua_call(L, 2, 0);
    }
    return 0;
}

int32_t luat_usb_app_vhid_cb(void *pData, void *pParam)
{
    rtos_msg_t msg;
    msg.handler = l_usb_app_vhid_cb;
	switch((uint32_t)pParam)
	{
	case USB_HID_NOT_READY:
	case USB_HID_READY:
	case USB_HID_SEND_DONE:
	case USB_HID_NEW_DATA:
	    msg.arg1 = (uint32_t)pParam;
        luat_msgbus_put(&msg, 0);
		break;
	}
    return 0;
}
/*
USB 设置VID和PID
@api usbapp.set_id(id, vid, pid)
@int 设备id,默认为0
@int vid 小端格式
@int pid 小端格式
@usage
usbapp.set_id(0, 0x1234, 0x5678)
*/
static int l_usb_set_id(lua_State* L) {
    luat_usb_app_set_vid_pid(luaL_optinteger(L, 1, 0), luaL_optinteger(L, 2, 0x1234), luaL_optinteger(L, 3, 0x5678));
    return 0;
}

/*
USB HID设备模式
@api usbapp.hid_mode(id, mode, buff_size)
@int 设备id,默认为0
@int mode，目前0是键盘，1是自定义
@int buff_size，只能是8,16,32,64，如果是键盘模式或者填了其他值，自动为8
@usage
usbapp.hid_mode(0, 0) -- usb hid键盘模式
usbapp.hid_mode(0, 1) -- usb hid自定义模式，用于免驱USB交互
*/
static int l_usb_set_hid_mode(lua_State* L) {
	luat_usb_app_set_hid_mode(luaL_optinteger(L, 1, 0), luaL_optinteger(L, 2, 0), luaL_optinteger(L, 3, 8));
	return 0;
}

/*
启动USB设备
@api usbapp.start(id)
@int 设备id,默认为0
@return bool 成功返回true,否则返回false
@usage
-- 启动USB
usbapp.start(0)
*/
static int l_usb_start(lua_State* L) {
    luat_usb_app_start(USB_ID0);
    lua_pushboolean(L, 1);
    return 1;
}

/*
关闭USB设备
@api usbapp.stop(id)
@int 设备id,默认为0
@return bool 成功返回true,否则返回false
@usage
-- 关闭USB
usbapp.stop(0)
*/
static int l_usb_stop(lua_State* L) {
    luat_usb_app_stop(USB_ID0);
    lua_pushboolean(L, 1);
    return 1;
}

/*
USB HID设备上传数据
@api usbapp.vhid_upload(id, data)
@int 设备id,默认为0
@string 数据. 注意, HID的可用字符是有限制的, 基本上只有可见字符是支持的, 不支持的字符会替换为空格.
@return bool 成功返回true,否则返回false
@usage
-- HID上传数据
usbapp.vhid_upload(0, "1234") -- usb hid会模拟敲出1234
*/
static int l_usb_vhid_upload(lua_State* L) {
    size_t len;
    const char* data = luaL_checklstring(L, 2, &len);
    if (len > 0) {
        luat_usb_app_vhid_upload(USB_ID0, data, len);
        lua_pushboolean(L, 1);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

/*
USB HID设备上传用户自定义数据
@api usbapp.hid_tx(id, data, start, len)
@int 设备id,默认为0
@string or zbuff 注意数据量不足时会自动填充0
@int 可选，data为zbuff才有效，要发送的数据起始位置，默认为0
@int 可选，data为zbuff才有效，要发送的数据长度，默认为zbuff内有效数据，最大值不超过zbuff的最大空间
@return bool 成功返回true,否则返回false
@usage
-- HID上传数据
usbapp.hid_tx(0, "1234") -- usb hid上传0x31 0x32 0x33 0x34  + N个0
*/
static int l_usb_hid_tx(lua_State* L) {
    size_t start, len;
    const char *buf;
    luat_zbuff_t *buff = NULL;
    if(lua_isuserdata(L, 2)) {
        buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        start = luaL_optinteger(L, 3, 0);
        len = luaL_optinteger(L, 4, buff->used);
        if (start >= buff->len) {
        	lua_pushboolean(L, 0);
        	return 1;
        }
        if ((start + len)>= buff->len) {
        	len = buff->len - start;
        }
        if (len > 0) {
        	luat_usb_app_vhid_tx(USB_ID0, buff->addr + start, len);
            lua_pushboolean(L, 1);
        }
        else {
            lua_pushboolean(L, 0);
        }
    } else {
    	buf = luaL_checklstring(L, 2, &len);
    	luat_usb_app_vhid_tx(USB_ID0, buf, len);
        lua_pushboolean(L, 1);
    }
    return 1;
}

/*
buff形式读接收到的数据，一次读出全部数据存入buff中，如果buff空间不够会自动扩展，目前只有air105支持这个操作
@api    usbapp.hid_rx(id, buff)
@int 设备id,默认为0
@zbuff zbuff对象
@return int 返回读到的长度，并把zbuff指针后移
@usage
usbapp.hid_rx(0, buff)
*/
static int l_usb_hid_rx(lua_State *L)
{
    uint8_t id = luaL_checkinteger(L, 1);

    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
    	luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        int result = luat_usb_app_vhid_rx(id, NULL, 0);	//读出当前缓存的长度，目前只有105支持这个操作
        if (result > (buff->len - buff->used))
        {
        	__zbuff_resize(buff, buff->len + result);
        }
        luat_usb_app_vhid_rx(id, buff->addr + buff->used, result);
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
USB HID设备取消上传数据
@api usbapp.vhid_cancel_upload(id)
@int 设备id,默认为0
@return nil 无返回值
@usage
-- 取消上传数据,通常不需要
usbapp.vhid_cancel_upload(0)
*/
static int l_usb_vhid_cancel_upload(lua_State* L) {
    luat_usb_app_vhid_cancel_upload(USB_ID0);
    return 0;
}

/*
USB U盘设备挂载SDHC，TF卡
@api usbapp.udisk_attach_sdhc(id)
@int 设备id,默认为0
@return nil 无返回值
@usage
usbapp.udisk_attach_sdhc(0)
*/
static int l_usb_udisk_attach_sdhc(lua_State* L) {
	luat_usb_udisk_attach_sdhc(USB_ID0);
    return 0;
}

/*
USB U盘设备去除挂载SDHC，TF卡
@api usbapp.udisk_detach_sdhc(id)
@int 设备id,默认为0
@return nil 无返回值
@usage
usbapp.udisk_detach_sdhc(0)
*/
static int l_usb_udisk_detach_sdhc(lua_State* L) {
	luat_usb_udisk_detach_sdhc(USB_ID0);
    return 0;
}


#include "rotable2.h"
static const rotable_Reg_t reg_usbapp[] =
{
	{ "set_id" ,         ROREG_FUNC(l_usb_set_id)},
	{ "hid_mode" ,         ROREG_FUNC(l_usb_set_hid_mode)},
    { "start" ,         ROREG_FUNC(l_usb_start)},
    { "stop" ,       ROREG_FUNC(l_usb_stop)},
	{ "hid_tx", ROREG_FUNC(l_usb_hid_tx)},
	{ "hid_rx", ROREG_FUNC(l_usb_hid_rx)},
    { "vhid_upload",        ROREG_FUNC(l_usb_vhid_upload)},
    { "vhid_cancel_upload", ROREG_FUNC(l_usb_vhid_cancel_upload)},
	{ "udisk_attach_sdhc", ROREG_FUNC(l_usb_udisk_attach_sdhc)},
	{ "udisk_detach_sdhc", ROREG_FUNC(l_usb_udisk_detach_sdhc)},
    //@const NO_READY number NO_READY事件
    { "NO_READY",      ROREG_INT(USB_HID_NOT_READY)},
    //@const READY number READY事件
    { "READY",         ROREG_INT(USB_HID_READY)},
    //@const SEND_OK number SEND_OK事件
    { "SEND_OK",      ROREG_INT(USB_HID_SEND_DONE)},
    //@const NEW_DATA number NEW_DATA事件
	{ "NEW_DATA",      ROREG_INT(USB_HID_NEW_DATA)},
	{ NULL,            ROREG_INT(0)},
};

LUAMOD_API int luaopen_usbapp( lua_State *L ) {
	luat_newlib2(L, reg_usbapp);
    return 1;
}
