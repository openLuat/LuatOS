#include "luat_audio_driver.h"
#include "luat_common_api.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_rtos_legacy.h"
#define LUAT_LOG_TAG "audio_drv"
#include "luat_log.h"
#include "luat_gpio.h"

#ifdef LUAT_CSDK_CONFIG_FILE
#include LUAT_CSDK_CONFIG_FILE
#endif

#ifndef LUAT_RT_RET_TYPE
#define LUAT_RT_RET_TYPE void
#endif

#ifndef LUAT_RT_CB_PARAM
#define LUAT_RT_CB_PARAM void *param
#endif

static __LUAT_C_CODE_IN_ISR__ LUAT_RT_RET_TYPE _audio_pa_power_on_delay_timer(LUAT_RT_CB_PARAM)
{
	struct luat_audio_driver_ctrl *ctrl = (struct luat_audio_driver_ctrl *)param;
	luat_gpio_set(ctrl->pa_power_pin, ctrl->pa_power_on_level);
    ctrl->pa_power_state = 1;
    LLOGC(luat_audio_debug_flag, "audio driver pa power on delay timer expire");
    if (ctrl->pa_power_state && ctrl->codec_power_state && ctrl->codec_ready_state) {
        LLOGC(luat_audio_debug_flag, "audio driver enable audio output");
        ctrl->audio_output_enable = 1;
    }
}

static __LUAT_C_CODE_IN_ISR__ LUAT_RT_RET_TYPE _audio_codec_ready_after_wakeup_timer(LUAT_RT_CB_PARAM)
{
	struct luat_audio_driver_ctrl *ctrl = (struct luat_audio_driver_ctrl *)param;
    LLOGC(luat_audio_debug_flag, "audio driver codec ready after wakeup timer expire");
    ctrl->codec_ready_state = 1;
    if (ctrl->pa_power_state && ctrl->codec_power_state && ctrl->codec_ready_state) {
        LLOGC(luat_audio_debug_flag, "audio driver enable audio output");
        ctrl->audio_output_enable = 1;
    }
}

int luat_audio_driver_config_pa_power_ctrl(struct luat_audio_driver_ctrl *ctrl, uint8_t pa_power_ctrl_enable, uint8_t pa_power_pin,
    uint8_t pa_power_on_level, uint16_t pa_power_on_delay_time_ms)
{
    if (!ctrl) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    ctrl->pa_power_ctrl_enable = pa_power_ctrl_enable;
    ctrl->pa_power_pin = pa_power_pin;
    ctrl->pa_power_on_level = pa_power_on_level;
    if (pa_power_on_delay_time_ms) {
        if (!ctrl->pa_power_on_delay_timer) {
            ctrl->pa_power_on_delay_timer = luat_create_rtos_timer(_audio_pa_power_on_delay_timer, ctrl, NULL);
        }
    }
    ctrl->pa_power_on_delay_time_ms = pa_power_on_delay_time_ms;
    if (pa_power_ctrl_enable) {
        luat_gpio_cfg_t cfg = {0};
        cfg.pin = pa_power_pin;
        cfg.mode = LUAT_GPIO_OUTPUT;
        cfg.pull = LUAT_GPIO_DEFAULT;
        cfg.output_level = !pa_power_on_level; 
        luat_gpio_open(&cfg);
        luat_gpio_set(pa_power_pin, !pa_power_on_level);
    }
    return 0;
}

