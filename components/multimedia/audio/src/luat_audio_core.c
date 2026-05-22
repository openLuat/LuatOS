#include "luat_audio_data_codec.h"
#include "luat_audio_define.h"
#include "luat_audio_driver.h"
#include "luat_base.h"
#include "luat_audio_core.h"
#include "luat_audio_request.h"
#include "luat_audio_channel.h"
#include "luat_common_api.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_rtos_legacy.h"
#include <string.h>
#include <sys/_types.h>
#define LUAT_LOG_TAG "audio_core"
#include "luat_log.h"
#include "luat_gpio.h"

unsigned char luat_audio_debug_flag;	// 调试标志位，默认1，开启调试
enum {
	LUAT_AUDIO_EV_TX_NEED_DATA = 0x01,	// 放音需要更多数据事件
	LUAT_AUDIO_EV_TX_NO_DATA,			// 放音数据完成事件
	LUAT_AUDIO_EV_RX_ENOUGH_DATA,		// 接收数据完成事件
	LUAT_AUDIO_EV_REQUEST,			// 请求启动事件
	LUAT_AUDIO_EV_REQUEST_CANCEL,	// 请求取消事件
	LUAT_AUDIO_EV_TTS_RUN = 0x01,
};

typedef struct
{
	luat_llist_head request_block_list;		// 请求块列表	
	luat_audio_driver_ctrl_t driver_ctrl[LUAT_AUDIO_DRIVER_MAX];
	luat_audio_channel_t channel[LUAT_AUDIO_DRIVER_MAX];
	luat_audio_request_block_t *current_request_block; // 当前正在处理的请求块
	luat_rtos_task_handle common_task_handle;
	luat_rtos_task_handle tts_task_handle;
	void *request_lock;	// 请求块列表操作保护锁
	void *tts_wait_sem;	// tts任务等待信号量
	uint32_t next_request_id;		// 下一个请求id
	uint8_t default_driver_index;	// 默认驱动索引
	uint8_t all_driver_nums;				// 已注册的音频驱动匹配结构数量
	uint8_t decode_is_running:1;			// 解码标志位
}luat_audio_ctrl_t;

static luat_audio_ctrl_t _luat_audio;

#ifdef LUAT_CSDK_CONFIG_FILE
#include LUAT_CSDK_CONFIG_FILE
#endif

#ifndef __LUAT_C_CODE_IN_ISR__
#define __LUAT_C_CODE_IN_ISR__
#endif

extern void soc_printf(char *fmt, ...);

static __LUAT_C_CODE_IN_ISR__ void _audio_play_next_block(struct luat_audio_driver_ctrl *ctrl)
{
	volatile uint32_t next_play_cnt;
	ctrl->last_play_cnt = ctrl->current_play_cnt;
	ctrl->current_play_cnt = (ctrl->current_play_cnt + 1) & 3;
	next_play_cnt = (ctrl->current_play_cnt + 1) & 3;
	uint8_t *next_play_buff = ctrl->play_buff_byte + ctrl->one_play_block_len * next_play_cnt;
	if (ctrl->data_channel->user_play_stop || !ctrl->audio_output_enable) {	// 播放状态为停止，播放空白音
		ctrl->opts->fill(ctrl, next_play_buff, ctrl->one_play_block_len, ctrl->opts->is_signed, ctrl->data_channel->data_align);
		return;
	}
	// play数据从这里读取，只有1个消费者，所以不需要加锁
	uint32_t read_len = luat_fifo_read(ctrl->data_channel->play_fifo, next_play_buff, ctrl->one_play_block_len);

	if (read_len < ctrl->one_play_block_len) { 	// fifo没有完整的1个block
		ctrl->opts->fill(ctrl, next_play_buff + read_len, ctrl->one_play_block_len - read_len, ctrl->opts->is_signed, ctrl->data_channel->data_align);
	}
	if (!_luat_audio.current_request_block) {  // 没有请求块，直接返回
		return;
	}
	// soc_printf("read_len %u %d-%d-%x,%u,%x,%d", read_len, ctrl->current_play_cnt, next_play_cnt,next_play_buff,
	// 	ctrl->one_play_block_len, _luat_audio.current_request_block,_luat_audio.current_request_block->is_wait_play_end);
	if (_luat_audio.current_request_block->is_wait_play_end && (read_len >= ctrl->one_play_block_len)) {
		return;
	}
	if (!_luat_audio.decode_is_running && luat_fifo_check_free_space(ctrl->data_channel->play_fifo) >= ctrl->data_channel->play_fifo_low_level) { // fifo剩余数据不足低水位，需要请求更多数据
		luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_TX_NEED_DATA, (uint32_t)ctrl, 0, 0, 0);
	}
}

LUAT_WEAK __LUAT_C_CODE_IN_ISR__ void luat_audio_driver_event_callback(uint32_t event, uint8_t *rx_data, uint32_t param, struct luat_audio_driver_ctrl *ctrl)
{
	uint32_t rest_data_len;
	switch (event) {
	case LUAT_AUDIO_DRIVER_EVENT_TX_ONE_BLOCK_DONE:
		if (ctrl->opts->support_full_loop) {
			return;
		}
		_audio_play_next_block(ctrl);
		break;
	case LUAT_AUDIO_DRIVER_EVENT_RX_ONE_BLOCK_DONE:
		if (!ctrl->data_channel->record_request_block) {
			return;
		}
		if (ctrl->data_channel->record_jump_cnt) {
			ctrl->data_channel->record_jump_cnt--;
			return;
		}
		rest_data_len = luat_fifo_check_free_space(ctrl->data_channel->record_request_block->record_data_fifo);
		if (param < rest_data_len) {
			luat_fifo_write(ctrl->data_channel->record_request_block->record_data_fifo, rx_data, param);
		} else {
			ctrl->data_channel->error_record_overflow = 1;
		}
		if (luat_fifo_check_used_space(ctrl->data_channel->record_request_block->record_data_fifo) >= ctrl->data_channel->record_request_block->record_fifo_enough_data_level) {	// 录音数据足够，发送事件
			luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_RX_ENOUGH_DATA, (uint32_t)ctrl, 0, 0, 0);
		}
		if (ctrl->opts->support_full_loop) {
			_audio_play_next_block(ctrl);
		}
		break;
	default:
		break;
	}
}

