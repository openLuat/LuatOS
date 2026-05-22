
/*
@module  audio
@summary 多媒体-音频
@version 1.0
@date    2022.03.11
@demo multimedia
@tag LUAT_USE_AUDIO_V2
*/
#include "luat_audio_channel.h"
#include "luat_audio_define.h"
#include "luat_audio_driver.h"
#include "luat_audio_request.h"
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#include <stdint.h>
#define LUAT_LOG_TAG "audio_v2"
#include "luat_log.h"
#ifdef LUAT_USE_AUDIO_V2
#include "luat_common_api.h"
#include "luat_audio_core.h"

#include "luat_mem.h"

#ifndef LUAT_AUDIO_REQUEST_MAX
#define LUAT_AUDIO_REQUEST_MAX 10
#endif

typedef struct {
    luat_llist_head node;
    uint8_t self_index;
    uint8_t is_busy;
    uint8_t pad[2];
    luat_audio_request_block_t request;
} l_audio_request_t;

typedef struct {
    luat_llist_head request_free_list;
    luat_llist_head request_busy_list;
    l_audio_request_t request_table[LUAT_AUDIO_REQUEST_MAX];
    int cb_ref;
} l_audio_ctrl_t;
static l_audio_ctrl_t _l_audio;


static int _l_audio_handler(lua_State *L, void* ptr) {
    (void)ptr;
    luat_data_union_t u_data;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    u_data.u32 = msg->arg1;
    if (u_data.u8[0] < LUAT_AUDIO_REQUEST_MAX) {
        if (LUAT_AUDIO_REQUEST_EVENT_END == u_data.u8[1]) {
            l_audio_request_t *l_req = &_l_audio.request_table[u_data.u8[0]];
            l_req->is_busy = 0;
            luat_llist_del(&l_req->node);
            luat_llist_add_tail(&l_req->node, &_l_audio.request_free_list);
            LLOGC(luat_audio_debug_flag,"lua request %d end", u_data.u8[0]);
        }
        if (_l_audio.cb_ref) {
            lua_geti(L, LUA_REGISTRYINDEX, _l_audio.cb_ref);
            if (lua_isfunction(L, -1)) {
                lua_pushinteger(L, u_data.u8[0]);
                lua_pushinteger(L, u_data.u8[1]);
                lua_pushinteger(L, msg->arg2);
                lua_call(L, 3, 0);
            }
        }
    }

    lua_pushinteger(L, 0);
    return 1;
}

static void _l_audio_request_callback(uint32_t event, uint8_t *data, uint32_t param, struct luat_audio_request_block *request_block) {
    l_audio_request_t *l_req = (l_audio_request_t *)(request_block->user_data);
    luat_data_union_t u_data;
    u_data.u8[0] = l_req->self_index;
    u_data.u8[1] = event;
    rtos_msg_t msg;
	msg.handler = _l_audio_handler;
	msg.ptr = NULL;
	msg.arg1 = u_data.u32;
	msg.arg2 = param;
	luat_msgbus_put(&msg, 0);
}

void l_audio_init(void)
{
    LUAT_INIT_LLIST_HEAD(&_l_audio.request_free_list);
    LUAT_INIT_LLIST_HEAD(&_l_audio.request_busy_list);
    for(uint32_t i = 0; i < LUAT_AUDIO_REQUEST_MAX; i++)
    {
        _l_audio.request_table[i].self_index = i;
        luat_llist_add_tail(&_l_audio.request_table[i].node, &_l_audio.request_free_list);
    }
}