int luat_audio_driver_config_codec_power_ctrl(struct luat_audio_driver_ctrl *ctrl, uint8_t codec_power_ctrl_enable, uint8_t codec_power_pin,
    uint8_t codec_power_on_level, uint32_t codec_ready_after_wakeup_time_ms, uint16_t codec_power_off_delay_time_ms)
{
    if (!ctrl) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    ctrl->codec_ready_after_wakeup_time_ms = codec_ready_after_wakeup_time_ms;
    if (ctrl->codec_ready_after_wakeup_time_ms) {
        if (!ctrl->codec_ready_after_wakeup_timer) {
            ctrl->codec_ready_after_wakeup_timer = luat_create_rtos_timer(_audio_codec_ready_after_wakeup_timer, ctrl, NULL);
        }
    }
    ctrl->codec_power_ctrl_enable = codec_power_ctrl_enable;
    ctrl->codec_power_pin = codec_power_pin;
    ctrl->codec_power_on_level = codec_power_on_level;
    ctrl->codec_power_off_delay_time_ms = codec_power_off_delay_time_ms;
    if (codec_power_ctrl_enable) {
        luat_gpio_cfg_t cfg = {0};
        cfg.pin = codec_power_pin;
        cfg.mode = LUAT_GPIO_OUTPUT;
        cfg.pull = LUAT_GPIO_DEFAULT;
        cfg.output_level = !codec_power_on_level; 
        luat_gpio_open(&cfg);
        luat_gpio_set(codec_power_pin, !codec_power_on_level);
    }
    return 0;
}

int luat_audio_driver_config_private_param(struct luat_audio_driver_ctrl *ctrl, uint32_t param, uint32_t value1, uint32_t value2)
{
    if (!ctrl) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (LUAT_AUDIO_DRIVER_STATE_IDLE == ctrl->state) {
        return -LUAT_ERROR_NO_SUCH_ID;
    }
    if (LUAT_AUDIO_DRIVER_STATE_RUNNING > ctrl->state) {
        return ctrl->opts->config_private_param(ctrl, param,value1, value2);
    }
    return -LUAT_ERROR_DEVICE_BUSY;
}

int luat_audio_driver_config_audio_common_param(struct luat_audio_driver_ctrl *ctrl, uint32_t sample_rate, uint8_t data_bits, uint8_t channel_nums)
{
    if (!ctrl) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (LUAT_AUDIO_DRIVER_STATE_IDLE == ctrl->state) {
        return -LUAT_ERROR_NO_SUCH_ID;
    }
    if (LUAT_AUDIO_DRIVER_STATE_RUNNING > ctrl->state) {
        return ctrl->opts->modify_audio_common_param(ctrl, sample_rate, data_bits, channel_nums);
    }
    return -LUAT_ERROR_DEVICE_BUSY;
}

int luat_audio_driver_change_sample_rate(struct luat_audio_driver_ctrl *ctrl, uint32_t sample_rate)
{
    if (!ctrl) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (LUAT_AUDIO_DRIVER_STATE_IDLE == ctrl->state) {
        return -LUAT_ERROR_NO_SUCH_ID;
    }
    return ctrl->opts->change_sample_rate(ctrl, sample_rate);
}

