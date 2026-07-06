
/*
@module  cc
@summary VoLTE通话功能
@version 1.0
@date    2024.1.17
@demo    cc
@tag LUAT_USE_VOLTE
@usage
-- 选型手册上支持VoLTE通话功能的模组支持
*/

#include "luat_audio_data_codec.h"
#include "luat_audio_driver.h"
#include "luat_audio_request.h"
#include "luat_base.h"
#ifdef LUAT_USE_AUDIO_V2
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#include "luat_mobile.h"
#include "luat_network_adapter.h"

#include "luat_audio_core.h"
#include "luat_common_api.h"

#define LUAT_LOG_TAG "cc"
#include "luat_log.h"
enum{
	CC_EVENT_HANGUP,
	CC_EVENT_CALL_READY,

    CC_MSG_AUDIO_START = 0,
    CC_MSG_EXTERNAL_SOURCE_DECODE_DONE,
};

//播放控制
typedef struct
{
    luat_audio_request_block_t ring_request;
    luat_audio_request_block_t cc_request;
    luat_audio_extern_source_t extern_source;  // 外部音频源
    luat_audio_common_param_t cc_param;
    luat_fifo_t *record_save_fifo;  // 录音数据FIFO
    luat_fifo_t *play_save_fifo;  // 播放数据FIFO
	luat_rtos_task_handle task_handle;
	luat_zbuff_t *up_buff[2];
	luat_zbuff_t *down_buff[2];
	int record_cb;
    const char *user_incoming_ring_path; //用户来电振铃路径
    const char *user_dial_ring_path; //用户拨号振铃路径
	uint8_t tone_data_cnt;//1秒声音，2秒静音
	volatile uint8_t record_down_zbuff_point;
	volatile uint8_t record_up_zbuff_point;
    uint8_t record_callback_cnt_level;
    uint8_t is_audio_start:1;   //是否开始音频操作
	uint8_t is_play_ring:1;     //是否播放振铃，0:否，可能是在通话中，1:是
    uint8_t is_play_user_ring:1;     //是否播放用户振铃
	uint8_t is_force_ring:1;     //是否强制播放振铃
	uint8_t record_on_off:1;
	uint8_t upload_enable:1;
    uint8_t is_play_extern_source:1;     //是否播放第三方数据源
    uint8_t is_true_start:1;
}luat_cc_ctrl_t;

static luat_cc_ctrl_t _l_cc;

extern const int16_t ringback_8k_data[8000];

static int _l_cc_handler(lua_State *L, void* ptr) {
    (void)ptr;
    //LLOGD("l_uart_handler");
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_pop(L, 1);

    if (_l_cc.record_on_off && _l_cc.record_cb)
    {
    	lua_geti(L, LUA_REGISTRYINDEX, _l_cc.record_cb);
        if (lua_isfunction(L, -1)) {
        	lua_pushboolean(L, msg->arg1);
        	lua_pushinteger(L, msg->arg2);
        	lua_call(L, 2, 0);
        }
    }
    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}

static int _l_cc_audio_start(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (!_l_cc.is_true_start) {
        return 0;
    }
    if (lua_getglobal(L, "sys_pub") != LUA_TFUNCTION) {
        return 0;
    };
    lua_pushstring(L, "CC_IND");
    switch (msg->arg1) {
    case CC_MSG_AUDIO_START:
        if (_l_cc.is_true_start) {
             lua_pushstring(L, "AUDIO_START");
        }
       
        break;
    case CC_MSG_EXTERNAL_SOURCE_DECODE_DONE:
        lua_pushstring(L, "EXT_SRC_DONE");
        _l_cc.is_play_extern_source = 0;
        break;
    }
    lua_call(L, 2, 0);
    return 0;
}

