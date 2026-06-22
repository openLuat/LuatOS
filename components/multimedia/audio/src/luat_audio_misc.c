#include "luat_base.h"
#include "luat_audio_core.h"
#include "luat_common_api.h"
#include "luat_fs.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include <string.h>
#include <sys/_types.h>
#define LUAT_LOG_TAG "audio_misc"
#include "luat_log.h"

static void _audio_decode_extern_source_play_info(luat_audio_extern_source_t *source)
{
    uint8_t error = 0;
    int ret;
    source->codec.common_param.sample_rate = 0;
    while (!source->codec.common_param.sample_rate && !source->is_error_stop && source->file_done_cnt < source->file_info_cnt) {
        if (source->codec.opts) {
            //已经指定了解码器则自动处理
            if (luat_audio_get_play_info_from_file(&source->codec, &source->file_info[source->file_done_cnt])) {
                LLOGE("no play info found for file %d", source->file_done_cnt);
                error = 1;
            } else {
                LLOGC(luat_audio_debug_flag, "find play info %u,%u,%u", source->codec.common_param.sample_rate, source->codec.common_param.data_align, source->codec.common_param.channel_nums);
            }
        } else {
            luat_audio_data_codec_t codec = {0};
            codec.common_param.driver_work_mode = LUAT_AUDIO_DRIVER_MODE_PLAY;
            uint8_t codec_type = 255;
            //没有指定解码器则需要搜索所有的解码器，解码尝试分析播放参数，找到合适的解码器
            for (int i = 0; i < LUAT_AUDIO_DATA_CODEC_TYPE_MAX; i++) {
                codec.opts = (luat_audio_data_codec_opts_t *)luat_audio_data_codec_find(i);
                if (!codec.opts || !codec.opts->support_detect) {
                    continue;
                }
                if (LUAT_ERROR_NONE == luat_audio_get_play_info_from_file(&codec, &source->file_info[source->file_done_cnt])) {
                    LLOGC(luat_audio_debug_flag, "auto search find codec %d", i);
                    codec_type = i;
                    break;
                }
            }
            if (255 == codec_type) {
                LLOGE("no play info found for file %d", source->file_done_cnt);
                error = 1;
            }
            if (!error) {
                // 绑定解码器
                ret = luat_audio_data_codec_bind(&source->codec, luat_audio_data_codec_find(codec_type), source->request);
                if (ret) {
                    LLOGE("bind codec %d failed, ret %d", codec_type, ret);
                    error = 1;
                } else {
                    if (source->codec.opts->init(&source->codec, 0)) {
                        LLOGE("init codec %d failed", codec_type);
                        luat_audio_data_codec_deinit(&source->codec);
                        luat_audio_data_codec_unbind(&source->codec);
                        error = 1;
                    } else {
                        source->codec.common_param = codec.common_param;
                        LLOGC(luat_audio_debug_flag, "find codec %d, play info %u,%u,%u", codec_type, source->codec.common_param.sample_rate, source->codec.common_param.data_align, source->codec.common_param.channel_nums);
                    }
                }
            }
        }
        if (error) {
            if (source->file_info[source->file_done_cnt].fail_continue) {
                LLOGC(luat_audio_debug_flag, "continue decode file %d", source->file_done_cnt);
                source->file_done_cnt++;
                continue;
            } else {
                source->is_error_stop = 1;
            }
        } else {
            return;
        }
    }
    if (!source->codec.common_param.sample_rate) {
        LLOGE("no play info found ");
        source->is_error_stop = 1;
    }
}