/*
播放N个文件。考虑到读SD卡速度比较慢而拖累luavm进程的速度，所以尽量使用本API
@api audio_v2.play(path, err_stop, priority, driver_probe_id, codec_id)
@string/table 文件名，如果是table，则表示连续播放多个文件
@boolean 是否在文件解码失败后停止解码，只有在连续播放多个文件时才有用，默认true，遇到解码错误自动停止
@int 优先级，0~255，值越大，优先级越高，默认0
@int 驱动id，在不使用默认驱动时填写，绝大部分情况下都不需要填写。驱动id需要通过audio.make_probe_id合成
@int 解码器id，在需要指定解码器时填写，绝大部分情况下都不需要填写
@return boolean 成功返回true,否则返回false
@return int request_index 请求索引，用于后续操作，如暂停、恢复，回调信息判断等
@usage
audio_v2.play("xxxxxx")		--开始播放某个文件
*/
static int l_audio_play(lua_State *L) {
    int result = -1;
    uint8_t request_index = 0;
    uint8_t is_error_stop = 1;
    uint8_t priority = luaL_optinteger(L, 3, 0);
    luat_audio_driver_probe_t driver_probe = {0};
    uint8_t codec_id = LUAT_AUDIO_DATA_CODEC_TYPE_MAX;
    if (lua_isboolean(L, 2)) {
        is_error_stop = lua_toboolean(L, 2);
    }
    driver_probe.probe_id = luaL_optinteger(L, 4, 0);
    codec_id = luaL_optinteger(L, 5, LUAT_AUDIO_DATA_CODEC_TYPE_MAX);
    size_t file_nums = 0;
    size_t path_len = 0;
    luat_audio_play_file_info_t *info = NULL;
    if (lua_istable(L, 1)) {
    	file_nums = lua_rawlen(L, 1); //返回数组的长度
        info = (luat_audio_play_file_info_t *)luat_heap_calloc(file_nums, sizeof(luat_audio_play_file_info_t));
        if (!info) {
            goto DONE;
        }

        for (size_t i = 0; i < file_nums; i++) {
            lua_rawgeti(L, 1, 1 + i);
            info[i].path = (void*)lua_tolstring(L, -1, &path_len);
            info[i].fail_continue = !is_error_stop;
            info[i].rom_data_len = 0;
            lua_pop(L, 1); //将刚刚获取的元素值从栈中弹出
        }
    } else if (LUA_TSTRING == (lua_type(L, (1)))) {
        info = (luat_audio_play_file_info_t *)luat_heap_calloc(1, sizeof(luat_audio_play_file_info_t));
        if (!info) {
            goto DONE;
        }
        info[0].path = (void*)lua_tolstring(L, 1, &path_len);
        info[0].fail_continue = !is_error_stop;
        info[0].rom_data_len = 0;
        file_nums = 1;
    } else {
    	goto DONE;
    }
    if (luat_llist_empty(&_l_audio.request_free_list)) {
        LLOGE("audio request free list is empty");
        goto DONE;
    }
    l_audio_request_t *l_req = (l_audio_request_t *)_l_audio.request_free_list.next;
    request_index = l_req->self_index;
    luat_llist_del(&l_req->node);
    luat_llist_add_tail(&l_req->node, &_l_audio.request_busy_list);
    result = luat_audio_request_play_files(&l_req->request, 
        (driver_probe.probe_id ? &driver_probe : NULL), 
    luat_audio_data_codec_find(codec_id), 
        info, file_nums, priority,0, _l_audio_request_callback, l_req);
    luat_heap_free(info);
    if (result) {
        luat_llist_del(&l_req->node);
        luat_llist_add_tail(&l_req->node, &_l_audio.request_free_list);
    } else {
        LLOGC(luat_audio_debug_flag,"lua request %d start", l_req->self_index);
    }
DONE:
    lua_pushboolean(L, !result);
    lua_pushinteger(L, request_index);
    return 2;
}

