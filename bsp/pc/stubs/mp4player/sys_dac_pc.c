/**
 * @file sys_dac_pc.c
 * @brief PC simulator no-op stub for CCM42xx DAC DMA hardware interface.
 *
 * The real sys_dac.c configures DMA channels and DAC peripheral registers
 * that are specific to the CCM42xx SoC and do not exist on a PC host.
 * This stub provides the same function signatures so that dac_sound.c (and
 * transitively sound.c / mp4_decode.c) can link cleanly on the PC simulator.
 *
 * For real audio output on PC, replace this file with an SDL2 Audio backend
 * and update dac_sound_pc.c accordingly.
 */

#include "sys_dac.h"

int dac_dma_transmit(short *pcm_buffer, unsigned int pcm_num, void (*cb)(void))
{
    (void)pcm_buffer;
    (void)pcm_num;
    /* Immediately invoke the callback so the caller is not left waiting. */
    if (cb) cb();
    return 0;
}

int dac_dma_set_rate(unsigned int rate)
{
    (void)rate;
    return 0;
}

int dac_dma_start(void)
{
    return 0;
}

int dac_dma_stop(void)
{
    return 0;
}

int dac_dma_pause(int enable)
{
    (void)enable;
    return 0;
}