int luat_audio_driver_start(struct luat_audio_driver_ctrl *ctrl, uint8_t mode, uint32_t *play_buff, uint32_t one_block_len, uint8_t block_nums)
{
    if (!ctrl) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    LLOGC(luat_audio_debug_flag, "audio driver start mode %d driver state %d", mode, ctrl->state);
    if (LUAT_AUDIO_DRIVER_STATE_IDLE == ctrl->state) {
        return -LUAT_ERROR_NO_SUCH_ID;
    }
    int ret;
    if (LUAT_AUDIO_DRIVER_STATE_INITED == ctrl->state) {
        ret = ctrl->opts->activate(ctrl);
        if (ret) {
            return -LUAT_ERROR_OPERATION_FAILED;
        }
        ctrl->state = LUAT_AUDIO_DRIVER_STATE_ACTIVE;
    }
    if (LUAT_AUDIO_DRIVER_STATE_ACTIVE == ctrl->state) {
        switch (mode) {
            case LUAT_AUDIO_DRIVER_MODE_PLAY:
                if (ctrl->opts->support_full_loop) {
                    ret = ctrl->opts->start_full_loop(ctrl, &ctrl->play_buff, one_block_len, block_nums, &ctrl->record_buff, one_block_len, block_nums);
                } else if (ctrl->opts->support_tx_loop){
                    ret = ctrl->opts->start_tx_loop(ctrl, &ctrl->play_buff, one_block_len, block_nums);
                } else {
                    ret = -LUAT_ERROR_CMD_NOT_SUPPORT;
                }
                break;
            case LUAT_AUDIO_DRIVER_MODE_RECORD:
                if (ctrl->opts->support_full_loop) {
                    ret = ctrl->opts->start_full_loop(ctrl, &ctrl->play_buff, one_block_len, block_nums, &ctrl->record_buff, one_block_len, block_nums);
                } else if (ctrl->opts->support_rx_loop){
                    ret = ctrl->opts->start_rx_loop(ctrl, &ctrl->record_buff, one_block_len, block_nums);
                } else {
                    ret = -LUAT_ERROR_CMD_NOT_SUPPORT;
                }
                break;
            case LUAT_AUDIO_DRIVER_MODE_CALL:
                if (ctrl->opts->support_full_loop) {
                    ret = ctrl->opts->start_full_loop(ctrl, &ctrl->play_buff, one_block_len, block_nums, &ctrl->record_buff, one_block_len, block_nums);
                } else {
                    ret = -LUAT_ERROR_CMD_NOT_SUPPORT;
                }
                break;
            case LUAT_AUDIO_DRIVER_MODE_CALL_WITH_BUFFER:
                if (ctrl->opts->support_full_loop) {
                    ret = ctrl->opts->start_full_loop_with_play_buff(ctrl, play_buff, one_block_len, block_nums, &ctrl->record_buff, one_block_len, block_nums);
                } else {
                    ret = -LUAT_ERROR_CMD_NOT_SUPPORT;
                }
                break;
        }

        if (ret) {
            ctrl->opts->deactivate(ctrl);
            ctrl->state = LUAT_AUDIO_DRIVER_STATE_INITED;
            return -LUAT_ERROR_OPERATION_FAILED;
        }
        ctrl->state = LUAT_AUDIO_DRIVER_STATE_RUNNING;
    }
    LLOGC(luat_audio_debug_flag, "audio driver check codec power %d , param %d %d %d", ctrl->codec_power_state,
        ctrl->codec_power_ctrl_enable, ctrl->codec_power_pin, ctrl->codec_power_on_level);
    if (!ctrl->codec_power_state) {
        if (ctrl->codec_power_ctrl_enable) {
            luat_gpio_set(ctrl->codec_power_pin, ctrl->codec_power_on_level);
            ctrl->codec_power_state = 1;
            ctrl->codec_ready_state = 0;
        } else {
            ctrl->codec_ready_state = 1;
            ctrl->codec_power_state = 1;
        }
    }
    LLOGC(luat_audio_debug_flag, "audio driver check codec ready %d , param %u", ctrl->codec_ready_state,
        ctrl->codec_ready_after_wakeup_time_ms);
    if (!ctrl->codec_ready_state) {
        if (ctrl->codec_ready_after_wakeup_time_ms) {
            luat_start_rtos_timer(ctrl->codec_ready_after_wakeup_timer, ctrl->codec_ready_after_wakeup_time_ms, 0);
        } else {
            ctrl->codec_ready_state = 1;
        }
    }
    LLOGC(luat_audio_debug_flag, "audio driver check pa power %d, param %d %d %d %u", ctrl->pa_power_state,
    ctrl->pa_power_ctrl_enable, ctrl->pa_power_pin, ctrl->pa_power_on_level, ctrl->pa_power_on_delay_time_ms);
    if (!ctrl->pa_power_state) {
        if (ctrl->pa_power_ctrl_enable) {
            if (ctrl->pa_power_on_delay_time_ms) {
                luat_start_rtos_timer(ctrl->pa_power_on_delay_timer, ctrl->pa_power_on_delay_time_ms, 0);
            } else {
                luat_gpio_set(ctrl->pa_power_pin, ctrl->pa_power_on_level);
                ctrl->pa_power_state = 1;
            }
        } else {
            ctrl->pa_power_state = 1;
        }
    }
    if (ctrl->pa_power_state && ctrl->codec_power_state && ctrl->codec_ready_state) {
        LLOGC(luat_audio_debug_flag, "audio driver enable audio output");
        ctrl->audio_output_enable = 1;
    }

    return LUAT_ERROR_NONE;
}