int luat_audio_extern_source_check(luat_audio_extern_source_t *source)
{
    luat_audio_data_codec_t *check_codec = source->is_add_record? &source->request->record_codec : &source->request->play_codec;
    if (source->codec.common_param.sample_rate != check_codec->common_param.sample_rate) {
        LLOGE("sample_rate not match, source %d, request %d", source->codec.common_param.sample_rate, check_codec->common_param.sample_rate);
        return -LUAT_ERROR_PERMISSION_DENIED;
    }
    if (source->codec.common_param.data_align != check_codec->common_param.data_align) {
        LLOGE("data_align not match, source %d, request %d", source->codec.common_param.data_align, check_codec->common_param.data_align);
        return -LUAT_ERROR_PERMISSION_DENIED;
    }
    if (source->codec.common_param.channel_nums != check_codec->common_param.channel_nums) {
        LLOGE("channel_nums not match, source %d, request %d", source->codec.common_param.channel_nums, check_codec->common_param.channel_nums);
        return -LUAT_ERROR_PERMISSION_DENIED;
    }
    return LUAT_ERROR_NONE;
}

int luat_audio_extern_source_decode(luat_audio_extern_source_t *source)
{
    if (source->is_done || source->is_decode_finish || source->is_error_stop || source->is_tts) {
        return LUAT_ERROR_NONE;
    }
    uint8_t is_file_end = 0;
    int ret = LUAT_ERROR_NONE;
    for(;;) {
        if (!source->is_stream) {   //从文件里读取数据
            ret = LUAT_ERROR_NONE;
            if (!source->is_input_end) {
                ret = luat_audio_data_read_to_fifo(&source->file_info[source->file_done_cnt], source->decode_input_fifo, &is_file_end);
            }
            if (ret < 0) {
                LLOGC(luat_audio_debug_flag, "read file %d failed", source->file_done_cnt, ret);
                if (source->file_info[source->file_done_cnt].fail_continue) {
                    is_file_end = 1;
                } else {
                    goto ERROR;
                }
            }
            if (is_file_end) { //读到文件结尾了，看看是否还有文件文件读	
                if (!source->is_input_end) {
                    source->file_done_cnt++;
                    LLOGC(luat_audio_debug_flag, "decode file to fifo done,file_done_cnt %d, total %d", source->file_done_cnt, source->file_info_cnt);
                }
                if (source->file_done_cnt >= source->file_info_cnt) {	//全部文件读取完成
                    source->is_input_end = 1;
                    source->file_done_cnt = source->file_info_cnt;
                } else { // 还有文件未读取，开始读取下一个文件
                    _audio_decode_extern_source_play_info(source);
                }
            }
        }
        uint32_t before_pos = source->decode_output_buffer.pos;
        // LLOGC(luat_audio_debug_flag, "decode once before, output pos %u, is_input_end %d, is_file_end %d, input_fifo %u", before_pos, source->is_input_end, is_file_end, luat_fifo_check_used_space(source->decode_input_fifo));
        ret =luat_audio_data_codec_decode_once(&source->codec, 
            source->decode_input_fifo, 
            &source->decode_output_buffer, 
            source->is_input_end || is_file_end);
        if (ret) {
            LLOGE("decode once failed, ret %d", ret);
            goto ERROR;
        }
        // LLOGC(luat_audio_debug_flag, "decode once after, output pos %u, is_input_end %d, is_file_end %d, input_fifo %u", before_pos, source->is_input_end, is_file_end, luat_fifo_check_used_space(source->decode_input_fifo));

        if (source->is_input_end && !luat_fifo_check_used_space(source->decode_input_fifo) && !source->decode_output_buffer.pos) {
            source->is_decode_finish = 1;
            LLOGC(luat_audio_debug_flag, "decode done");
            return LUAT_ERROR_NONE;
        }
        if (before_pos == source->decode_output_buffer.pos) {
            return LUAT_ERROR_NONE;
        }
        if (source->decode_output_buffer.pos >= source->decode_low_level) {
            return LUAT_ERROR_NONE;
        }
    }
    return LUAT_ERROR_NONE;
ERROR:
    LLOGE("extern source decode error, ret %d", ret);
    source->is_error_stop = 1;
    source->is_decode_finish = 1;
    return ret;
}