static void _audio_find_next_request_block(void)
{
	if (luat_llist_empty(&_luat_audio.request_block_list)) {
		LLOGC(luat_audio_debug_flag, "no request block");
		return;
	}
	_luat_audio.current_request_block = (luat_audio_request_block_t *)_luat_audio.request_block_list.next;
	luat_llist_del(&_luat_audio.current_request_block->node);
}


static int _audio_add_request(void *node, void *param)
{
	luat_audio_request_block_t *old_req = (luat_audio_request_block_t *)node;
	luat_audio_request_block_t *new_req = (luat_audio_request_block_t *)param;
	if (new_req->priority > old_req->priority)
	{
		LLOGC(luat_audio_debug_flag, "add request id %d priority %d before request id %d priority %d", new_req->request_id, new_req->priority, old_req->request_id, old_req->priority);
		luat_llist_add_tail(&new_req->node, &old_req->node);
		return LUAT_LIST_FIND;
	}
	return LUAT_LIST_PASS;
}

static int _audio_tts_output_callback(void *data, uint32_t param, void *user_data)
{
	luat_audio_request_block_t *request_block = (luat_audio_request_block_t *)user_data;
	int ret;
	if (data) {
		while(!request_block->is_user_stop && (luat_fifo_check_free_space(request_block->data_channel->play_fifo) >= request_block->data_channel->play_fifo_high_level))
		{
			LLOGC(luat_audio_debug_flag, "tts wait fifo space %d", luat_fifo_check_free_space(request_block->data_channel->play_fifo));
			if (luat_rtos_semaphore_take(_luat_audio.tts_wait_sem, 1000)) {
				LLOGE("tts wait timeout");
				return -1;
			}
		}
		if (request_block->is_user_stop) {
			LLOGC(luat_audio_debug_flag, "tts user stop, stop");
			return -1;
		}
		uint32_t written_bytes;
		ret = luat_audio_channel_write_data(request_block->data_channel, data, param, &written_bytes, request_block->codec.common_param.is_signed, request_block->codec.common_param.data_align, request_block->codec.common_param.channel_nums);		
		if (ret) {
			request_block->is_error_stop = 1;
			LLOGE("tts write data failed");
			return -1;
		}
	} else {
		ret = luat_audio_driver_start(request_block->data_channel->driver_ctrl, &request_block->codec.common_param, request_block->play_buff, request_block->one_block_len, request_block->block_nums);
		if (ret) {
			LLOGE("tts start driver failed");
			return -1;
		}
	}
	return LUAT_ERROR_NONE;
}

/**
 * @brief 请求块完成
 */
static void _audio_request_finish(void)
{
	void *sem = _luat_audio.current_request_block->done_sem;
	luat_audio_request_deinit(_luat_audio.current_request_block);
	_luat_audio.current_request_block->cb(LUAT_AUDIO_REQUEST_EVENT_END, NULL, 0, _luat_audio.current_request_block);
	_luat_audio.current_request_block = NULL;
	if (sem) {
		luat_mutex_unlock(sem);
	}
	luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
}

static void luat_audio_tts_task(void *param)
{
	luat_event_t out_event;
	luat_audio_request_block_t *tts_request_block;
	for(;;)
	{
		luat_rtos_event_recv(_luat_audio.tts_task_handle, 0, &out_event, NULL, 0);
		switch (out_event.id) {
		case LUAT_AUDIO_EV_TTS_RUN:
			tts_request_block = (luat_audio_request_block_t *)out_event.param1;
			if (tts_request_block->request_id == _luat_audio.current_request_block->request_id) {
				if (tts_request_block->codec.opts->tts_decode(&tts_request_block->codec, tts_request_block->tts_data, tts_request_block->tts_data_size, tts_request_block)) {
					tts_request_block->is_error_stop = 1;
				}
				_audio_request_finish();
			}
			break;
		default:
			break;
		}
	}
}

/**
 * @brief 从文件读取数据到FIFO
 * @param decode_file 解码文件信息
 * @param input_data_fifo 输入数据FIFO
 * @param is_file_end 是否为结束请求
 * @return int 读取的字节数
 */