/*
播放tts语音
@api audio_v2.tts(text, priority, driver_probe_id)
@string/zbuff 需要播放的内容
@int 优先级，0~255，值越大，优先级越高，默认0
@int 驱动id，在不使用默认驱动时填写，绝大部分情况下都不需要填写。驱动id需要通过audio.make_probe_id合成
@return boolean 成功返回true,否则返回false
@return int request_index 请求索引，用于后续操作，如暂停、恢复，回调信息判断等
@usage
audio_v2.tts("xxxxxx")		--开始播放某个文本
*/
static int l_audio_tts(lua_State *L) {
    int result = -1;
    uint8_t request_index = 0;
    luat_audio_driver_probe_t driver_probe = {0};
    driver_probe.probe_id = luaL_optinteger(L, 3, 0);
    uint8_t priority = luaL_optinteger(L, 2, 0);
    const char *buf;
    size_t len = 0;
    if (LUA_TSTRING == (lua_type(L, 1))) {
        buf = lua_tolstring(L, 1, &len);//取出字符串数据
    } else if(lua_isuserdata(L, 2)) {
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        buf = buff->addr;
        len = buff->used;
    } else {
    	goto DONE;
    }
    if (luat_llist_empty(&_l_audio.request_free_list)) {
        LLOGE("audio request free list is empty");
        goto DONE;
    }
    l_audio_request_t *l_req = (l_audio_request_t *)_l_audio.request_free_list.next;
    request_index = l_req->self_index;
    luat_llist_del(&l_req->node);
    luat_llist_add_tail(&l_req->node, &_l_audio.request_busy_list);
    result = luat_audio_request_play_tts(&l_req->request, 
        (driver_probe.probe_id ? &driver_probe : NULL), buf, len, priority, 0,_l_audio_request_callback, l_req);
    if (result) {
        luat_llist_del(&l_req->node);
        luat_llist_add_tail(&l_req->node, &_l_audio.request_free_list);
    } else {
        LLOGC(luat_audio_debug_flag,"lua request %d start", l_req->self_index);
    }
DONE:
    lua_pushboolean(L, !result);
    lua_pushinteger(L, request_index);
    return 2;
}

/*
停止播放文件或者tts
@api audio_v2.stop(request_index)
@int request_index 请求索引，通过audio.play_files或audio.tts返回
@return nil
@usage
audio_v2.stop(request_index)
*/
static int l_audio_stop(lua_State *L) {
    uint8_t request_index = luaL_checkinteger(L, 1);
    l_audio_request_t *l_req = &_l_audio.request_table[request_index];
    if (l_req->is_busy) {
        luat_audio_request_cancel(&l_req->request);
        luat_llist_del(&l_req->node);
        luat_llist_add_tail(&l_req->node, &_l_audio.request_free_list);
    } else {
        LLOGC(luat_audio_debug_flag,"lua request %d not busy", request_index);
    }
    return 0;
}

/*
暂停播放文件或者tts对应的音频通道
@api audio_v2.pause(request_index, pause)
@int request_index 请求索引，通过audio.play_files或audio.tts返回
@boolean pause 是否暂停，默认false
@return nil
@usage
audio_v2.pause(request_index, true)
*/
static int l_audio_pause(lua_State *L) {
    uint8_t request_index = luaL_checkinteger(L, 1);
    l_audio_request_t *l_req = &_l_audio.request_table[request_index];
    uint8_t pause = lua_toboolean(L, 2);
    luat_audio_channel_play(&l_req->request.data_channel, !pause);
    return 0;
}

/*
合成音频驱动id
@api audio_v2.make_probe_id(tx_bus_type, tx_bus_id, rx_bus_type, rx_bus_id)
@int tx_bus_type 发送总线类型，见DRIVER_TYPE_xxx常量
@int tx_bus_id 发送总线id，见DRIVER_TYPE_xxx常量
@int rx_bus_type 接收总线类型，见DRIVER_TYPE_xxx常量
@int rx_bus_id 接收总线id，见DRIVER_TYPE_xxx常量
@return int 驱动id
@usage
probe_id = audio_v2.make_probe_id(LUAT_AUDIO_DRIVER_TYPE_I2S, 0, LUAT_AUDIO_DRIVER_TYPE_I2S, 0) --i2s0双工
probe_id = audio_v2.make_probe_id(LUAT_AUDIO_DRIVER_TYPE_DAC, 0, LUAT_AUDIO_DRIVER_TYPE_NONE, 0) --dac0单工
*/
static int l_audio_make_probe_id(lua_State *L) {
	luat_audio_driver_probe_t probe;
    probe.tx_bus_type = luaL_optinteger(L, 1, LUAT_AUDIO_DRIVER_TYPE_NONE);
    probe.tx_bus_id = luaL_optinteger(L, 2, 0);
    probe.rx_bus_type = luaL_optinteger(L, 3, LUAT_AUDIO_DRIVER_TYPE_NONE);
    probe.rx_bus_id = luaL_optinteger(L, 4, 0);
    lua_pushinteger(L, probe.probe_id);
    return 1;
}