void luat_audio_driver_pa_power_off(struct luat_audio_driver_ctrl *ctrl)
{
    if (!ctrl) {
        return;
    }
    if (ctrl->pa_power_ctrl_enable) {
        luat_gpio_set(ctrl->pa_power_pin, !ctrl->pa_power_on_level);
        ctrl->pa_power_state = 0;
    } else {
        ctrl->pa_power_state = 0;
    }
    ctrl->audio_output_enable = 0;
}

void luat_audio_driver_codec_power_off(struct luat_audio_driver_ctrl *ctrl)
{
    if (!ctrl) {
        return;
    }
    if (ctrl->codec_power_ctrl_enable) {
        if (ctrl->codec_power_off_delay_time_ms) {
            luat_rtos_task_sleep(ctrl->codec_power_off_delay_time_ms);
        }
        luat_gpio_set(ctrl->codec_power_pin, !ctrl->codec_power_on_level);
        ctrl->codec_power_state = 0;
        ctrl->codec_ready_state = 0;
    } else {
        ctrl->codec_power_state = 0;
        ctrl->codec_ready_state = 0;
    }
    ctrl->audio_output_enable = 0;
}

void luat_audio_driver_stop(struct luat_audio_driver_ctrl *ctrl)
{
    if (!ctrl) {
        return;
    }
    if (LUAT_AUDIO_DRIVER_STATE_RUNNING == ctrl->state) {
        ctrl->opts->stop(ctrl);
        ctrl->state = LUAT_AUDIO_DRIVER_STATE_ACTIVE;
    }
}

void luat_audio_driver_deactivate(struct luat_audio_driver_ctrl *ctrl)
{
    if (!ctrl) {
        return;
    }
    if (LUAT_AUDIO_DRIVER_STATE_RUNNING == ctrl->state) {
        ctrl->opts->stop(ctrl);
        ctrl->state = LUAT_AUDIO_DRIVER_STATE_ACTIVE;
    }
    if (LUAT_AUDIO_DRIVER_STATE_ACTIVE == ctrl->state) {
        ctrl->opts->deactivate(ctrl);
        ctrl->state = LUAT_AUDIO_DRIVER_STATE_INITED;
    }
}

int luat_audio_driver_fill_default(struct luat_audio_driver_ctrl *ctrl, uint8_t *play_buff, uint32_t len_bytes, uint8_t is_signed, uint8_t align)
{
    luat_data_union_t data;
    uint32_t data_address = (uint32_t)play_buff;
    uint32_t data_len;
    data.p8 = (uint8_t *)data_address;
    if (is_signed) {
        memset(play_buff, 0, len_bytes);
    } else {
        switch (align) {
            case 2:
                data_address &= ~0x1;
                data.p16 = (uint16_t *)data_address;
                data_len = len_bytes >> 1;
                for(uint32_t i = 0; i < data_len; i++)
                {
                    data.p16[i] = 0x8000;
                }
                break;
            case 3:
            case 4:
                data_address &= ~0x3;
                data.p32 = (uint32_t *)data_address;
                data_len = len_bytes >> 2;
                uint32_t fill_data = align == 4 ? 0x80000000 : 0x00800000;
                for(uint32_t i = 0; i < data_len; i++)
                {
                    data.p32[i] = fill_data;
                }
                break;
            default:
                memset(play_buff, 0x80, len_bytes);
                break;
        }
    }
    return 0;
}