static void _l_cc_audio_ring_request_callback(uint32_t event, uint8_t *data, uint32_t param, struct luat_audio_request_block *request_block) {
    // LLOGD("EVENT: %d", event);
    if (event == LUAT_AUDIO_REQUEST_EVENT_NEED_NEW_DATA) {
        if (_l_cc.is_play_ring && !_l_cc.is_play_user_ring) {   //在播放默认振铃
            if (luat_fifo_check_free_space(_l_cc.ring_request.org_input_data_fifo) >= sizeof(ringback_8k_data)) {
                
                if (!_l_cc.tone_data_cnt) {
                    luat_fifo_write(_l_cc.ring_request.org_input_data_fifo, ringback_8k_data, sizeof(ringback_8k_data));
                    _l_cc.tone_data_cnt = 1;
                } else {
                    uint16_t blank_data[1000] = {0};
                    for (uint8_t i = 0; i < 8; i++) {
                        luat_fifo_write(_l_cc.ring_request.org_input_data_fifo, blank_data, sizeof(blank_data));
                    }
                    _l_cc.tone_data_cnt++;
                    if (_l_cc.tone_data_cnt >= 3) { //2秒空白音之后，播放下一个振铃
                        _l_cc.tone_data_cnt = 0;
                    }
                }
            }
        }
    }

}

static void _l_cc_audio_voice_request_callback(uint32_t event, uint8_t *data, uint32_t param, struct luat_audio_request_block *request_block) {
	luat_zbuff_t *buff;
    rtos_msg_t msg;
    switch (event) {
    case LUAT_AUDIO_REQUEST_EVENT_GET_NEW_DATA:
        if (_l_cc.upload_enable && _l_cc.is_true_start) {    //在通话状态中
            if (_l_cc.record_on_off) { //通话录音中
                uint32_t zbuff_rest_data_len;
                uint32_t fifo_read_len;
                // 录音数据写入用户zbuff
                buff = _l_cc.up_buff[_l_cc.record_up_zbuff_point];
                zbuff_rest_data_len = buff->len - buff->used;
                fifo_read_len = luat_fifo_read(_l_cc.record_save_fifo, buff->addr + buff->used, zbuff_rest_data_len);
                buff->used += fifo_read_len;
                if (buff->used >= buff->len) {  //zbuff满了，需要上传了
                    msg.handler = _l_cc_handler;
                    msg.arg2 = _l_cc.record_up_zbuff_point;
                    msg.arg1 = 0;
                    luat_msgbus_put(&msg, 0);
                    _l_cc.record_up_zbuff_point = !_l_cc.record_up_zbuff_point;
                    _l_cc.up_buff[_l_cc.record_up_zbuff_point]->used = 0;
                }
                // 放音数据写入用户zbuff
                buff = _l_cc.down_buff[_l_cc.record_down_zbuff_point];
                zbuff_rest_data_len = buff->len - buff->used;
                fifo_read_len = luat_fifo_read(_l_cc.play_save_fifo, buff->addr + buff->used, zbuff_rest_data_len);
                buff->used += fifo_read_len;
                if (buff->used >= buff->len) {  //zbuff满了，需要上传了
                    msg.handler = _l_cc_handler;
                    msg.arg2 = _l_cc.record_down_zbuff_point;
                    msg.arg1 = 1;
                    luat_msgbus_put(&msg, 0);
                    _l_cc.record_down_zbuff_point = !_l_cc.record_down_zbuff_point;
                    _l_cc.down_buff[_l_cc.record_down_zbuff_point]->used = 0;
                }
                
            } else {
                luat_fifo_delete_all(_l_cc.record_save_fifo);
                luat_fifo_delete_all(_l_cc.play_save_fifo);
            }
        } else {
            luat_fifo_delete_all(_l_cc.record_save_fifo);
            luat_fifo_delete_all(_l_cc.play_save_fifo);
        }
        break;
    case LUAT_AUDIO_REQUEST_EVENT_START:
        if (_l_cc.upload_enable && _l_cc.record_on_off) {
            _l_cc.cc_request.play_save_fifo = _l_cc.play_save_fifo;
            _l_cc.cc_request.is_save_play_data = 1;
        }
        break;
    case LUAT_AUDIO_REQUEST_EVENT_EXTERNAL_SOURCE_DECODE_DONE:
        msg.handler = _l_cc_audio_start;
        msg.arg1 = CC_MSG_EXTERNAL_SOURCE_DECODE_DONE;
        luat_msgbus_put(&msg, 0);
        break;
    }
}