static int _audio_data_read_to_fifo(luat_audio_play_file_info_t *decode_file, luat_fifo_t *input_data_fifo, uint8_t *is_file_end)
{
	uint32_t need_len = luat_fifo_check_free_space(input_data_fifo);
    uint32_t done_len = 0;
    uint32_t read_len;
    if (!decode_file->rom_data_len) {
        uint8_t temp[1024];
        int ret;
        while (done_len < need_len) {
            read_len = ((need_len - done_len) > sizeof(temp))? sizeof(temp) : (need_len - done_len);
            ret = luat_fs_fread(temp, read_len, 1, decode_file->fd);
            if (ret < 0) {
				*is_file_end = 1;
                return -LUAT_ERROR_OPERATION_FAILED;
            } else {
                done_len += ret;
                if (ret) {
                    luat_fifo_write(input_data_fifo, temp, ret);
                }
                if (ret < read_len) {
					*is_file_end = 1;
                    break;
                }
            }
        }
        return done_len;
    } else {
        read_len = ((decode_file->rom_data_len - decode_file->rom_data_offset) > need_len) ? need_len : (decode_file->rom_data_len - decode_file->rom_data_offset);
        luat_fifo_write(input_data_fifo, decode_file->rom_data + decode_file->rom_data_offset, read_len);
        decode_file->rom_data_offset += read_len;
		if (decode_file->rom_data_offset >= decode_file->rom_data_len) {
			*is_file_end = 1;
		}
        return read_len;
    }
}

/**
 * @brief 从文件读取数据到缓冲区
 * @param decode_file 解码文件信息
 * @param buffer 缓冲区
 * @param need_len 读取的字节数
 * @return int 读取的字节数
 */
static int _audio_data_read_to_buffer(luat_audio_play_file_info_t *decode_file, uint8_t *buffer, uint32_t need_len)
{
    if (!decode_file->rom_data_len) {
		return luat_fs_fread(buffer, need_len, 1, decode_file->fd);
    } else {
        uint32_t read_len = ((decode_file->rom_data_len - decode_file->rom_data_offset) > need_len) ? need_len : (decode_file->rom_data_len - decode_file->rom_data_offset);
		memcpy(buffer, decode_file->rom_data + decode_file->rom_data_offset, read_len);
        decode_file->rom_data_offset += read_len;
        return read_len;
    }
}

/**
 * @brief 文件定位
 * @param decode_file 解码文件信息
 * @param offset 宁位偏移量
 * @param origin 宁位参考点
 * @return int 定位后的偏移量
 */
static int _audio_data_seek(luat_audio_play_file_info_t *decode_file, int offset, int origin)
{
    if (!decode_file->rom_data_len) {
        return luat_fs_fseek(decode_file->fd, offset, origin);
    } else {
		switch(origin)
		{
		case SEEK_SET:
			if (offset < decode_file->rom_data_len) {
				decode_file->rom_data_offset = offset;
			} else {
				decode_file->rom_data_offset = decode_file->rom_data_len;
			}
			break;
		case SEEK_CUR:
			if ((offset + decode_file->rom_data_offset) < decode_file->rom_data_len) {
				decode_file->rom_data_offset += offset;
			} else {
				decode_file->rom_data_offset = offset;
			}
			break;
		case SEEK_END:
			decode_file->rom_data_offset = decode_file->rom_data_len - offset;
			break;
		}
		return decode_file->rom_data_offset;
    }
}

/**
 * @brief 解码当前请求块的播放信息
 * @param request_block 请求块
 */
static void _audio_decode_current_request_play_info(luat_audio_request_block_t *request_block)
{
	uint8_t error = 0;
	int ret;
	request_block->codec.common_param.sample_rate = 0;
	while (!request_block->codec.common_param.sample_rate && !request_block->is_error_stop && !request_block->is_user_stop && request_block->file_done_cnt < request_block->file_info_cnt) {
		if (request_block->codec.opts) {
			//已经指定了解码器则自动处理
			if (luat_audio_get_play_info_from_file(&request_block->codec, &request_block->file_info[request_block->file_done_cnt])) {
				LLOGE("no play info found for file %d", request_block->file_done_cnt);
				error = 1;
			} else {
				LLOGC(luat_audio_debug_flag, "find play info %u,%u,%u", request_block->codec.common_param.sample_rate, request_block->codec.common_param.data_align, request_block->codec.common_param.channel_nums);
			}
		} else {
			luat_audio_data_codec_t codec = {0};
			codec.common_param.driver_work_mode = LUAT_AUDIO_DRIVER_MODE_PLAY;
			uint8_t codec_type = 255;
			//没有指定解码器则需要搜索所有的解码器，解码尝试分析播放参数，找到合适的解码器
			for (int i = 0; i < LUAT_AUDIO_DATA_CODEC_TYPE_MAX; i++) {
				codec.opts = (luat_audio_data_codec_opts_t *)luat_audio_data_codec_find(i);
				if (!codec.opts->support_detect) {
					continue;
				}
				if (LUAT_ERROR_NONE == luat_audio_get_play_info_from_file(&codec, &request_block->file_info[request_block->file_done_cnt])) {
					LLOGC(luat_audio_debug_flag, "auto search find codec %d", i);
					codec_type = i;
					break;
				}
			}
			if (255 == codec_type) {
				LLOGE("no play info found for file %d", request_block->file_done_cnt);
				error = 1;
			}
			if (!error) {
				// 绑定解码器
				ret = luat_audio_data_codec_bind(&request_block->codec, luat_audio_data_codec_find(codec_type), request_block);
				if (ret) {
					LLOGE("bind codec %d failed, ret %d", codec_type, ret);
					error = 1;
				} else {
					if (request_block->codec.opts->init(&request_block->codec, 0)) {
						LLOGE("init codec %d failed", codec_type);
						luat_audio_data_codec_deinit(&request_block->codec);
						luat_audio_data_codec_unbind(&request_block->codec);
						error = 1;
					} else {
						request_block->codec.common_param = codec.common_param;
						LLOGC(luat_audio_debug_flag, "find codec %d, play info %u,%u,%u", codec_type, request_block->codec.common_param.sample_rate, request_block->codec.common_param.data_align, request_block->codec.common_param.channel_nums);
					}
				}
			}
		}
		if (error) {
			if (request_block->file_info[request_block->file_done_cnt].fail_continue) {
				LLOGC(luat_audio_debug_flag, "continue decode file %d", request_block->file_done_cnt);
				request_block->file_done_cnt++;
				continue;
			} else {
				request_block->is_error_stop = 1;
			}
		} else {
			return;
		}
	}
	LLOGE("no play info found for request id %d", request_block->request_id);
	request_block->is_error_stop = 1;
}