/*
设置默认音频驱动
@api audio_v2.set_default_driver(driver_probe_id)
@int driver_probe_id 驱动id，驱动id需要通过audio.make_probe_id合成
@return boolean 成功返回true,否则返回false
@usage
local driver_probe_id = audio_v2.make_probe_id(LUAT_AUDIO_DRIVER_TYPE_I2S, 0, LUAT_AUDIO_DRIVER_TYPE_I2S, 0) 
audio_v2.set_default_driver(driver_probe_id)
driver_probe_id = audio_v2.make_probe_id(LUAT_AUDIO_DRIVER_TYPE_DAC, 0, LUAT_AUDIO_DRIVER_TYPE_NONE, 0) --dac0单工
audio_v2.set_default_driver(driver_probe_id)
*/
static int l_audio_set_default_driver(lua_State *L) {
    luat_audio_driver_probe_t probe;
    probe.probe_id = luaL_optinteger(L, 1, 0);
    int ret = luat_audio_driver_set_default(&probe);
    lua_pushboolean(L, !ret);
    return 1;
}

/*
获取音频驱动数量和默认音频驱动索引
@api audio_v2.get_driver_info()
@return int all_nums 所有音频驱动数量
@return int default_driver_index 默认音频驱动索引，从0开始
@usage
local all_nums, default_driver_index = audio_v2.get_driver_info()
log.info(all_nums, default_driver_index)
*/
static int l_audio_get_driver_info(lua_State *L) {
    uint8_t all_nums = 0;
    uint8_t default_driver_index;
    luat_audio_driver_get_ctrl_info(&all_nums, &default_driver_index);
    lua_pushinteger(L, all_nums);
    lua_pushinteger(L, default_driver_index);
    return 2;
}

/*
获取音频驱动id
@api audio_v2.get_driver_id(index)
@int index 驱动索引，从0开始
@return int 驱动id
@usage
-- 打印出默认音频驱动信息
local all_nums, default_driver_index = audio_v2.get_driver_info()
local driver_probe_id = audio_v2.get_driver_id(default_driver_index)
log.info(audio_v2.print_probe_id(driver_probe_id, true))
*/
static int l_audio_get_driver_id(lua_State *L) {
    uint8_t index = luaL_optinteger(L, 1, 0);
    uint8_t all_nums = 0;
    uint8_t default_driver_index;
    luat_audio_driver_ctrl_t *ctrl_table =luat_audio_driver_get_ctrl_info(&all_nums, &default_driver_index);
    if (index >= all_nums) {
        lua_pushinteger(L, 0);
        return 1;
    } else {
        lua_pushinteger(L, ctrl_table[index].probe.probe_id);
        return 1;
    }
}

/*
分解音频驱动id，并返回详细信息
@api audio_v2.print_probe_id(driver_probe_id, is_string)
@int driver_probe_id 驱动id，驱动id需要通过audio.make_probe_id合成
@boolean is_string 是否返回字符串，true返回字符串，false返回常量
@return any tx_bus_type 发送总线类型，见DRIVER_TYPE_xxx常量。is_string为true时，返回字符串，否则返回常量类型名称
@return any tx_bus_id 发送总线id
@return any rx_bus_type 接收总线类型，见DRIVER_TYPE_xxx常量。is_string为true时，返回字符串，否则返回常量类型名称
@return any rx_bus_id 接收总线id
@usage
local tx_bus_type, tx_bus_id, rx_bus_type, rx_bus_id = audio_v2.print_probe_id(probe_id, true)
log.info(tx_bus_type, tx_bus_id, rx_bus_type, rx_bus_id)
*/
static int l_audio_print_probe_id(lua_State *L) {
    const char *bus_type_str[] = {"NONE", "I2S", "DAC", "ADC", "USB"};
    luat_audio_driver_probe_t probe;
    probe.probe_id = luaL_optinteger(L, 1, 0);
    uint8_t is_string = lua_toboolean(L, 2);
    if (is_string) {
        lua_pushstring(L, bus_type_str[probe.tx_bus_type]);
        lua_pushinteger(L, probe.tx_bus_id);
        lua_pushstring(L, bus_type_str[probe.rx_bus_type]);
        lua_pushinteger(L, probe.rx_bus_id);
        return 4;
    } else {
        lua_pushinteger(L, probe.tx_bus_type);
        lua_pushinteger(L, probe.tx_bus_id);
        lua_pushinteger(L, probe.rx_bus_type);
        lua_pushinteger(L, probe.rx_bus_id);
        return 4;
    }
}

