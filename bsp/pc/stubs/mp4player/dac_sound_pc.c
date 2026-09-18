/**
 * @file dac_sound_pc.c
 * @brief PC simulator no-op stub for CCM42xx DAC/sound hardware interface.
 *
 * The real dac_sound.c drives platform-specific DAC + DMA peripheral registers
 * that do not exist on a PC host. This stub provides the current
 * sound_dev_port signatures so that sound_dev_port.c can link on the PC
 * simulator. All functions return 0 (success) and perform no actual I/O.
 *
 * For real audio output on PC, replace this file with an SDL2 Audio backend.
 */

#include "dac_sound.h"

int dac_sound_init(int idx)
{
    (void)idx;
    return 0;
}

int dac_sound_start(int stream)
{
    (void)stream;
    return 0;
}

int dac_sound_stop(int stream)
{
    (void)stream;
    return 0;
}

int dac_sound_pause(int enable)
{
    (void)enable;
    return 0;
}

int dac_sound_set_format(unsigned int samplerate, unsigned int channel, unsigned int bps)
{
    (void)samplerate;
    (void)channel;
    (void)bps;
    return 0;
}

int dac_sound_set_callback(void (*callback)(emSOUND_EVENT event, void *data, void *user_data), void *user_data)
{
    (void)callback;
    (void)user_data;
    return 0;
}

int dac_sound_fill_txfifo(int per, void *data, unsigned int size)
{
    (void)per;
    (void)data;
    (void)size;
    return 0;
}

int dac_sound_set_volume(int volume)
{
    (void)volume;
    return 0;
}
