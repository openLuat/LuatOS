#define SDL_MAIN_HANDLED

#include "luat_base.h"
#include "luat_audio.h"
#include "luat_audio_core.h"
#include "luat_audio_driver.h"
#include "luat_log.h"

#define LUAT_LOG_TAG "audio_compat"
#include "luat_log.h"

static luat_audio_driver_ctrl_t *g_compat_ctrl = NULL;

int luat_audio_record_and_play(uint8_t multimedia_id, uint32_t sample_rate, const uint8_t *play_buffer, uint32_t one_trunk_len, uint32_t total_trunk_cnt)
{
    (void)multimedia_id;

    if (g_compat_ctrl) {
        LLOGW("record_and_play already active");
        return -1;
    }

    luat_audio_driver_ctrl_t *ctrl = luat_audio_driver_probe(NULL);
    if (!ctrl) {
        LLOGE("no audio driver found");
        return -1;
    }

    /* Activate if needed */
    if (LUAT_AUDIO_DRIVER_STATE_INITED == ctrl->state) {
        int ret = ctrl->opts->activate(ctrl);
        if (ret) {
            LLOGE("activate failed: %d", ret);
            return -1;
        }
        ctrl->state = LUAT_AUDIO_DRIVER_STATE_ACTIVE;
    }

    /* Configure common audio params */
    int ret = ctrl->opts->modify_audio_common_param(ctrl, sample_rate, 2, 1, 0);
    if (ret) {
        LLOGE("modify tx param failed: %d", ret);
        return -1;
    }
    ret = ctrl->opts->modify_audio_common_param(ctrl, sample_rate, 2, 1, 1);
    if (ret) {
        LLOGE("modify rx param failed: %d", ret);
        return -1;
    }

    /* Use SPEECH_WITH_BUFFER so the driver uses our external play_buffer */
    ctrl->request_work_mode = LUAT_AUDIO_DRIVER_MODE_SPEECH_WITH_BUFFER;

    ret = luat_audio_driver_start(ctrl, &ctrl->tx_param, &ctrl->rx_param,
                                   (uint32_t *)play_buffer, one_trunk_len, (uint8_t)total_trunk_cnt);
    if (ret) {
        LLOGE("driver start failed: %d", ret);
        return -1;
    }

    LLOGI("record_and_play started: %uHz block=%u x %u support_full_loop=%d",
          sample_rate, one_trunk_len, total_trunk_cnt, ctrl->opts->support_full_loop);
    g_compat_ctrl = ctrl;
    return 0;
}

int luat_audio_record_stop(uint8_t multimedia_id)
{
    (void)multimedia_id;
    if (g_compat_ctrl) {
        g_compat_ctrl->opts->stop(g_compat_ctrl);
        g_compat_ctrl = NULL;
    }
    return 0;
}

int luat_audio_speech(uint8_t multimedia_id, uint8_t is_downlink, uint8_t type, const uint8_t *downlink_buffer, uint32_t buffer_len, uint8_t channel_num)
{
    (void)multimedia_id;
    (void)is_downlink;
    (void)type;
    (void)downlink_buffer;
    (void)buffer_len;
    (void)channel_num;
    return 0;
}
