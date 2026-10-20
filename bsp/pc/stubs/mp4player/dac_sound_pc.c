/**
 * @file dac_sound_pc.c
 * @brief PC simulator sound backend for the mp4player audio devices.
 *
 * On CCM42xx, dac_sound.c drives a real DAC + DMA peripheral (through the
 * Audio V2 stream-request API). A PC host has no such peripheral, so this file
 * keeps the exact dac_sound.h contract but forwards the PCM produced by the
 * upper layer (mp4_decode / mp3player / wave / flac) into the SDL2 audio
 * device via the LuatOS I2S port (bsp/pc/port/driver/luat_i2s_pc.c), which is
 * the same audio path already proven audible for the classic audio module.
 *
 * Data flow (sound_dev_port.c registers dac_sound_* as SOUND_DEV_PDM):
 *   upper layer: sound_dev_set_callback() + sound_dev_set_format()
 *                + sound_dev_start()
 *   pump task  : once per audio period
 *                1. wait until the SDL queue has room (luat_i2s_txbuff_info)
 *                2. ask the upper layer for the next period of PCM
 *                   (event SOUND_TX_PERIOD fills dac_tx_fifo)
 *                3. luat_i2s_send() that period to the SDL device
 *
 * The I2S device is (re)configured only when the requested format actually
 * changes: luat_i2s_setup() clears the SDL queue and reopens the device, so
 * calling it on every start would drop already queued audio.
 */

#include <string.h>

#include "dac_sound.h"
#include "luat_i2s.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "dac_sound_pc"
#include "luat_log.h"

#define DAC_PC_I2S_ID          0
#define DAC_PC_PUMP_STACK      (8 * 1024)
#define DAC_PC_PUMP_PRIO       60
#define DAC_PC_IDLE_SLEEP_MS   10

/* One period of PCM handed to the upper layer per SOUND_TX_PERIOD event. */
static unsigned char dac_tx_fifo[SOUND_TX_FIFO_PERIOD_SIZE];

typedef struct {
    unsigned char inited;
    unsigned char format_valid;
    unsigned char i2s_opened;
    unsigned int volume;
    unsigned int sample_rate;
    unsigned int channels;
    unsigned int bps;
    unsigned int applied_rate;
    unsigned int applied_channels;
    void (*event_callback)(emSOUND_EVENT event, void *data, void *user_data);
    void *user_data;
} dac_pc_ctrl_t;

static dac_pc_ctrl_t dac_ctrl;

/* Playback gate; written by start/stop (any thread), read by the pump task. */
static volatile int dac_playing = 0;
static luat_rtos_task_handle dac_pump_task = NULL;

static void dac_pump_task_body(void *param)
{
    (void)param;

    while (1) {
        if (!dac_playing || !dac_ctrl.i2s_opened || dac_ctrl.event_callback == NULL) {
            luat_rtos_task_sleep(DAC_PC_IDLE_SLEEP_MS);
            continue;
        }

        size_t buffsize = 0;
        size_t remain = 0;
        if (luat_i2s_txbuff_info(DAC_PC_I2S_ID, &buffsize, &remain) != 0) {
            /* Device gone (closed by another user of I2S id 0). */
            dac_ctrl.i2s_opened = 0;
            luat_rtos_task_sleep(DAC_PC_IDLE_SLEEP_MS);
            continue;
        }

        /* Keep roughly half a buffer of headroom so a late wakeup cannot underrun. */
        if (buffsize && remain > buffsize / 2) {
            luat_rtos_task_sleep(DAC_PC_IDLE_SLEEP_MS);
            continue;
        }

        /* The upper layer fills at most one period; silence the rest so a
         * partially filled period cannot replay stale PCM. */
        memset(dac_tx_fifo, 0, SOUND_TX_FIFO_PERIOD_SIZE);
        dac_ctrl.event_callback(SOUND_TX_PERIOD, dac_tx_fifo, dac_ctrl.user_data);

        if (!dac_playing) {
            /* The callback stopped playback (ring buffer ran dry). */
            continue;
        }

        luat_i2s_send(DAC_PC_I2S_ID, dac_tx_fifo, SOUND_TX_FIFO_PERIOD_SIZE);
    }
}