/**
 * @brief 解码文件开始
 * @param request_block 请求块
 */
static void _audio_decode_file_start(luat_audio_request_block_t *request_block)
{
	luat_fifo_destroy(request_block->org_input_data_fifo);
	request_block->org_input_data_fifo = luat_fifo_create(LUAT_AUDIO_DATA_CODEC_INPUT_FIFO_DEFAULT_SIZE_POWER);
	if (!request_block->org_input_data_fifo) {
		LLOGE("create org input data fifo failed, no memory");
		request_block->is_error_stop = 1;
	}
	_audio_decode_current_request_play_info(request_block);
	if (request_block->is_error_stop || request_block->is_user_stop) {
		return;
	}
	luat_buffer_reinit(&request_block->out_buffer, request_block->codec.opts->decode_max_output_len * 3);
	if (!request_block->out_buffer.data) {
		LLOGE("create out buffer failed, no memory");
		request_block->is_error_stop = 1;
	}
	request_block->is_stream_end = 0;
}

static void _audio_decode_stream_to_fifo(luat_audio_request_block_t *request_block)
{
	if (request_block->codec.opts) { //已经指定了解码器则自动处理
		while (!request_block->is_error_stop && !request_block->is_user_stop && !request_block->is_stream_end && (luat_fifo_check_used_space(request_block->data_channel->play_fifo) < request_block->data_channel->play_fifo_high_level)) {	//fifo剩余数据不足高水位，需要请求更多数据
			luat_audio_data_codec_decode_once(&request_block->codec, 
				request_block->org_input_data_fifo, 
				&request_block->out_buffer, 
				request_block->is_stream_end);
			if (request_block->out_buffer.pos) {
				uint32_t written_bytes;
				int ret = luat_audio_channel_write_data(request_block->data_channel, request_block->out_buffer.data, request_block->out_buffer.pos, &written_bytes, request_block->codec.common_param.is_signed, request_block->codec.common_param.data_align, request_block->codec.common_param.channel_nums);	
				if (ret) {
					request_block->is_error_stop = 1;
					LLOGE("write data failed ret %d", ret);
					return;
				}
				request_block->out_buffer.pos -= written_bytes;
			}
			uint32_t rest_bytes = luat_fifo_check_used_space(request_block->org_input_data_fifo);
			if (request_block->is_stream_end) { // 流结束
				if (!rest_bytes) { // 流结束，且fifo数据为空，结束解码循环
					break;
				}
			} else {
				if (rest_bytes < request_block->codec.opts->decode_min_input_len) { // 流未结束，且fifo数据不足最小解码输入长度，结束解码循环
					break;
				}
			}
		}
	}
}

static void _audio_decode_file_to_fifo(luat_audio_request_block_t *request_block)
{
	int ret = 0;
	uint8_t is_file_end = 0;
	uint8_t stop = 0;
	uint8_t error  = 0;
	while (!stop && !request_block->is_error_stop && !request_block->is_user_stop && (luat_fifo_check_used_space(request_block->data_channel->play_fifo) < request_block->data_channel->play_fifo_high_level)) {	//fifo剩余数据不足高水位，需要请求更多数据
		error = 0;
		ret = 0;
		if (!request_block->is_file_end) {
			ret = _audio_data_read_to_fifo(&request_block->file_info[request_block->file_done_cnt], request_block->org_input_data_fifo, &is_file_end);
		}
		// 有没有读取错误
		if (ret < 0) {
			LLOGC(luat_audio_debug_flag, "read file %d failed", request_block->file_done_cnt, ret);
			if (request_block->file_info[request_block->file_done_cnt].fail_continue) {
				is_file_end = 1;
			} else {
				request_block->is_error_stop = 1;
				is_file_end = 0;
			}
		}
		if (is_file_end) { //读到文件结尾了，看看是否还有文件文件读	
			if (!request_block->is_file_end) {
				request_block->file_done_cnt++;
				LLOGC(luat_audio_debug_flag, "decode file to fifo done,request id %u, file_done_cnt %d, total %d", request_block->request_id, request_block->file_done_cnt, request_block->file_info_cnt);
			}
			if (request_block->file_done_cnt >= request_block->file_info_cnt) {	//全部文件读取完成
				request_block->is_file_end = 1;
				request_block->file_done_cnt = request_block->file_info_cnt;
			} else { // 还有文件未读取，开始读取下一个文件
				_audio_decode_current_request_play_info(request_block);
			}
		}
		if (request_block->is_error_stop || request_block->is_user_stop || error) {
			stop = 1;
		}
		if (!stop) {
			luat_audio_data_codec_decode_once(&request_block->codec, 
				request_block->org_input_data_fifo, 
				&request_block->out_buffer, 
				request_block->is_file_end || is_file_end);
			if (request_block->out_buffer.pos) {
				uint32_t written_bytes;
				int ret = luat_audio_channel_write_data(request_block->data_channel, request_block->out_buffer.data, request_block->out_buffer.pos, &written_bytes, request_block->codec.common_param.is_signed, request_block->codec.common_param.data_align, request_block->codec.common_param.channel_nums);	
				if (ret) {
					request_block->is_error_stop = 1;
					LLOGE("write data failed ret %d", ret);
					stop = 1;
				}
				request_block->out_buffer.pos -= written_bytes;
			}
			uint32_t rest_bytes = luat_fifo_check_used_space(request_block->org_input_data_fifo);
			if (request_block->is_file_end || is_file_end) {
				if (!rest_bytes) { // 文件结束，且fifo数据为空，结束解码循环
					stop = 1;
				}
			} else {
				if (rest_bytes < request_block->codec.opts->decode_min_input_len) {
					stop = 1;
				}
			}
		}
	}
}

