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
--从机功能
pm.power(pm.USB, false)		--确保USB外设是掉电状态
--usb.vid(0, 0x1234)		--配置VID,不是必须的
--usb.pid(0, 0x5678)		--配置PID,不是必须的
usb.clear_all_class(0)				--清除掉之前配置的设备类
usb.mode(0, usb.DEVICE)		--usb设置成从机模式
usb.add_class(0, usb.CDC_ACM, 1)	--使用1个CDC-ACM虚拟串口功能
pm.power(pm.USB, true)		--USB上电初始化开始工作

--主机功能
pm.power(pm.USB, false)		--确保USB外设是掉电状态
usb.mode(0, usb.HOST)		--usb设置成主机模式
pm.power(pm.USB, true)		--USB上电初始化开始工作
--说明
目前设备类只有usb.HID可以通过usb操作库api和对端通讯,usb.CDC-ACM虚拟串口直接使用uart api
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

#ifdef LUAT_USE_USB
#if defined(LUAT_USE_USB_HID_LUA) && defined(LUAT_USE_INPUT_HID)
#include "luat_input_service.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include <string.h>
#endif
static int l_usb_cb[MAX_USB_BUS_COUNT];


int l_usb_handler(lua_State *L, void* ptr) {
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);
    usb_event_u u_event;
    usb_info_u u_info;
    u_event.u32 = msg->arg1;
    u_info.u32 = msg->arg2;
    if (l_usb_cb[u_event.usb_id] && u_event.usb_id < MAX_USB_BUS_COUNT)
    {
        lua_geti(L, LUA_REGISTRYINDEX, l_usb_cb[u_event.usb_id]);
        lua_pushinteger(L, u_event.usb_id);
        lua_pushinteger(L, u_event.class);
        lua_pushinteger(L, u_event.app_id);
        lua_pushinteger(L, u_event.event);
        switch(u_event.event)
        {
        case LUAT_USB_EVENT_CONNECT:
        case LUAT_USB_EVENT_DISCONNECT:
            lua_pushinteger(L, u_info.hub_address);
            lua_pushinteger(L, u_info.hub_port);
            lua_pushinteger(L, u_info.device_address);
        	break;
        default:
        	lua_pushnil(L);
        	lua_pushnil(L);
        	lua_pushnil(L);
        	break;
        }
        lua_call(L, 7, 0);
    }
    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}


/*
USB发送数据,目前仅限于HID设备,CDC-ACM虚拟串口直接使用串口API操作,暂时无法使用
@api usb.tx(id, data, app_id)
@int usb总线id,默认0,如果芯片只有1条USB线,填0
@zbuff or string 需要发送的数据
@int 设备应用id
@return bool 成功返回true,否则返回false,总线id填错,所填设备类不支持直接发送数据等情况下返回错误
@usage
-- HID上传数据
usb.tx(0, "1234", 1) -- usb hid上传0x31 0x32 0x33 0x34  + N个0
*/
static int l_usb_tx(lua_State* L) {
	int result;
	uint32_t app_id = luaL_checkinteger(L, 3);
	uint32_t usb_id = luaL_optinteger(L, 1, 0);
    const char *buf;
    luat_zbuff_t *buff = NULL;
    if(lua_isuserdata(L, 2)) {
        buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        result = luat_usb_tx(usb_id, app_id, buff->addr, buff->used);
    } else {
    	size_t len;
    	buf = luaL_checklstring(L, 2, &len);
    	result = luat_usb_tx(usb_id, app_id, buf, len);
        lua_pushboolean(L, !result);
    }
    return 1;
}