/*
配置音频驱动的pa电源控制
@api audio_v2.config_pa_power_ctrl(pa_power_ctrl_enable, pa_power_pin, pa_power_on_level, pa_power_on_delay_time_ms, driver_probe_id)
@boolean pa_power_ctrl_enable 是否使能pa电源控制
@int pa_power_pin pa电源引脚
@int pa_power_on_level pa电源电平，1表示高电平，0表示低电平
@int pa_power_on_delay_time_ms pa电源开启延时时间，单位毫秒
@int driver_probe_id 驱动id，在不使用默认驱动时填写，绝大部分情况下都不需要填写。驱动id需要通过audio.make_probe_id合成
@return boolean 成功返回true,否则返回false
@usage
audio_v2.config_pa_power_ctrl(true, 12, 1, 100)
*/
static int l_audio_config_pa_power_ctrl(lua_State *L) {
    luat_audio_driver_ctrl_t *ctrl = NULL;
    luat_audio_driver_probe_t probe;
    probe.probe_id = luaL_optinteger(L, 5, 0);
    if (probe.probe_id) {
        ctrl = luat_audio_driver_probe(&probe);
        if (!ctrl) {
            lua_pushboolean(L, 0);
            return 1;
        }
    } else {
        ctrl = luat_audio_driver_probe(NULL);
    }
    uint8_t pa_power_ctrl_enable = lua_toboolean(L, 1);
    uint8_t pa_power_pin = luaL_optinteger(L, 2, 0);
    uint8_t pa_power_on_level = luaL_optinteger(L, 3, 1);
    uint16_t pa_power_on_delay_time_ms = luaL_optinteger(L, 4, 100);
    LLOGC(luat_audio_debug_flag,"lua config pa power ctrl %d %d %d %d", pa_power_ctrl_enable, pa_power_pin, pa_power_on_level, pa_power_on_delay_time_ms);
    int ret = luat_audio_driver_config_pa_power_ctrl(ctrl, pa_power_ctrl_enable, pa_power_pin, pa_power_on_level, pa_power_on_delay_time_ms);
    lua_pushboolean(L, !ret);
    return 1;
}

/*
配置音频驱动的codec电源控制
@api audio_v2.config_codec_power_ctrl(codec_power_ctrl_enable, codec_power_pin, codec_power_on_level, codec_ready_after_wakeup_time_ms, codec_power_off_delay_time_ms, driver_probe_id)
@boolean codec_power_ctrl_enable 是否使能codec电源控制
@int codec_power_pin codec电源引脚
@int codec_power_on_level codec电源电平，1表示高电平，0表示低电平
@int codec_ready_after_wakeup_time_ms codec电源开启延时时间，单位毫秒
@int codec_power_off_delay_time_ms codec电源关闭延时时间，单位毫秒
@int driver_probe_id 驱动id，在不使用默认驱动时填写，绝大部分情况下都不需要填写。驱动id需要通过audio.make_probe_id合成
@return boolean 成功返回true,否则返回false
@usage
audio_v2.config_codec_power_ctrl(true, 11, 1, 200, 10)
*/
static int l_audio_config_codec_power_ctrl(lua_State *L) {
    luat_audio_driver_ctrl_t *ctrl = NULL;
    luat_audio_driver_probe_t probe;
    probe.probe_id = luaL_optinteger(L, 6, 0);
    if (probe.probe_id) {
        ctrl = luat_audio_driver_probe(&probe);
        if (!ctrl) {
            lua_pushboolean(L, 0);
            return 1;
        }
    } else {
        ctrl = luat_audio_driver_probe(NULL);
    }
    uint8_t codec_power_ctrl_enable = lua_toboolean(L, 1);
    uint8_t codec_power_pin = luaL_optinteger(L, 2, 0);
    uint8_t codec_power_on_level = luaL_optinteger(L, 3, 1);
    uint32_t codec_ready_after_wakeup_time_ms = luaL_optinteger(L, 4, 200);
    uint16_t codec_power_off_delay_time_ms = luaL_optinteger(L, 5, 10);
    LLOGC(luat_audio_debug_flag,"lua config codec power ctrl %d %d %d %d %d", codec_power_ctrl_enable, codec_power_pin, codec_power_on_level, codec_ready_after_wakeup_time_ms, codec_power_off_delay_time_ms);
    int ret = luat_audio_driver_config_codec_power_ctrl(ctrl, codec_power_ctrl_enable, codec_power_pin, codec_power_on_level, codec_ready_after_wakeup_time_ms, codec_power_off_delay_time_ms);
    lua_pushboolean(L, !ret);
    return 1;
}