static void _audio_start_request(luat_audio_request_block_t *request_block)
{
	int ret;
	request_block->cb(LUAT_AUDIO_REQUEST_EVENT_START, NULL, 0, request_block);
	// 最后根据请求块的模式做不同的解码操作
	if (request_block->is_tts) {	//TTS模式发送给tts_task处理
		luat_rtos_event_send(_luat_audio.tts_task_handle, LUAT_AUDIO_EV_TTS_RUN, (uint32_t)request_block, 0, 0, 0);
		return;
	} else if (!request_block->is_stream) {	//本地文件模式
		_audio_decode_file_start(request_block);
		if (request_block->is_error_stop || request_block->is_user_stop) {
			return;
		}
		request_block->data_channel->driver_ctrl->opts->modify_audio_common_param(request_block->data_channel->driver_ctrl, request_block->codec.common_param.sample_rate, request_block->codec.common_param.data_align,request_block->codec.common_param.channel_nums);
		_audio_decode_file_to_fifo(request_block);
	} else {
		request_block->data_channel->driver_ctrl->opts->modify_audio_common_param(request_block->data_channel->driver_ctrl, request_block->codec.common_param.sample_rate, request_block->codec.common_param.data_align,request_block->codec.common_param.channel_nums);
		_audio_decode_stream_to_fifo(request_block);
	}
	ret = luat_audio_driver_start(request_block->data_channel->driver_ctrl, &request_block->codec.common_param, request_block->play_buff, 0, 4);
	if (ret) {
		LLOGE("request id %d start driver failed, ret %d", request_block->request_id, ret);
		request_block->is_error_stop = 1;
	}
}

static void luat_audio_common_task(void *param)
{
	luat_event_t out_event;
	luat_audio_request_block_t *request_block;
	uint8_t request_change;
	for(;;) {
		luat_rtos_event_recv(_luat_audio.common_task_handle, 0, &out_event, NULL, 0);
		LLOGC(luat_audio_debug_flag, "common task recv event %d", out_event.id);
		switch (out_event.id) {
		case LUAT_AUDIO_EV_TX_NEED_DATA:
			_luat_audio.decode_is_running = 1;
			luat_mutex_lock(_luat_audio.request_lock);
			if (!_luat_audio.current_request_block) {
				luat_mutex_unlock(_luat_audio.request_lock);
				luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
				_luat_audio.decode_is_running = 0;
				break;
			}
			request_block = _luat_audio.current_request_block;
			luat_mutex_unlock(_luat_audio.request_lock);
			if (request_block->is_stream) {	//流媒体模式
				_audio_decode_stream_to_fifo(request_block);
				request_block->cb(LUAT_AUDIO_REQUEST_EVENT_NEED_NEW_DATA, NULL, 0, request_block);
			} else {
				if (request_block->is_tts) {
					luat_mutex_unlock(_luat_audio.tts_wait_sem);
				} else {
					//加入解码文件写入fifo
					if (request_block->is_wait_play_end) {
						request_block->play_blank_data_cnt++;
						if (request_block->play_blank_data_cnt >= 4) {	// 播放空白数据超过4次，认为播放结束
							LLOGC(luat_audio_debug_flag, "wait play end %d", request_block->play_blank_data_cnt);
							request_block->is_stream_end = 1;
							request_block->is_wait_play_end = 0;
						}
					} else if (request_block->is_file_end && !luat_fifo_check_used_space(request_block->org_input_data_fifo)) {
						LLOGC(luat_audio_debug_flag, "file end, fifo empty, stop decode");
						request_block->is_wait_play_end = 1;
						request_block->play_blank_data_cnt = 0;
					} else {
						_audio_decode_file_to_fifo(request_block);
					}
				}
			}
			if (_luat_audio.current_request_block->is_error_stop || _luat_audio.current_request_block->is_user_stop || _luat_audio.current_request_block->is_stream_end) {
				_audio_request_finish();
			}
			_luat_audio.decode_is_running = 0;
			break;
		case LUAT_AUDIO_EV_RX_ENOUGH_DATA:
			request_block = _luat_audio.current_request_block;
			if (request_block) {
				request_block->cb(LUAT_AUDIO_REQUEST_EVENT_GET_NEW_DATA, NULL, 0, request_block);
			}

			if (_luat_audio.current_request_block->is_error_stop || _luat_audio.current_request_block->is_user_stop || _luat_audio.current_request_block->is_stream_end) {
				_audio_request_finish();
			}
			break;
		case LUAT_AUDIO_EV_REQUEST:
			request_change = 0;
			luat_mutex_lock(_luat_audio.request_lock);
			if (!_luat_audio.current_request_block) {	// 没有请求块，找下一个请求块
				_audio_find_next_request_block();
				luat_mutex_unlock(_luat_audio.request_lock);
				if (!_luat_audio.current_request_block) {	// 找不到请求块，直接返回
					break;
				}
				request_change = 1;
			} else {	// 有请求块，检查一下队列里是否有更高优先级的请求块
				if (!luat_llist_empty(&_luat_audio.request_block_list)) { // 请求队列不空的情况下，检查一下是否有更高优先级的请求块
					request_block = (luat_audio_request_block_t *)_luat_audio.request_block_list.next;
					if (request_block->priority > _luat_audio.current_request_block->priority) {
						LLOGD("request_id: %d priority higher than now request_id: %d", request_block->request_id, _luat_audio.current_request_block->request_id);
						luat_llist_del(&request_block->node);
						if (!luat_llist_traversal(&_luat_audio.request_block_list, _audio_add_request, _luat_audio.current_request_block)) {
							luat_llist_add_tail(&_luat_audio.current_request_block->node, &_luat_audio.request_block_list)	;
						}
						_luat_audio.current_request_block = request_block;
						request_change = 1;
					}
				}
				luat_mutex_unlock(_luat_audio.request_lock);
			}
			if (request_change) {
				// 请求块有变化，需要重新播放
				luat_rtos_task_sleep(1);	// 让低优先级的task能返回结果
				_audio_start_request(_luat_audio.current_request_block);
				if (_luat_audio.current_request_block->is_error_stop || _luat_audio.current_request_block->is_user_stop || _luat_audio.current_request_block->is_stream_end) {	// 启动请求块失败，将当前工作请求块设置为NULL，并且重新触发一下请求事件
					_audio_request_finish();
				}
			}
			break;
		case LUAT_AUDIO_EV_REQUEST_CANCEL:
			request_block = (luat_audio_request_block_t *)out_event.param1;
			request_block->is_user_stop = 1;
			luat_mutex_lock(_luat_audio.request_lock);
			luat_llist_del(&request_block->node);
			luat_mutex_unlock(_luat_audio.request_lock);
			if (_luat_audio.current_request_block && (_luat_audio.current_request_block->request_id == request_block->request_id)) {
				_audio_request_finish();
			} else {
				luat_audio_request_deinit(request_block);
				request_block->cb(LUAT_AUDIO_REQUEST_EVENT_END, NULL, 0, request_block);
			}
			luat_mutex_unlock((void *)out_event.param2);
			break;
		}
	}
}