static int _l_cc_play_default_ring(void) {
    luat_audio_common_param_t common_param = {0};
    common_param.sample_rate = 8000;
    common_param.channel_nums = 1;
    common_param.data_align = 2;
    _l_cc.is_play_ring = 1;
    _l_cc.is_audio_start = 1;
    return luat_audio_request_play_stream(&_l_cc.ring_request, NULL, luat_audio_data_codec_find(LUAT_AUDIO_DATA_CODEC_TYPE_RAW), &common_param, 2000, 200, 0, _l_cc_audio_ring_request_callback, &_l_cc.ring_request, NULL);
}

static void _l_cc_volte_task(void *param){
	luat_event_t event;
    int ret = - 1;
	while (1){
		luat_rtos_event_recv(_l_cc.task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
		switch(event.id)
		{
		case CC_EVENT_HANGUP:
			luat_mobile_hangup_call(event.param1);
			break;
        }
	}
}

/**
获取最后一次通话的号码
@api cc.lastNum()
@return string 获取最后一次通话的号码
 */
static int l_cc_get_last_call_num(lua_State* L) {
    char number[64] = {0};
    luat_mobile_get_last_call_num(number, sizeof(number));
    lua_pushlstring(L, (const char*)(number),strlen(number));
    return 1;
}

/**
拨打电话
@api cc.dial(sim_id, number)
@number sim_id
@string 电话号码
@return bool 拨打电话成功与否
 */
static int l_cc_make_call(lua_State* L) {
    uint8_t sim_id = luaL_optinteger(L, 1, 0);
    size_t len = 0;
	const char* number = luaL_checklstring(L, 2, &len);
    lua_pushboolean(L, !luat_mobile_make_call(sim_id, (char*)number, len));
    return 1;
}

/**
挂断电话
@api cc.hangUp(sim_id)
@number sim_id
 */
static int l_cc_hangup_call(lua_State* L) {
    uint8_t sim_id = luaL_optinteger(L, 1, 0);
    luat_rtos_event_send(_l_cc.task_handle, CC_EVENT_HANGUP, sim_id, 0, 0, 0);
    return 0;
}

/**
接听电话
@api cc.accept(sim_id)
@number sim_id
@return bool 接听电话成功与否
 */
static int l_cc_answer_call(lua_State* L) {
    uint8_t sim_id = luaL_optinteger(L, 1, 0);
    lua_pushboolean(L, !luat_mobile_answer_call(sim_id));
    return 1;
}

/**
初始化电话功能
@api cc.init(multimedia_id)
@number multimedia_id 多媒体id
@return bool 成功与否
 */
static int l_cc_speech_init(lua_State* L) {
    _l_cc.record_save_fifo = luat_fifo_create(13);
    _l_cc.play_save_fifo = luat_fifo_create(13);
    if (!_l_cc.record_save_fifo || !_l_cc.play_save_fifo)
    {
        LLOGE("create fifo failed");
        luat_fifo_destroy(_l_cc.record_save_fifo);
        luat_fifo_destroy(_l_cc.play_save_fifo);
        _l_cc.record_save_fifo = NULL;
        _l_cc.play_save_fifo = NULL;
        lua_pushboolean(L, 0);
        return 1;
    }
    luat_rtos_task_create(&_l_cc.task_handle, 4*1024, 100, "volte", _l_cc_volte_task, NULL, 0);
    lua_pushboolean(L, 1);
    return 1;
}

/**
录音通话
@api cc.record(on_off,upload_zbuff1, upload_zbuff2, download_zbuff1, download_zbuff2)
@boolean 开启关闭通话录音功能，false或者nil关闭，其他开启
@zbuff 上行数据保存区1,zbuff创建时的空间容量必须是640的倍数,下同
@zbuff 上行数据保存区2,和上行数据保存区1组成双缓冲区
@zbuff 下行数据保存区1
@zbuff 下行数据保存区2,和下行数据保存区1组成双缓冲区
@return bool 成功与否，如果处于通话状态，会失败
@usage
buff1 = zbuff.create(6400,0,zbuff.HEAP_AUTO)
buff2 = zbuff.create(6400,0,zbuff.HEAP_AUTO)
buff3 = zbuff.create(6400,0,zbuff.HEAP_AUTO)
buff4 = zbuff.create(6400,0,zbuff.HEAP_AUTO)
cc.on("record", function(type, buff_point)
 log.info(type, buff_point) -- type==true是下行数据，false是上行数据 buff_point指示双缓存中返回了哪一个
end)
cc.record(true, buff1, buff2, buff3, buff4)
*/
static int l_cc_record_call(lua_State* L) {
    _l_cc.record_on_off = lua_toboolean(L, 1);
    if (_l_cc.record_on_off)
    {
    	_l_cc.up_buff[0] = (luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE);
    	_l_cc.up_buff[1] = (luat_zbuff_t *)luaL_checkudata(L, 3, LUAT_ZBUFF_TYPE);
    	_l_cc.down_buff[0] = (luat_zbuff_t *)luaL_checkudata(L, 4, LUAT_ZBUFF_TYPE);
    	_l_cc.down_buff[1] = (luat_zbuff_t *)luaL_checkudata(L, 5, LUAT_ZBUFF_TYPE);
    }
    else
    {
    	_l_cc.up_buff[0] = NULL;
    	_l_cc.up_buff[1] = NULL;
    	_l_cc.down_buff[0] = NULL;
    	_l_cc.down_buff[1] = NULL;
    }

    lua_pushboolean(L, 1);
    return 1;
}

/**
获取当前通话质量
@api cc.quality()
@return int 1为低音质(8K)，2为高音质(16k)，0没有在通话,其他值为具体的音频采样率
 */
static int l_cc_get_quality(lua_State* L) {
    if (!_l_cc.upload_enable)
    {
        lua_pushinteger(L, 0);
        return 1;
    } else {
        switch (_l_cc.cc_param.sample_rate) {
            case 8000:
                lua_pushinteger(L, 1);
                break;
            case 16000:
                lua_pushinteger(L, 2);
                break;
            default:
                lua_pushinteger(L, _l_cc.cc_param.sample_rate);
                break;
        }
    }
    return 1;
}

/**
注册通话回调
@api    cc.on(event, func)
@string 事件名称 音频录音数据为"record"
@function 回调方法
@return nil 无返回值
@usage
cc.on("record", function(type, buff_point)
 log.info(type, buff_point) -- type==true是下行数据，false是上行数据 buff_point指示双缓存中返回了哪一个
end)
*/
static int l_cc_on(lua_State *L) {
    const char* event = luaL_checkstring(L, 1);
    if (!strcmp("record", event)) {
        if (_l_cc.record_cb != 0) {
            luaL_unref(L, LUA_REGISTRYINDEX, _l_cc.record_cb);
            _l_cc.record_cb = 0;
        }
        if (lua_isfunction(L, 2)) {
            lua_pushvalue(L, 2);
            _l_cc.record_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        }
    }
    return 0;
}

/*
通话中附加额外的音频数据，额外音频的参数必须和通话的参数一致，否则会失败而没有任何作用
@api cc.extern_source(source, is_add_record, codec_id, sample_rate, data_bits, channel_nums, is_signed)
@table/string/zbuff/nil 输入数据，table表示播放文件，string表示播放tts，zbuff表示播放音频数据，如果只播放一个文件也要用table,nil表示停止当前第三方数据播放
@boolean 是否添加到上行通道，true添加到上行通道，false添加到下行通道，默认true，往对端播放第三方数据源，目前只支持上行通道
@boolean 是否在文件解码失败后停止解码，只有在连续播放多个文件时才有用，默认true，遇到解码错误自动停止
@int 解码器id，见audio_v2.DATA_CODEC_TYPE_XXX，如果留空则通过输入数据自行判断
@int 采样率，如果指定解码器是RAW，不能留空
@int 数据位数，8,16,24,32，如果指定解码器是RAW，不能留空
@int 通道数，1,2，如果指定解码器是RAW，不能留空
@boolean 是否有符号数据，默认true
@return boolean 成功返回true,否则返回false
@usage
cc.extern_source({"/test_16k.mp3"})
*/
static int l_cc_extern_source(lua_State *L) {
    int result = -1;
    const char *data = NULL;
    size_t len = 0;
    size_t file_nums = 0;
    size_t path_len = 0;
    luat_audio_play_file_info_t *info = NULL;
    uint8_t is_add_record = 1;
    uint8_t is_error_stop = 1;
    if (_l_cc.is_play_extern_source) {
        LLOGE("cc extern source is busy");
        goto DONE;
    }
    if (!_l_cc.is_true_start) {
        LLOGE("cc is not true start");
        goto DONE;
    }
    luat_audio_common_param_t common_param = {0};
    common_param.sample_rate = luaL_optinteger(L, 5, 0);
    uint8_t data_bits = luaL_optinteger(L, 6, 16);
    common_param.channel_nums = luaL_optinteger(L, 7, 1);
    common_param.data_align = data_bits / 8;
    if (lua_isboolean(L, 8)) {
        common_param.is_signed = lua_toboolean(L, 8);
    }
    else {
        common_param.is_signed = 1;
    }

    if (lua_isboolean(L, 4)) {
        is_error_stop = lua_toboolean(L, 4);
    } else {
        is_error_stop = 1;
    }

    const luat_audio_data_codec_opts_t *codec_opts = NULL;
    uint8_t org_codec_id = luaL_optinteger(L, 3, LUAT_AUDIO_DATA_CODEC_TYPE_MAX);
    uint8_t codec_id = org_codec_id &~ LUAT_AUDIO_DATA_CODEC_TYPE_HW;
    if (codec_id < LUAT_AUDIO_DATA_CODEC_TYPE_MAX) {
        codec_opts = luat_audio_data_codec_find(org_codec_id);
    }
    if (lua_isnil(L, 1)) {
        if (_l_cc.is_play_extern_source) {
            luat_audio_request_delete_source(&_l_cc.extern_source);
            _l_cc.is_play_extern_source = 0;   
        } 
        result = LUAT_ERROR_NONE;
        goto DONE;
    }
    if (LUA_TSTRING == (lua_type(L, 1))) {
        
        data = lua_tolstring(L, 1, &len);//取出字符串数据
        result = luat_audio_request_add_source_tts(&_l_cc.extern_source, data, len, is_add_record, &_l_cc.extern_source);

    } else if(lua_isuserdata(L, 1)) {
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 1, LUAT_ZBUFF_TYPE));
        info = (luat_audio_play_file_info_t *)luat_heap_calloc(1, sizeof(luat_audio_play_file_info_t));
        if (!info) {
            LLOGE("lua extern source malloc info failed");
            goto DONE;
        }

        info[0].rom_data = buff->addr;
        info[0].fail_continue = !is_error_stop;
        info[0].rom_data_len = buff->used;

        result = luat_audio_request_add_source_files(&_l_cc.extern_source, info, 1, codec_opts, is_add_record, &_l_cc.extern_source);

    } else if (lua_istable(L, 1)) {
    	file_nums = lua_rawlen(L, 1); //返回数组的长度
        info = (luat_audio_play_file_info_t *)luat_heap_calloc(file_nums, sizeof(luat_audio_play_file_info_t));
        if (!info) {
            LLOGE("lua extern source malloc info failed");
            goto DONE;
        }
        for (size_t i = 0; i < file_nums; i++) {
            lua_rawgeti(L, 1, 1 + i);
            info[i].path = (void*)lua_tolstring(L, -1, &path_len);
            info[i].fail_continue = !is_error_stop;
            info[i].rom_data_len = 0;
            lua_pop(L, 1); //将刚刚获取的元素值从栈中弹出
        }
        result = luat_audio_request_add_source_files(&_l_cc.extern_source, info, file_nums, codec_opts, is_add_record, &_l_cc.extern_source);
    }
    if (!result) {
        _l_cc.is_play_extern_source = 1;
    } else {
        LLOGE("cc extern source play failed");
    }