int luat_audio_extern_source_init(luat_audio_extern_source_t *source, void *file_info_or_tts_data, uint32_t files_num_or_tts_data_len, void *user_data)
{
    int ret = LUAT_ERROR_NONE;
    if (!source->is_tts && !source->is_stream) { // 初始化文件源
        source->temp_buff = luat_heap_calloc(files_num_or_tts_data_len, sizeof(luat_audio_play_file_info_t));
        if (!source->temp_buff) {
            ret = -LUAT_ERROR_NO_MEMORY;
            goto ERROR;
        }
        source->file_info_cnt = files_num_or_tts_data_len;
        memcpy(source->temp_buff, file_info_or_tts_data, files_num_or_tts_data_len * sizeof(luat_audio_play_file_info_t));
        source->file_info = (luat_audio_play_file_info_t *)source->temp_buff;
        for (int i = 0; i < files_num_or_tts_data_len; i++) {
            if (!source->file_info[i].rom_data_len) {	//真正的文件形式
                source->file_info[i].fd = luat_fs_fopen(source->file_info[i].path, "r");
                if (!source->file_info[i].fd) {
                    LLOGE("open file %s failed", source->file_info[i].path);
                    ret = -LUAT_ERROR_NO_SUCH_ID;
                    goto ERROR;
                }
            }
        }
        _audio_decode_extern_source_play_info(source);
        if (source->is_error_stop) {
            ret = -LUAT_ERROR_NO_SUCH_ID;
            goto ERROR;
        }
    }
    if (source->is_tts) {

        if (!luat_audio_data_codec_find(LUAT_AUDIO_DATA_CODEC_TYPE_TTS)) {
            LLOGE("tts codec not found");
            ret = -LUAT_ERROR_PERMISSION_DENIED;
            goto ERROR;
        }

        if (luat_audio_data_codec_bind(&source->codec, luat_audio_data_codec_find(LUAT_AUDIO_DATA_CODEC_TYPE_TTS), source) != LUAT_ERROR_NONE) {
            ret = -LUAT_ERROR_PERMISSION_DENIED;
            goto ERROR;
        }
        if (source->codec.opts->init(&source->codec, 0) != LUAT_ERROR_NONE) {
            ret = -LUAT_ERROR_PERMISSION_DENIED;
            goto ERROR;
        }

        source->temp_buff = luat_heap_malloc(files_num_or_tts_data_len);
        if (!source->temp_buff) {
            ret = -LUAT_ERROR_NO_MEMORY;
            goto ERROR;
        }
        memcpy(source->temp_buff, file_info_or_tts_data, files_num_or_tts_data_len);
        source->tts_data = (const char *)source->temp_buff;
        source->tts_data_size = files_num_or_tts_data_len;
    } else {

    }
    if (!source->is_tts) {
        source->decode_input_fifo = luat_fifo_create(LUAT_AUDIO_DATA_CODEC_INPUT_FIFO_DEFAULT_SIZE_POWER);
    }
    if (source->is_add_record) { //附加在录音通道，输出缓存长度需要看单次录音数量和解码输出长度
        source->decode_low_level = source->request->record_fifo_enough_data_level;
        uint32_t size = source->request->record_fifo_enough_data_level > source->codec.opts->decode_max_output_len?
        source->request->record_fifo_enough_data_level : source->codec.opts->decode_max_output_len;
        luat_buffer_init(&source->decode_output_buffer, size * 2);
    } else {
        source->decode_low_level = source->codec.opts->decode_max_output_len;
        luat_buffer_init(&source->decode_output_buffer, source->codec.opts->decode_max_output_len * 2);
    }
    if (!source->decode_output_buffer.data || !source->decode_input_fifo) {
        ret = -LUAT_ERROR_NO_MEMORY;
        goto ERROR;
    }
    source->user_data = user_data;
    return ret;
ERROR:
    luat_audio_extern_source_deinit(source);
    return ret;
}