int luat_audio_driver_register(const luat_audio_driver_opts_t *opts, struct luat_audio_driver_probe probe, void *driver_data)
{
	volatile uint8_t i = _luat_audio.all_driver_nums;
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].opts == NULL) {
			_luat_audio.driver_ctrl[i].opts = opts;
			_luat_audio.driver_ctrl[i].driver_data = driver_data;
			_luat_audio.driver_ctrl[i].probe = probe;
			_luat_audio.driver_ctrl[i].data_channel = &_luat_audio.channel[i];
			if (opts->init(&_luat_audio.driver_ctrl[i])) {
				LLOGE("probe_id: %x driver init failed, can not register", probe.probe_id);
				memset(&_luat_audio.driver_ctrl[i], 0, sizeof(luat_audio_driver_ctrl_t));
				return -LUAT_ERROR_OPERATION_FAILED; // 驱动注册失败，初始化失败
			}
			_luat_audio.driver_ctrl[i].state = LUAT_AUDIO_DRIVER_STATE_INITED;
			_luat_audio.channel[i].driver_ctrl = &_luat_audio.driver_ctrl[i];
			_luat_audio.channel[i].play_lock_mutex = luat_mutex_create();
			_luat_audio.channel[i].soft_vol = 100;
			_luat_audio.channel[i].play_fifo = luat_fifo_create(LUAT_AUDIO_CHANNEL_FIFO_DEFAULT_SIZE_POWER);
    		_luat_audio.channel[i].play_fifo_low_level = 32 * 1024;
    		_luat_audio.channel[i].play_fifo_high_level = _luat_audio.channel[i].play_fifo->size - 16 * 1024;
			_luat_audio.all_driver_nums++;
			LLOGC(luat_audio_debug_flag, "probe_id: %x driver register success index: %d", probe.probe_id, i);
			return LUAT_ERROR_NONE;
		}
	}
	LLOGE("driver %x register failed, max driver count is %d", probe.probe_id, LUAT_AUDIO_DRIVER_MAX);
	return -LUAT_ERROR_ID_INVALID; // 驱动注册失败，超过最大支持数量
}

luat_audio_driver_ctrl_t *luat_audio_driver_probe(luat_audio_driver_probe_t *probe)
{
	int i;
	if (!probe) {
		if (_luat_audio.driver_ctrl[_luat_audio.default_driver_index].opts) {
			LLOGC(luat_audio_debug_flag, "use default driver index: %d probe_id: %x", _luat_audio.default_driver_index,
				_luat_audio.driver_ctrl[_luat_audio.default_driver_index].probe.probe_id);
			return &_luat_audio.driver_ctrl[_luat_audio.default_driver_index];
		}
		return NULL;
	}
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].opts != NULL && _luat_audio.driver_ctrl[i].probe.probe_id == probe->probe_id) {
			return &_luat_audio.driver_ctrl[i];
		}
	}
	return NULL;
}

int luat_audio_driver_set_default(luat_audio_driver_probe_t *probe)
{
	uint8_t i;
	if (!probe) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].opts != NULL && _luat_audio.driver_ctrl[i].probe.probe_id == probe->probe_id) {
			_luat_audio.default_driver_index = i;
			return LUAT_ERROR_NONE;
		}
	}
	return -LUAT_ERROR_PARAM_INVALID;
}