/**
注册audio事件回调
@api    audio_v2.on(func)
@function 回调方法
@return nil 无返回值
@usage
audio_v2.on(function(request_index, event, param)
    log.info(request_index, event, param)
end)
--回调函数参数说明
---@param int 请求索引
---@param int 事件类型, 见audio_v2.REQUEST_xxx常量
---@param int 附加参数, 根据事件类型不同, 有不同的含义, 有如下组合
event和param可能出现的值
  audio_v2.REQUEST_START 	开始处理请求, param无意义
  audio_v2.REQUEST_NEED_NEW_DATA 	需要新的数据, param无意义
  audio_v2.REQUEST_GET_NEW_DATA 	获取到新数据, param为zbuff序号. 录音才有这个回调
  audio_v2.REQUEST_DECODE_DONE 	    请求处理完成, param无意义
  audio_v2.REQUEST_END 	请求块处理完成, param无意义
*/
static int l_audio_on(lua_State *L) {
	if (_l_audio.cb_ref != 0) {
		luaL_unref(L, LUA_REGISTRYINDEX, _l_audio.cb_ref);
		_l_audio.cb_ref = 0;
	}
	if (lua_isfunction(L, 1)) {
		lua_pushvalue(L, 1);    
		_l_audio.cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
	}
    return 0;
}