void luat_audio_extern_source_deinit(luat_audio_extern_source_t *source)
{
    if (source->is_done) {
        LLOGC(luat_audio_debug_flag, "extern source %p deinit already done", source);
        return;
    }
    source->is_done = 1;
    luat_buffer_deinit(&source->decode_output_buffer);
    luat_fifo_destroy(source->decode_input_fifo);
    // luat_fifo_destroy(source->decode_output_fifo);
    if (!source->is_tts && !source->is_stream) {
        for (int i = 0; i < source->file_info_cnt; i++) {
            if (!source->file_info[i].rom_data_len && source->file_info[i].fd) {
                luat_fs_fclose(source->file_info[i].fd);
                source->file_info[i].fd = NULL;
            }
        }
    }
    luat_heap_free(source->temp_buff);
    luat_audio_data_codec_unbind(&source->codec);
    LLOGC(luat_audio_debug_flag, "extern source %p deinit done", source);
}

int luat_audio_get_play_info_from_file(luat_audio_data_codec_t *codec, luat_audio_play_file_info_t *play_file)
{
    if (!codec || !play_file) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    int read_len;
    luat_buffer_t input_buffer;
    uint8_t temp[44];
    uint32_t jump_offset_bytes = 0;
    uint32_t need_bytes = 0;
	volatile uint32_t now_file_pos = 0;
	luat_audio_data_seek(play_file, now_file_pos, SEEK_SET);
    input_buffer.data = temp;
    input_buffer.pos = 0;
    input_buffer.max_len = sizeof(temp);
    codec->common_param.sample_rate = 0;
    read_len = luat_audio_data_read_to_buffer(play_file, input_buffer.data, input_buffer.max_len);
    if (read_len != sizeof(temp)) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    input_buffer.pos = read_len;
    int ret =codec->opts->get_play_info(codec, &input_buffer, now_file_pos,&jump_offset_bytes, &need_bytes, &codec->common_param);
    if (ret) {
		LLOGC(luat_audio_debug_flag, "codec type %d, get common param failed, ret: %d", codec->opts->type, ret);
        return ret;
    }
	now_file_pos = jump_offset_bytes;
    memset(&input_buffer, 0, sizeof(input_buffer));
    uint8_t retry_count = 0;
    while (!codec->common_param.sample_rate && retry_count < 5) {
        luat_audio_data_seek(play_file, jump_offset_bytes, SEEK_SET);
        luat_buffer_reinit(&input_buffer, need_bytes);
        read_len = luat_audio_data_read_to_buffer(play_file, input_buffer.data, input_buffer.max_len);
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
		LLOGC(luat_audio_debug_flag, "codec type %d, get common param failed, ret: %d, retry %d times, jump_offset_bytes: %d, need_bytes: %d", codec->opts->type, ret, retry_count, jump_offset_bytes, need_bytes);
		return ret;
	}
    if (!codec->common_param.sample_rate) {
        // LLOGC(luat_audio_debug_flag, "codec type %d, get common param failed, retry %d times", codec->opts->type, retry_count);
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    luat_audio_data_seek(play_file, jump_offset_bytes, SEEK_SET);
	LLOGC(luat_audio_debug_flag, "detect ok %u-%d-%d-%d, data start pos %d", codec->common_param.sample_rate, codec->common_param.data_align,codec->common_param.channel_nums, 
		codec->common_param.is_signed, jump_offset_bytes);
    return LUAT_ERROR_NONE;
}

/**
 * @brief 从文件读取数据到FIFO
 * @param decode_file 解码文件信息
 * @param input_data_fifo 输入数据FIFO
 * @param is_file_end 是否为结束请求
 * @return int 读取的字节数
 */
int luat_audio_data_read_to_fifo(luat_audio_play_file_info_t *decode_file, luat_fifo_t *input_data_fifo, uint8_t *is_file_end)
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

int luat_audio_data_read_to_buffer(luat_audio_play_file_info_t *decode_file, uint8_t *buffer, uint32_t need_len)
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


int luat_audio_data_seek(luat_audio_play_file_info_t *decode_file, int offset, int origin)
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