luat_audio_driver_ctrl_t *luat_audio_driver_get_ctrl_info(uint8_t *all_nums, uint8_t *default_index)
{
	*all_nums = _luat_audio.all_driver_nums;
	*default_index = _luat_audio.default_driver_index;
	return _luat_audio.driver_ctrl;
}

int luat_audio_request_init(luat_audio_request_block_t *request_block)
{
	if (!request_block) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	memset(request_block, 0, sizeof(luat_audio_request_block_t));
	luat_mutex_lock(_luat_audio.request_lock);
	request_block->request_id = ++_luat_audio.next_request_id;
	luat_mutex_unlock(_luat_audio.request_lock);
	LLOGC(luat_audio_debug_flag, "request_id: %d init", request_block->request_id);
	return LUAT_ERROR_NONE;
}

void luat_audio_request_deinit(luat_audio_request_block_t *request_block)
{
	if (!request_block) {
		return;
	}
	if (!request_block->is_stream && !request_block->is_tts) {
		LLOGC(luat_audio_debug_flag, "request_id: %d close all file", request_block->request_id);
		for (int i = 0; i < request_block->file_info_cnt; i++) {
			if (!request_block->file_info[i].rom_data_len && request_block->file_info[i].fd) {
				luat_fs_fclose(request_block->file_info[i].fd);
				request_block->file_info[i].fd = NULL;
			}
		}
	}
	luat_fifo_destroy(request_block->org_input_data_fifo);
	request_block->org_input_data_fifo = NULL;
	luat_fifo_destroy(request_block->record_data_fifo);
	request_block->record_data_fifo = NULL;
	luat_buffer_deinit(&request_block->out_buffer);
	if (request_block->codec.opts) {
		luat_audio_data_codec_deinit(&request_block->codec);
		luat_audio_data_codec_unbind(&request_block->codec);
	}
	luat_heap_free(request_block->temp_buff);
	request_block->temp_buff = NULL;
	LLOGC(luat_audio_debug_flag, "request_id: %d deinit", request_block->request_id);
}

int luat_audio_request_start(luat_audio_request_block_t *request_block, uint8_t is_sync)
{
	if (!request_block) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	LLOGC(luat_audio_debug_flag, "request_id: %d add in request_block_list", request_block->request_id);
	luat_mutex_lock(_luat_audio.request_lock);
	if (luat_llist_empty(&_luat_audio.request_block_list)) {
		luat_llist_add(&request_block->node, &_luat_audio.request_block_list);
	} else {
		if (!luat_llist_traversal(&_luat_audio.request_block_list, _audio_add_request, request_block)) {
			luat_llist_add_tail(&request_block->node, &_luat_audio.request_block_list);
		}
	}
	luat_mutex_unlock(_luat_audio.request_lock);
	void *done_sem = NULL;
	if (is_sync) {
		done_sem = luat_mutex_create();
		request_block->done_sem = done_sem;
		luat_mutex_lock(done_sem);
	} 
	luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
	if (is_sync) {
		luat_mutex_lock(done_sem);
		luat_mutex_release(done_sem);
		return request_block->is_error_stop ? -LUAT_ERROR_OPERATION_FAILED : LUAT_ERROR_NONE;
	} else {
		return LUAT_ERROR_NONE;
	}
}

void luat_audio_request_cancel(luat_audio_request_block_t *request_block)
{
	void *done_sem = luat_mutex_create();
	luat_mutex_lock(done_sem);

	luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST_CANCEL, (uint32_t)request_block, (uint32_t)done_sem, 0, 0);
	luat_mutex_lock(done_sem);
	LLOGC(luat_audio_debug_flag, "request_id: %d cancel", request_block->request_id);
	return;
}

int luat_audio_request_prepare(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, uint8_t driver_work_mode, 
    luat_audio_request_cb_t cb, void *user_data)
{
	if (!request_block) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	luat_audio_request_init(request_block);
	luat_audio_driver_ctrl_t *driver_ctrl = luat_audio_driver_probe(probe);
	if (!driver_ctrl) {
		return -LUAT_ERROR_NO_SUCH_ID;
	}
	request_block->data_channel = driver_ctrl->data_channel;
	request_block->driver_work_mode = driver_work_mode;
	request_block->cb = cb;
	request_block->user_data = user_data;
	return LUAT_ERROR_NONE;
}

int luat_audio_request_play_files(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, const luat_audio_data_codec_opts_t *codec_opts, luat_audio_play_file_info_t *files, uint32_t files_num, uint8_t priority, uint8_t is_sync,
    luat_audio_request_cb_t cb, void *user_data)
{
	if (!request_block) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	int ret = luat_audio_request_prepare(request_block, probe, LUAT_AUDIO_DRIVER_MODE_PLAY, cb, user_data);
	if (ret != LUAT_ERROR_NONE) {
		return ret;
	}
	if (codec_opts) {
		
		if (luat_audio_data_codec_bind(&request_block->codec, codec_opts, request_block)) {
			luat_audio_request_deinit(request_block);
			return -LUAT_ERROR_OPERATION_FAILED;
		}
		if (request_block->codec.opts->init(&request_block->codec, 0) != LUAT_ERROR_NONE) {
			luat_audio_request_deinit(request_block);
			return -LUAT_ERROR_OPERATION_FAILED;
		}
		request_block->codec.common_param.driver_work_mode = LUAT_AUDIO_DRIVER_MODE_PLAY;
	}
	request_block->temp_buff = luat_heap_calloc(files_num, sizeof(luat_audio_play_file_info_t));
	if (!request_block->temp_buff) {
		return -LUAT_ERROR_NO_MEMORY;
	}
	memcpy(request_block->temp_buff, files, files_num * sizeof(luat_audio_play_file_info_t));
	request_block->file_info = (luat_audio_play_file_info_t *)request_block->temp_buff;
	for (int i = 0; i < files_num; i++) {
		if (!request_block->file_info[i].rom_data_len) {	//真正的文件形式
			request_block->file_info[i].fd = luat_fs_fopen(files[i].path, "r");
			if (!request_block->file_info[i].fd) {
				LLOGE("request_id: %d open file %s failed", request_block->request_id, files[i].path);
				luat_audio_request_deinit(request_block);
				return -LUAT_ERROR_NO_SUCH_ID;
			}
		}
	}
	request_block->priority = priority;
	request_block->file_info_cnt = files_num;
	return luat_audio_request_start(request_block, is_sync);
}