DONE:
    if (info) {
        luat_heap_free(info);
    }
    lua_pushboolean(L, !result);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_cc[] =
{
    { "init" ,      ROREG_FUNC(l_cc_speech_init)},
    { "dial" ,      ROREG_FUNC(l_cc_make_call)},
    { "accept" ,    ROREG_FUNC(l_cc_answer_call)},
    { "hangUp" ,    ROREG_FUNC(l_cc_hangup_call)},
    { "lastNum" ,   ROREG_FUNC(l_cc_get_last_call_num)},
	{ "quality" ,   ROREG_FUNC(l_cc_get_quality)},
    { "on" ,        ROREG_FUNC(l_cc_on)},
    { "record", 	ROREG_FUNC(l_cc_record_call)},
    { "extern_source", ROREG_FUNC(l_cc_extern_source)},
	{ NULL,         ROREG_INT(0)}
};

LUAMOD_API int luaopen_cc( lua_State *L ) {
    luat_newlib2(L, reg_cc);
    return 1;
}

void luat_cc_start_upload(void)
{
    _l_cc.upload_enable = 1;
    luat_audio_request_record_pause(&_l_cc.cc_request, 0);
}

void luat_cc_start_audio(uint8_t *play_buff_byte, uint32_t one_play_block_len, uint32_t play_block_cnt, uint32_t sample_rate, uint8_t data_align, uint8_t channel_nums, uint8_t record_callback_cnt_level, uint8_t need_upload, uint8_t true_start)
{
    _l_cc.is_true_start = true_start;
	_l_cc.upload_enable = need_upload;
    _l_cc.record_callback_cnt_level = record_callback_cnt_level;
    _l_cc.cc_param.sample_rate = sample_rate;
    _l_cc.cc_param.data_align = data_align;
    _l_cc.cc_param.channel_nums = channel_nums;
    int ret;
    const luat_audio_data_codec_opts_t* codec_opts = luat_audio_data_codec_find(LUAT_AUDIO_DATA_CODEC_TYPE_CC);
    if (!codec_opts) {
        LLOGE("CC_EVENT_VOICE_START codec_opts is NULL");
        return;
    }
    ret = luat_audio_request_speech(&_l_cc.cc_request, NULL, codec_opts, codec_opts, &_l_cc.cc_param, _l_cc.record_save_fifo, _l_cc.record_callback_cnt_level, (uint32_t *)play_buff_byte, one_play_block_len, play_block_cnt, _l_cc_audio_voice_request_callback, &_l_cc.cc_request, NULL);
    if (!ret) {
        if (_l_cc.upload_enable) {
            rtos_msg_t msg;
            msg.handler = _l_cc_audio_start;
            msg.arg1 = CC_MSG_AUDIO_START;
            luat_msgbus_put(&msg, 0);
        } else {
            luat_audio_request_record_pause(&_l_cc.cc_request, 1);
        }
        _l_cc.is_audio_start = 1;
        LLOGD("CC_EVENT_VOICE_START request speech success, update upload enable %d", _l_cc.upload_enable);
    } else {
        LLOGE("CC_EVENT_VOICE_START request speech failed, ret %d", ret);
    }
}

