/**
 * @file i2s_sound_pc.c
 * @brief PC simulator no-op stub for CCM42xx I2S/sound hardware interface.
 *
 * sound_dev_port.c registers both DAC and I2S devices. The real i2s_sound.c
 * talks to CCM42xx I2S/DMA registers, so PC uses this stub instead.
 */

#include "i2s_sound.h"

int i2s_sound_init(int idx)
{
    (void)idx;
    return 0;
}

int i2s_sound_start(int stream)
{
    (void)stream;
    return 0;
}

int i2s_sound_stop(int stream)
{
    (void)stream;
    return 0;
}

int i2s_sound_pause(int enable)
{
    (void)enable;
    return 0;
}

int i2s_sound_set_format(unsigned int samplerate, unsigned int channel, unsigned int bps)
{
    (void)samplerate;
    (void)channel;
    (void)bps;
    return 0;
}

int i2s_sound_set_callback(void (*callback)(emSOUND_EVENT event, void *data, void *user_data), void *user_data)
{
    (void)callback;
    (void)user_data;
    return 0;
}

int i2s_sound_fill_txfifo(int per, void *data, unsigned int size)
{
    (void)per;
    (void)data;
    (void)size;
    return 0;
}

int i2s_sound_set_volume(int volume)
{
    (void)volume;
    return 0;
}