int luat_audio_request_play_tts(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, const char *text, uint32_t text_len, uint8_t priority, uint8_t is_sync,
    luat_audio_request_cb_t cb, void *user_data)
{
	if (!request_block) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	int ret = luat_audio_request_prepare(request_block, probe, LUAT_AUDIO_DRIVER_MODE_PLAY, cb, user_data);
	if (ret != LUAT_ERROR_NONE) {
		return ret;
	}
	request_block->codec.param.tts_output_callback_t = _audio_tts_output_callback;
	if (luat_audio_data_codec_bind(&request_block->codec, luat_audio_data_codec_find(LUAT_AUDIO_DATA_CODEC_TYPE_TTS), request_block) != LUAT_ERROR_NONE) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	if (request_block->codec.opts->init(&request_block->codec, 0) != LUAT_ERROR_NONE) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	request_block->temp_buff = luat_heap_malloc(text_len);
	if (!request_block->temp_buff) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_NO_MEMORY;
	}
	memcpy(request_block->temp_buff, text, text_len);
	request_block->priority = priority;
	request_block->is_tts = 1;
	request_block->tts_data = (const char *)request_block->temp_buff;
	request_block->tts_data_size = text_len;
	return luat_audio_request_start(request_block, is_sync);
}

void luat_audio_base_init(void)
{
	luat_rtos_task_create(&_luat_audio.common_task_handle, LUAT_AUDIO_TASK_STACK, 90, "luat_audio", luat_audio_common_task, NULL, 64);
	luat_rtos_task_create(&_luat_audio.tts_task_handle, LUAT_AUDIO_TASK_STACK, 20, "luat_tts", luat_audio_tts_task, NULL, 0);
	_luat_audio.request_lock = luat_mutex_create();
	_luat_audio.tts_wait_sem = luat_mutex_create();
	luat_mutex_lock(_luat_audio.tts_wait_sem);
	LUAT_INIT_LLIST_HEAD(&_luat_audio.request_block_list);
#ifdef __LUATOS__
	l_audio_init();
#endif
}

void luat_audio_debug_switch(uint8_t on_off)
{
	luat_audio_debug_flag = on_off;
}

int luat_audio_get_play_info_from_file(luat_audio_data_codec_t *codec, luat_audio_play_file_info_t *play_file)
{
    if (!codec || !play_file) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    int read_len;
    luat_buffer_t input_buffer;
    uint8_t temp[12];
    uint32_t jump_offset_bytes = 0;
    uint32_t need_bytes = 0;
	volatile uint32_t now_file_pos = 0;
	_audio_data_seek(play_file, now_file_pos, SEEK_SET);
    input_buffer.data = temp;
    input_buffer.pos = 0;
    input_buffer.max_len = sizeof(temp);
    codec->common_param.sample_rate = 0;
    read_len = _audio_data_read_to_buffer(play_file, input_buffer.data, input_buffer.max_len);
    if (read_len != sizeof(temp)) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    input_buffer.pos = read_len;
    int ret =codec->opts->get_play_info(codec, &input_buffer, now_file_pos,&jump_offset_bytes, &need_bytes, &codec->common_param);
    if (ret) {
        return ret;
    }
	now_file_pos = jump_offset_bytes;
    memset(&input_buffer, 0, sizeof(input_buffer));
    uint8_t retry_count = 0;
    while (!codec->common_param.sample_rate && retry_count < 5) {
        _audio_data_seek(play_file, jump_offset_bytes, SEEK_SET);
        luat_buffer_reinit(&input_buffer, need_bytes);
        read_len = _audio_data_read_to_buffer(play_file, input_buffer.data, input_buffer.max_len);
        if (read_len != need_bytes) {
			ret = -LUAT_ERROR_OPERATION_FAILED;
			retry_count = 5;
        }
        input_buffer.pos = read_len;
        jump_offset_bytes = 0;
        need_bytes = 0;
        ret =codec->opts->get_play_info(codec, &input_buffer, now_file_pos,&jump_offset_bytes, &need_bytes, &codec->common_param);
        if (ret) {
            retry_count = 5;
        }
		now_file_pos = jump_offset_bytes;
        retry_count++;
    }
	luat_buffer_deinit(&input_buffer);
	if (ret) {
		return ret;
	}
    if (!codec->common_param.sample_rate) {
        LLOGE("get common param failed, retry %d times", retry_count);
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    _audio_data_seek(play_file, jump_offset_bytes, SEEK_SET);
	LLOGC(luat_audio_debug_flag, "detect ok %u-%d-%d-%d, data start pos %d", codec->common_param.sample_rate, codec->common_param.data_align,codec->common_param.channel_nums, 
		codec->common_param.is_signed, jump_offset_bytes);
    return LUAT_ERROR_NONE;
}