/* Configure the SDL device for the current format, reusing it when unchanged. */
static int dac_sound_apply_format(void)
{
    if (!dac_ctrl.format_valid) {
        LLOGE("dac_sound_start: format not set");
        return -1;
    }

    if (dac_ctrl.i2s_opened &&
        dac_ctrl.applied_rate == dac_ctrl.sample_rate &&
        dac_ctrl.applied_channels == dac_ctrl.channels) {
        /* Same format: never re-setup, it would clear the queued audio. */
        luat_i2s_resume(DAC_PC_I2S_ID);
        return 0;
    }

    luat_i2s_conf_t conf = {0};
    conf.id = DAC_PC_I2S_ID;
    conf.mode = LUAT_I2S_MODE_MASTER;
    conf.standard = LUAT_I2S_MODE_I2S;
    conf.sample_rate = dac_ctrl.sample_rate;
    conf.data_bits = (uint8_t)dac_ctrl.bps;
    conf.channel_bits = (uint8_t)dac_ctrl.bps;
    conf.channel_format = dac_ctrl.channels == 2 ? LUAT_I2S_CHANNEL_STEREO : LUAT_I2S_CHANNEL_LEFT;

    if (luat_i2s_setup(&conf) != 0) {
        LLOGE("dac_sound_start: i2s setup failed (%u Hz %u ch %u bit)",
              dac_ctrl.sample_rate, dac_ctrl.channels, dac_ctrl.bps);
        dac_ctrl.i2s_opened = 0;
        return -1;
    }

    dac_ctrl.i2s_opened = 1;
    dac_ctrl.applied_rate = dac_ctrl.sample_rate;
    dac_ctrl.applied_channels = dac_ctrl.channels;
    LLOGI("dac_sound_pc ready: %u Hz %u ch %u bit period=%u",
          dac_ctrl.sample_rate, dac_ctrl.channels, dac_ctrl.bps,
          (unsigned)SOUND_TX_FIFO_PERIOD_SIZE);
    return 0;
}

int dac_sound_init(int idx)
{
    (void)idx;

    dac_ctrl.inited = 1;
    dac_ctrl.volume = 100;

    return 0;
}

int dac_sound_start(int stream)
{
    if (!dac_ctrl.inited) {
        LLOGI("dac uninitialized");
        return -1;
    }

    if (!dac_ctrl.event_callback) {
        LLOGI("dac not played");
        return -1;
    }

    if (stream == SOUND_RECORD) {
        return 0;
    }
    if (stream != SOUND_PLAYBACK) {
        LLOGI("stream error");
        return -1;
    }

    if (dac_playing) {
        return 0; /* already started, keep the queue intact */
    }

    if (dac_sound_apply_format() != 0) {
        return -1;
    }

    dac_ctrl.event_callback(SOUND_TX_START, dac_tx_fifo, dac_ctrl.user_data);
    dac_playing = 1;

    if (dac_pump_task == NULL) {
        if (luat_rtos_task_create(&dac_pump_task, DAC_PC_PUMP_STACK, DAC_PC_PUMP_PRIO,
                                  "dac_pc_pump", dac_pump_task_body, NULL, 0) != 0) {
            dac_pump_task = NULL;
            dac_playing = 0;
            LLOGE("dac_sound_start: pump task create failed");
            return -1;
        }
    }

    return 0;
}

int dac_sound_stop(int stream)
{
    if (!dac_ctrl.inited) {
        LLOGI("dac uninitialized");
        return -1;
    }

    if (stream == SOUND_RECORD) {
        return 0;
    }
    if (stream != SOUND_PLAYBACK) {
        LLOGI("stream error");
        return -1;
    }

    /* Idempotent: the pump task may call stop on itself from the SOUND_TX_PERIOD
     * callback, so this must not block or join the task. */
    if (!dac_playing) {
        return 0;
    }
    dac_playing = 0;

    if (dac_ctrl.event_callback) {
        dac_ctrl.event_callback(SOUND_TX_STOP, dac_tx_fifo, dac_ctrl.user_data);
    }

    return 0;
}

int dac_sound_pause(int enable)
{
    if (!dac_ctrl.inited) {
        return -1;
    }
    (void)enable;
    return 0;
}

int dac_sound_set_format(unsigned int samplerate, unsigned int channel, unsigned int bps)
{
    dac_ctrl.sample_rate = samplerate;
    dac_ctrl.channels = channel;
    dac_ctrl.bps = bps ? bps : LUAT_I2S_BITS_16;
    dac_ctrl.format_valid = 1;
    return 0;
}

int dac_sound_set_callback(void (*callback)(emSOUND_EVENT event, void *data, void *user_data), void *user_data)
{
    dac_ctrl.user_data = user_data;
    dac_ctrl.event_callback = callback;
    return 0;
}

int dac_sound_fill_txfifo(int per, void *data, unsigned int size)
{
    /* The upper layer passes NULL here to clear the fifo (device side is a no-op
     * too, Audio V2 consumes the stream through the event callback instead). */
    (void)per;
    (void)data;
    (void)size;
    return 0;
}

int dac_sound_set_volume(int volume)
{
    if (!dac_ctrl.inited) {
        return -1;
    }
    dac_ctrl.volume = volume;
    return 0;
}