void luat_cc_play_tone(uint32_t param)
{   
    int ret = LUAT_ERROR_NONE;
    switch (param)
    {
    case LUAT_MOBILE_CC_PLAY_STOP:
        _l_cc.upload_enable = 0;
        luat_audio_request_record_pause(&_l_cc.cc_request, 1);
        _l_cc.tone_data_cnt = 0;
        _l_cc.is_true_start = 0;


        if (_l_cc.ring_request.org_input_data_fifo) {
            LLOGD("VOLTE_EVENT_PLAY_STOP stop play ring");
            luat_audio_request_cancel_immediate(&_l_cc.ring_request);
        }
        if (_l_cc.cc_request.org_input_data_fifo) {
            LLOGD("VOLTE_EVENT_PLAY_STOP stop play voice");
            luat_audio_request_cancel_immediate(&_l_cc.cc_request);
        }

        _l_cc.is_audio_start = 0;
        _l_cc.is_play_ring = 0;
        luat_audio_driver_stop(luat_audio_driver_probe(NULL));
        break;
    case LUAT_MOBILE_CC_PLAY_DIAL_TONE:
        if (!_l_cc.is_play_user_ring) {
            ret = _l_cc_play_default_ring();
        }
        break;
    case LUAT_MOBILE_CC_PLAY_CALL_INCOMINGCALL_RINGING:
        if (!_l_cc.is_play_user_ring) {
            ret = _l_cc_play_default_ring();
        }
        break;
    default:
        ret = _l_cc_play_default_ring();
        break;
    }
    if (ret < 0) {
        LLOGE("VOLTE_EVENT_PLAY_TONE play default ring failed, ret %d", ret);
        _l_cc.is_audio_start = 0;
        _l_cc.is_play_ring = 0;
    } else {
    }
}
#endif