/*
配置调试信息输出
@api audio_v2.debug(on_off)@boolean true开 false关
@return
@usage
audio_v2.debug(true)	--开启调试信息输出
audio_v2.debug(false)	--关闭调试信息输出
*/
static int l_audio_set_debug(lua_State *L) {
	luat_audio_debug_switch(lua_toboolean(L, 1));
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_audio_v2[] =
{
	{ "play",			ROREG_FUNC(l_audio_play)},
    { "tts",			ROREG_FUNC(l_audio_tts)},
    { "stop",			ROREG_FUNC(l_audio_stop)},
    { "pause",			ROREG_FUNC(l_audio_pause)},
    { "make_probe_id",			ROREG_FUNC(l_audio_make_probe_id)},
    { "set_default_driver",			ROREG_FUNC(l_audio_set_default_driver)},
    { "get_driver_info",			ROREG_FUNC(l_audio_get_driver_info)},
    { "get_driver_id",			ROREG_FUNC(l_audio_get_driver_id)},
    { "print_probe_id",			ROREG_FUNC(l_audio_print_probe_id)},
    { "config_pa_power_ctrl",		ROREG_FUNC(l_audio_config_pa_power_ctrl)},
    { "config_codec_power_ctrl",			ROREG_FUNC(l_audio_config_codec_power_ctrl)},
    { "on",				ROREG_FUNC(l_audio_on)},
    { "debug",			ROREG_FUNC(l_audio_set_debug)},
    //@const REQUEST_START number audio_v2.on回调函数传入消息值，表示开始处理请求块，可以传入更多数据
    { "REQUEST_START",			ROREG_INT(LUAT_AUDIO_REQUEST_EVENT_START)},
    //@const REQUEST_NEED_NEW_DATA number audio_v2.on回调函数传入消息值，表示请求块需要新的数据，需要传入新的数据
    { "REQUEST_NEED_NEW_DATA",			ROREG_INT(LUAT_AUDIO_REQUEST_EVENT_NEED_NEW_DATA)},
    //@const REQUEST_GET_NEW_DATA number audio_v2.on回调函数传入消息值，表示请求块获取新的数据
    { "REQUEST_GET_NEW_DATA",			ROREG_INT(LUAT_AUDIO_REQUEST_EVENT_GET_NEW_DATA)},
    //@const REQUEST_DECODE_DONE number audio_v2.on回调函数传入消息值，表示请求块解码完成
    { "REQUEST_DECODE_DONE",			ROREG_INT(LUAT_AUDIO_REQUEST_EVENT_DECODE_DONE)},
    //@const REQUEST_END number audio_v2.on回调函数传入消息值，表示请求块处理完成
    { "REQUEST_END",			ROREG_INT(LUAT_AUDIO_REQUEST_EVENT_END)},
    //@const DRIVER_TYPE_NONE number 驱动类型无
    { "DRIVER_TYPE_NONE",			ROREG_INT(LUAT_AUDIO_DRIVER_TYPE_NONE)},
    //@const DRIVER_TYPE_I2S number 驱动类型I2S
    { "DRIVER_TYPE_I2S",			ROREG_INT(LUAT_AUDIO_DRIVER_TYPE_I2S)}, 
    //@const DRIVER_TYPE_DAC number 驱动类型DAC
    { "DRIVER_TYPE_DAC",			ROREG_INT(LUAT_AUDIO_DRIVER_TYPE_DAC)},
    //@const DRIVER_TYPE_ADC number 驱动类型ADC
    { "DRIVER_TYPE_ADC",			ROREG_INT(LUAT_AUDIO_DRIVER_TYPE_ADC)},
    //@const DRIVER_TYPE_USB number 驱动类型USB声卡
    { "DRIVER_TYPE_USB",			ROREG_INT(LUAT_AUDIO_DRIVER_TYPE_USB)},
    //@const DATA_CODEC_TYPE_WAV number 编解码器类型WAV
    { "DATA_CODEC_TYPE_WAV",			ROREG_INT(LUAT_AUDIO_DATA_CODEC_TYPE_WAV)},
    //@const DATA_CODEC_TYPE_AMR_NB number 编解码器类型AMR_NB
    { "DATA_CODEC_TYPE_AMR_NB",			ROREG_INT(LUAT_AUDIO_DATA_CODEC_TYPE_AMR_NB)},
    //@const DATA_CODEC_TYPE_AMR_WB number 编解码器类型AMR_WB       
    { "DATA_CODEC_TYPE_AMR_WB",			ROREG_INT(LUAT_AUDIO_DATA_CODEC_TYPE_AMR_WB)},
    //@const DATA_CODEC_TYPE_TTS number 编解码器类型TTS
    { "DATA_CODEC_TYPE_TTS",			ROREG_INT(LUAT_AUDIO_DATA_CODEC_TYPE_TTS)},
    //@const DATA_CODEC_TYPE_MP3 number 编解码器类型MP3
    { "DATA_CODEC_TYPE_MP3",			ROREG_INT(LUAT_AUDIO_DATA_CODEC_TYPE_MP3)},
    //@const DATA_CODEC_TYPE_OPUS number 编解码器类型OPUS
    { "DATA_CODEC_TYPE_OPUS",			ROREG_INT(LUAT_AUDIO_DATA_CODEC_TYPE_OPUS)},
    //@const DATA_CODEC_TYPE_G711 number 编解码器类型G711
    { "DATA_CODEC_TYPE_G711",			ROREG_INT(LUAT_AUDIO_DATA_CODEC_TYPE_G711)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_audio_v2( lua_State *L ) {
    luat_newlib2(L, reg_audio_v2);
    return 1;
}
#endif