/*
buff形式读接收到的数据，一次读出全部数据存入buff中，如果buff空间不够会自动扩展,暂时无法使用
@api usb.rx(id, buff, app_id)
@int usb总线id,默认0,如果芯片只有1条USB线,填0
@zbuff zbuff对象
@int 设备应用id
@return int 返回读到的长度，并把zbuff指针后移
@usage
usb.rx(0, buff, 1)
*/
static int l_usb_rx(lua_State *L)
{
	uint32_t app_id = luaL_checkinteger(L, 3);
	uint32_t usb_id = luaL_optinteger(L, 1, 0);

    if(lua_isuserdata(L, 2)){//zbuff对象特殊处理
    	luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        int result = luat_usb_rx(usb_id, app_id, NULL, 0);	//读出当前缓存的长度
        if (result < 0 || buff->used > buff->len)
        {
        	lua_pushinteger(L, 0);
        	return 1;
        }
        if ((size_t)result > buff->len - buff->used)
        {
        	if (__zbuff_resize(buff, buff->len + result))
        	{
        		lua_pushinteger(L, 0);
        		return 1;
        	}
        }
        result = luat_usb_rx(usb_id, app_id, buff->addr + buff->used, result);
        if (result < 0)
        {
        	result = 0;
        }
        lua_pushinteger(L, result);
        buff->used += (size_t)result;
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
usb.on(0, function(id, class, app_id, event, param1, param2, param3)
    log.info("usb", id, class, event)
end)
--回调参数有7个
1、usb总线id
2、class,设备类
3、app_id
4、event,见usb.EV_XXX
5、param1,
6、param2,
7、param3,
event类型含义及后续param含义
1、usb.EV_CONNECT,设备枚举完成,param1为hub地址,param2为设备所在的hub port序号,param3是设备自身地址
2、usb.EV_DISCONNECT,设备断开,后续参数同usb.EV_CONNECT

*/
static int l_usb_on(lua_State *L) {
    int usb_id = luaL_optinteger(L, 1, 0);
    if (usb_id >= MAX_USB_BUS_COUNT) return 0;
    if (l_usb_cb[usb_id])
    {
    	luaL_unref(L, LUA_REGISTRYINDEX, l_usb_cb[usb_id]);
    	l_usb_cb[usb_id] = 0;
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

/*
USB主机重新枚举从机
@api usb.reset_device(id, app_id)
@int usb总线id,默认0,如果芯片只有1条USB线,填0
@int app id
@return boolean true开始重新枚举，false无法枚举
@usage
usb.reset_device(0, 2)
*/
static int l_usb_reset_device(lua_State* L) {
	int ret = luat_usb_host_reset_device(luaL_optinteger(L, 1, 0), luaL_checkinteger(L, 2));
	LLOGD("reset ret %d", ret);
	lua_pushboolean(L, !ret);
    return 1;
}

#if defined(LUAT_USE_USB_HID_LUA) && defined(LUAT_USE_INPUT_HID)
/* USB Host HID subscriptions use the shared C input service. */
#define USB_HID_SUB_MT "usb.hid_subscription"
#define USB_HID_FRAME_MT "usb.hid_frame"
#define USB_HID_OWN_MT "usb.hid_snapshots"
#define USB_HID_SUBS_KEY "luat.usb.hid_subscriptions"
#define USB_HID_FRAME_BUDGET 8U

typedef struct {
    luat_input_subscription_t sub;
    void *buffer;
    int callback, slot;
    uint8_t closed, registered;
} lua_usb_hid_sub_t;
typedef struct {
    luat_input_frame_t header;
    luat_input_event_t events[];
} lua_usb_hid_frame_t;
typedef struct {
    luat_input_service_info_t *items[LUAT_INPUT_SERVICE_DEVICES];
} lua_usb_hid_owned_t;

static luat_rtos_timer_t hid_retry_timer;
static unsigned hid_active_subscriptions; /* Lua thread only. */
static uint32_t hid_pending;
static int hid_dispatch(lua_State *L, void *ptr);
static void hid_init_bindings(lua_State *L);

static void hid_notify(void *userdata)
{
    (void)userdata;
    if (__atomic_exchange_n(&hid_pending, 1, __ATOMIC_ACQ_REL)) return;
    rtos_msg_t msg = {.handler = hid_dispatch};
    if (luat_msgbus_put(&msg, 0)) __atomic_store_n(&hid_pending, 0, __ATOMIC_RELEASE);
}

static void hid_integer(lua_State *L, const char *key, lua_Integer value)
{
    lua_pushinteger(L, value); lua_setfield(L, -2, key);
}
static void hid_string(lua_State *L, const char *key, const char *value)
{
    lua_pushstring(L, value); lua_setfield(L, -2, key);
}
static int hid_error_result(lua_State *L, const char *error)
{
    lua_pushnil(L); lua_pushstring(L, error); return 2;
}
static void hid_release_owned(lua_usb_hid_owned_t *owned)
{
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_DEVICES; i++) {
        luat_heap_free(owned->items[i]); owned->items[i] = NULL;
    }
}
static int hid_owned_gc(lua_State *L)
{
    hid_release_owned(luaL_checkudata(L, 1, USB_HID_OWN_MT));
    return 0;
}
static lua_usb_hid_owned_t *hid_new_owned(lua_State *L)
{
    lua_usb_hid_owned_t *owned = lua_newuserdata(L, sizeof(*owned));
    memset(owned, 0, sizeof(*owned));
    luaL_setmetatable(L, USB_HID_OWN_MT);
    return owned;
}

static void hid_push_state(lua_State *L, const luat_input_service_info_t *info)
{
    const luat_input_axis_t *abs = (const void *)(info->data + info->key_words);
    const luat_input_axis_t *mt = abs + info->abs_count;
    const uint32_t *state = (const void *)(mt + info->mt_count);
    lua_createtable(L, 0, 7);
    hid_integer(L, "id", info->snapshot.device_id);
    hid_integer(L, "sequence", info->snapshot.sequence);
    hid_integer(L, "timestamp_ms", info->snapshot.timestamp_ms);
    hid_integer(L, "slot", info->snapshot.mt_slot);
    lua_newtable(L);
    for (unsigned i = 0; i < info->key_words * 32U; i++) {
        if (!(state[i / 32U] & (UINT32_C(1) << (i % 32U)))) continue;
        lua_pushboolean(L, 1); lua_rawseti(L, -2, i);
    }
    lua_setfield(L, -2, "keys");
    state += info->key_words;
    lua_newtable(L);
    for (unsigned i = 0; i < info->abs_count; i++) {
        lua_pushinteger(L, (int32_t)state[i]); lua_rawseti(L, -2, abs[i].code);
    }
    lua_setfield(L, -2, "abs");
    state += info->abs_count;
    lua_newtable(L);
    for (unsigned slot = 0; slot < info->mt_slots; slot++) {
        lua_newtable(L);
        for (unsigned i = 0; i < info->mt_count; i++) {
            lua_pushinteger(L, (int32_t)state[slot * info->mt_count + i]);
            lua_rawseti(L, -2, mt[i].code);
        }
        lua_rawseti(L, -2, slot);
    }
    lua_setfield(L, -2, "slots");
}
static void hid_push_axes(lua_State *L, const luat_input_axis_t *axes, unsigned count)
{
    lua_newtable(L);
    for (unsigned i = 0; i < count; i++) {
        lua_createtable(L, 0, 3);
        hid_integer(L, "min", axes[i].minimum); hid_integer(L, "max", axes[i].maximum);
        hid_integer(L, "initial", axes[i].initial);
        lua_rawseti(L, -2, axes[i].code);
    }
}
static void hid_push_bits(lua_State *L, const uint32_t *bits, unsigned words)
{
    lua_newtable(L);
    unsigned n = 0;
    for (unsigned i = 0; i < words * 32U; i++) {
        if (!(bits[i / 32U] & (UINT32_C(1) << (i % 32U)))) continue;
        lua_pushinteger(L, i); lua_rawseti(L, -2, ++n);
    }
}
static void hid_push_info(lua_State *L, const luat_input_service_info_t *info)
{
    lua_createtable(L, 0, 9);
    hid_integer(L, "id", info->snapshot.device_id); hid_string(L, "name", info->name);
    hid_integer(L, "bus", info->bus); hid_integer(L, "vendor", info->vendor);
    hid_integer(L, "product", info->product); hid_integer(L, "version", info->version);
    hid_integer(L, "properties", info->properties);
    lua_newtable(L);
    hid_push_bits(L, info->data, info->key_words); lua_setfield(L, -2, "keys");
    hid_push_bits(L, &info->rel_bits, 1); lua_setfield(L, -2, "rel");
    hid_push_bits(L, &info->msc_bits, 1); lua_setfield(L, -2, "msc");
    const luat_input_axis_t *axes = (const void *)(info->data + info->key_words);
    hid_push_axes(L, axes, info->abs_count); lua_setfield(L, -2, "abs");
    hid_push_axes(L, axes + info->abs_count, info->mt_count); lua_setfield(L, -2, "mt");
    hid_integer(L, "mt_slots", info->mt_slots);
    lua_setfield(L, -2, "caps");
    hid_push_state(L, info); lua_setfield(L, -2, "state");
}

static uint32_t hid_check_id(lua_State *L, int index)
{
    lua_Integer id = luaL_checkinteger(L, index);
    luaL_argcheck(L, id > 0 && (uint64_t)id <= UINT32_MAX, index, "invalid device id");
    return (uint32_t)id;
}
static int hid_frame_get(lua_State *L)
{
    lua_usb_hid_frame_t *frame = luaL_checkudata(L, 1, USB_HID_FRAME_MT);
    lua_Integer index = luaL_checkinteger(L, 2);
    luaL_argcheck(L, index >= 1 && index <= frame->header.count, 2, "event index out of range");
    const luat_input_event_t *event = &frame->events[index - 1];
    lua_pushinteger(L, event->type); lua_pushinteger(L, event->code); lua_pushinteger(L, event->value);
    return 3;
}
static int hid_frame_index(lua_State *L)
{
    lua_usb_hid_frame_t *frame = luaL_checkudata(L, 1, USB_HID_FRAME_MT);
    const char *key = luaL_checkstring(L, 2);
    if (!strcmp(key, "get")) lua_pushcfunction(L, hid_frame_get);
    else if (!strcmp(key, "count")) lua_pushinteger(L, frame->header.count);
    else if (!strcmp(key, "device_id")) lua_pushinteger(L, frame->header.device_id);
    else if (!strcmp(key, "sequence")) lua_pushinteger(L, frame->header.sequence);
    else if (!strcmp(key, "timestamp_ms")) lua_pushinteger(L, frame->header.timestamp_ms);
    else lua_pushnil(L);
    return 1;
}
static int hid_readonly(lua_State *L) { return luaL_error(L, "input frame is read-only"); }
static int hid_frame_len(lua_State *L)
{
    lua_usb_hid_frame_t *frame = luaL_checkudata(L, 1, USB_HID_FRAME_MT);
    lua_pushinteger(L, frame->header.count); return 1;
}

static void hid_close_sub(lua_State *L, lua_usb_hid_sub_t *sub)
{
    if (sub->closed) return;
    sub->closed = 1;
    luat_input_service_lock();
    luat_input_service_close(&sub->sub);
    luat_input_service_unlock();
    luat_heap_free(sub->buffer); sub->buffer = NULL;
    if (sub->callback != LUA_NOREF) luaL_unref(L, LUA_REGISTRYINDEX, sub->callback);
    sub->callback = LUA_NOREF;
    if (sub->registered) {
        lua_getfield(L, LUA_REGISTRYINDEX, USB_HID_SUBS_KEY);
        lua_pushnil(L); lua_rawseti(L, -2, sub->slot + 1); lua_pop(L, 1);
        sub->registered = 0;
        hid_active_subscriptions--;
        if (!hid_active_subscriptions && hid_retry_timer) {
            luat_rtos_timer_stop(hid_retry_timer); luat_rtos_timer_delete(hid_retry_timer); hid_retry_timer = NULL;
        }
    }
}
static int l_hid_close(lua_State *L)
{
    lua_usb_hid_sub_t *sub = luaL_checkudata(L, 1, USB_HID_SUB_MT);
    hid_close_sub(L, sub); return 0;
}
static int l_hid_stats(lua_State *L)
{
    lua_usb_hid_sub_t *sub = luaL_checkudata(L, 1, USB_HID_SUB_MT);
    luat_input_service_lock();
    luat_input_subscription_t *s = &sub->sub;
    uint32_t frames = s->frames, overflows = s->overflows, required = s->required_bytes;
    size_t capacity = s->queue.capacity;
    size_t used = s->queue.full ? capacity : s->queue.tail >= s->queue.head ?
        s->queue.tail - s->queue.head : capacity - s->queue.head + s->queue.tail;
    luat_input_service_unlock();
    lua_newtable(L);
    hid_integer(L, "frames", frames); hid_integer(L, "overflows", overflows);
    hid_integer(L, "queue_bytes", capacity); hid_integer(L, "queued_bytes", used);
    hid_integer(L, "required_bytes", required);
    lua_pushboolean(L, sub->closed); lua_setfield(L, -2, "closed");
    return 1;
}

/* Takes one callback payload from the top. The userdata is rooted by dispatch.
 * Callback may close itself or create another subscription. */
static void hid_invoke(lua_State *L, lua_usb_hid_sub_t *sub, const char *kind, uint32_t id)
{
    if (sub->closed) { lua_pop(L, 1); return; }
    lua_rawgeti(L, LUA_REGISTRYINDEX, sub->callback); lua_insert(L, -2);
    lua_pushstring(L, kind); lua_insert(L, -2);
    if (id) lua_pushinteger(L, id); else lua_pushnil(L);
    lua_insert(L, -2);
    if (lua_pcall(L, 3, 0, 0) != LUA_OK) {
        const char *error = lua_tostring(L, -1);
        LLOGE("callback error: %s", error ? error : "non-string error");
        lua_pop(L, 1);
        hid_close_sub(L, sub); /* A failing consumer cannot flood the GUI task. */
    }
}

static int hid_drain(lua_State *L, lua_usb_hid_sub_t *sub)
{
    for (unsigned budget = 0; budget < USB_HID_FRAME_BUDGET && !sub->closed; budget++) {
        int base = lua_gettop(L);
        luat_input_frame_t next;
        luat_input_service_lock();
        int fault = sub->sub.fault;
        uint32_t required = sub->sub.required_bytes;
        int ret = fault ? fault : luat_input_queue_peek(&sub->sub.queue, &next);
        luat_input_service_unlock();
        if (fault) {
            lua_newtable(L);
            hid_string(L, "reason", fault == LUAT_INPUT_ENOSPC ? "frame_too_large" : "resource_error");
            hid_integer(L, "required_bytes", required);
            hid_invoke(L, sub, "overflow", 0);
            hid_close_sub(L, sub);
            return 0;
        }
        if (ret == LUAT_INPUT_EEMPTY) return 0;
        if (ret == LUAT_INPUT_ELOST) {
            lua_usb_hid_owned_t *owned = hid_new_owned(L);
            size_t count = 0;
            luat_input_service_lock();
            ret = luat_input_service_recover(&sub->sub, owned->items, LUAT_INPUT_SERVICE_DEVICES, &count);
            luat_input_service_unlock();
            if (ret) { lua_settop(L, base); return 0; } /* Retry on next timer tick. */
            lua_newtable(L); hid_string(L, "reason", "queue_full");
            hid_invoke(L, sub, "overflow", 0);
            for (size_t i = 0; i < count && !sub->closed; i++) {
                hid_push_info(L, owned->items[i]);
                lua_pushboolean(L, 1); lua_setfield(L, -2, "resync");
                hid_invoke(L, sub, "attach", owned->items[i]->snapshot.device_id);
            }
            hid_release_owned(owned);
            lua_settop(L, base);
            continue;
        }
        if (ret) return 0;
        /* Lua allocation may run GC, so it occurs outside the service lock.
         * Producers never remove a queued head except on sticky overflow. */
        lua_usb_hid_frame_t *frame = lua_newuserdata(L, sizeof(*frame) + (size_t)next.count * sizeof(frame->events[0]));
        memset(frame, 0, sizeof(*frame));
        luaL_setmetatable(L, USB_HID_FRAME_MT);
        luat_input_service_lock();
        ret = luat_input_queue_read(&sub->sub.queue, &frame->header, frame->events, next.count);
        luat_input_service_unlock();
        if (ret) { lua_settop(L, base); continue; }
        uint16_t flags = frame->header.flags;
        uint32_t id = frame->header.device_id;
        if (flags & LUAT_INPUT_FRAME_REMOVE) {
            lua_pop(L, 1); lua_pushnil(L); hid_invoke(L, sub, "remove", id);
        } else if (flags & (LUAT_INPUT_FRAME_ATTACH | LUAT_INPUT_FRAME_RESET)) {
            const luat_input_service_info_t *info = (const void *)frame->events;
            hid_push_info(L, info);
            hid_invoke(L, sub, flags & LUAT_INPUT_FRAME_ATTACH ? "attach" : "reset", id);
        } else hid_invoke(L, sub, "frame", id);
        lua_settop(L, base);
    }
    return !sub->closed; /* Continue a backlog through another bounded message. */
}
static int hid_dispatch(lua_State *L, void *ptr)
{
    (void)ptr;
    __atomic_store_n(&hid_pending, 0, __ATOMIC_RELEASE);
    int base = lua_gettop(L);
    lua_getfield(L, LUA_REGISTRYINDEX, USB_HID_SUBS_KEY);
    if (!lua_istable(L, -1)) { lua_settop(L, base); return 0; }
    int again = 0;
    for (unsigned i = 0; i < LUAT_INPUT_SERVICE_SUBSCRIPTIONS; i++) {
        lua_rawgeti(L, -1, i + 1);
        lua_usb_hid_sub_t *sub = luaL_testudata(L, -1, USB_HID_SUB_MT);
        if (sub && !sub->closed && hid_drain(L, sub)) again = 1;
        lua_pop(L, 1);
    }
    lua_settop(L, base);
    if (again) hid_notify(NULL);
    return 0;
}

/**
订阅 USB Host HID 输入事件，仅匹配 USB HID 设备。
@api usb.hid_subscribe(filter, callback)
@table 过滤项：device 为输入设备实例 ID；types 为事件类型数组；queue_bytes 默认为 4096。
@function 回调 function(kind, device_id, data)，不可 yield。kind 包括 attach、frame、reset、remove、overflow。
@return userdata|nil 订阅对象；保留对象直到调用 close()，垃圾回收时也会关闭。
*/
static int l_usb_hid_subscribe(lua_State *L)
{
    if (!luat_input_service_is_ready()) return hid_error_result(L, "not_ready");
    luaL_checktype(L, 1, LUA_TTABLE); luaL_checktype(L, 2, LUA_TFUNCTION);
    uint32_t id = 0, types = (1U << LUAT_INPUT_EV_KEY) | (1U << LUAT_INPUT_EV_REL) |
        (1U << LUAT_INPUT_EV_ABS) | (1U << LUAT_INPUT_EV_MSC);
    lua_getfield(L, 1, "device");
    if (!lua_isnil(L, -1)) id = hid_check_id(L, -1);
    lua_pop(L, 1);
    lua_getfield(L, 1, "queue_bytes");
    lua_Integer bytes = luaL_optinteger(L, -1, 4096);
    luaL_argcheck(L, bytes >= 256 && bytes <= 65536, 1, "queue_bytes must be 256..65536");
    lua_pop(L, 1);
    lua_getfield(L, 1, "types");
    if (!lua_isnil(L, -1)) {
        luaL_checktype(L, -1, LUA_TTABLE);
        types = 0;
        size_t count = lua_rawlen(L, -1);
        for (size_t i = 1; i <= count; i++) {
            lua_rawgeti(L, -1, i);
            lua_Integer type = luaL_checkinteger(L, -1);
            luaL_argcheck(L, type >= LUAT_INPUT_EV_SYN && type <= LUAT_INPUT_EV_MSC, 1, "invalid event type");
            types |= UINT32_C(1) << type;
            lua_pop(L, 1);
        }
        luaL_argcheck(L, types != 0, 1, "empty event types");
    }
    lua_pop(L, 1);
    hid_init_bindings(L);
    lua_usb_hid_sub_t *sub = lua_newuserdata(L, sizeof(*sub));
    memset(sub, 0, sizeof(*sub)); sub->callback = LUA_NOREF; sub->slot = -1;
    luaL_setmetatable(L, USB_HID_SUB_MT);
    sub->buffer = luat_heap_malloc((size_t)bytes);
    if (!sub->buffer) return hid_error_result(L, "no_memory");
    lua_pushvalue(L, 2); sub->callback = luaL_ref(L, LUA_REGISTRYINDEX);
    int created_timer = !hid_retry_timer;
    if (created_timer) {
        if (luat_rtos_timer_create(&hid_retry_timer)) { hid_close_sub(L, sub); return hid_error_result(L, "timer_failed"); }
        if (luat_rtos_timer_start(hid_retry_timer, 20, 1, hid_notify, NULL)) {
            luat_rtos_timer_delete(hid_retry_timer); hid_retry_timer = NULL;
            hid_close_sub(L, sub); return hid_error_result(L, "timer_failed");
        }
    }
    luat_input_service_lock();
    int ret = luat_input_service_subscribe_bus(&sub->sub, id, types, LUAT_INPUT_BUS_USB, sub->buffer, (size_t)bytes, hid_notify, NULL);
    luat_input_service_unlock();
    if (ret) {
        hid_close_sub(L, sub);
        if (created_timer) { luat_rtos_timer_delete(hid_retry_timer); hid_retry_timer = NULL; }
        return hid_error_result(L, ret == LUAT_INPUT_ESTALE ? "not_found" :
            ret == LUAT_INPUT_SERVICE_ENOMEM ? "no_memory" : "subscription_limit_or_queue_too_small");
    }
    sub->slot = (int)sub->sub.slot; sub->registered = 1; hid_active_subscriptions++;
    lua_getfield(L, LUA_REGISTRYINDEX, USB_HID_SUBS_KEY);
    lua_pushvalue(L, -2); lua_rawseti(L, -2, sub->slot + 1); lua_pop(L, 1);
    return 1;
}

static void hid_init_bindings(lua_State *L)
{
    int initialized = lua_getfield(L, LUA_REGISTRYINDEX, USB_HID_SUBS_KEY) != LUA_TNIL;
    lua_pop(L, 1);
    if (initialized) return;
    luaL_newmetatable(L, USB_HID_OWN_MT);
    lua_pushcfunction(L, hid_owned_gc); lua_setfield(L, -2, "__gc"); lua_pop(L, 1);
    luaL_newmetatable(L, USB_HID_FRAME_MT);
    lua_pushcfunction(L, hid_frame_index); lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, hid_readonly); lua_setfield(L, -2, "__newindex");
    lua_pushcfunction(L, hid_frame_len); lua_setfield(L, -2, "__len");
    hid_string(L, "__metatable", USB_HID_FRAME_MT); lua_pop(L, 1);
    luaL_newmetatable(L, USB_HID_SUB_MT);
    lua_pushcfunction(L, l_hid_close); lua_setfield(L, -2, "__gc");
    static const luaL_Reg methods[] = {{"close", l_hid_close}, {"stats", l_hid_stats}, {NULL, NULL}};
    luaL_newlib(L, methods); lua_setfield(L, -2, "__index"); lua_pop(L, 1);
    lua_newtable(L); lua_newtable(L);
    hid_string(L, "__mode", "v"); lua_setmetatable(L, -2);
    lua_setfield(L, LUA_REGISTRYINDEX, USB_HID_SUBS_KEY);
}
#endif

static const rotable_Reg_t reg_usb[] =
{
#if defined(LUAT_USE_USB_HID_LUA) && defined(LUAT_USE_INPUT_HID)
    { "hid_subscribe", ROREG_FUNC(l_usb_hid_subscribe) },
    { "HID_EV_KEY", ROREG_INT(LUAT_INPUT_EV_KEY) },
    { "HID_EV_REL", ROREG_INT(LUAT_INPUT_EV_REL) },
    { "HID_EV_ABS", ROREG_INT(LUAT_INPUT_EV_ABS) },
    { "HID_EV_MSC", ROREG_INT(LUAT_INPUT_EV_MSC) },
#endif
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
	{ "reset_device",       ROREG_FUNC(l_usb_reset_device)},
	//@const HOST number USB主机模式
    { "HOST",        		ROREG_INT(LUAT_USB_MODE_HOST)},
	//@const DEVICE number USB从机模式
    { "DEVICE",       		ROREG_INT(LUAT_USB_MODE_DEVICE)},
	//@const OTG number USB otg模式
    { "OTG",       			ROREG_INT(LUAT_USB_MODE_OTG)},
	//@const HUB number 集线器类
    { "HUB",        	ROREG_INT(LUAT_USB_CLASS_HUB)},
	//@const CAMERA number 摄像头类
    { "CAMERA",        		ROREG_INT(LUAT_USB_CLASS_CAMERA)},
	//@const CDC_ACM number 虚拟串口类
    { "CDC_ACM",        	ROREG_INT(LUAT_USB_CLASS_CDC_ACM)},
	//@const MSC number 大容量存储类，也就是U盘，TF卡
    { "MSC",       			ROREG_INT(LUAT_USB_CLASS_MSC)},
	//@const CDC_ECM number 虚拟网卡类
    { "CDC_ECM",		ROREG_INT(LUAT_USB_CLASS_CDC_ECM)},
	//@const RNDIS number 虚拟网卡类
    { "RNDIS",			ROREG_INT(LUAT_USB_CLASS_RNDIS)},
	//@const AUDIO number audio音频类
    { "AUDIO",       		ROREG_INT(LUAT_USB_CLASS_AUDIO)},
	//@const HID_CM number HID设备类，自定义类型，用于透传数据，不能和标准键盘同时使用
    { "HID_CM",       			ROREG_INT(LUAT_USB_CLASS_HID_CUSTOMER)},
	//@const HID_KB number HID设备类，标准键盘，常见扫码枪，不能和自定义类型同时使用
    { "HID_KB",       			ROREG_INT(LUAT_USB_CLASS_HID_KEYBOARD)},
	//@const EV_NEW_RX number  有新的数据到来
    { "EV_NEW_RX",       		ROREG_INT(LUAT_USB_EVENT_NEW_RX)},
	//@const EV_TX_DONE number 所有数据都已发送
    { "EV_TX_DONE",        		ROREG_INT(LUAT_USB_EVENT_TX_DONE)},
	//@const EV_CONNECT number usb从机已经连接上并且枚举成功
    { "EV_CONNECT",       	ROREG_INT(LUAT_USB_EVENT_CONNECT)},
	//@const EV_DISCONNECT number usb从机断开
    { "EV_DISCONNECT",      ROREG_INT(LUAT_USB_EVENT_DISCONNECT)},
	//@const EV_RX_ERROR number  有新的数据到来
    { "EV_RX_ERROR",       		ROREG_INT(LUAT_USB_EVENT_RX_ERROR)},
	//@const EV_TX_ERROR number 所有数据都已发送
    { "EV_TX_ERROR",        		ROREG_INT(LUAT_USB_EVENT_TX_ERROR)},
	//@const EV_SUSPEND number usb从机挂起
    { "EV_SUSPEND",       	ROREG_INT(LUAT_USB_EVENT_SUSPEND)},
	//@const EV_RESUME number usb从机恢复
    { "EV_RESUME",       	ROREG_INT(LUAT_USB_EVENT_RESUME)},
	//@const EV_ERR_STOP number usb从机遇到故障停止工作了，可以调用usb.reset_device来尝试恢复
    { "EV_ERR_STOP",       	ROREG_INT(LUAT_USB_EVENT_ERROR_STOP)},
    { NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_usb( lua_State *L )
{
    luat_newlib2(L, reg_usb);
    return 1;
}
#endif
