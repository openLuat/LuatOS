/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#include "gbc.h"

#if (GBC_ENABLE_SOUND == 1)

static const uint8_t gbc_apu_duty_table[4][8] = {
    {0, 0, 0, 0, 0, 0, 0, 1},
    {1, 0, 0, 0, 0, 0, 0, 1},
    {1, 0, 0, 0, 0, 1, 1, 1},
    {0, 1, 1, 1, 1, 1, 1, 0},
};

static const uint8_t gbc_apu_noise_divisors[8] = {
    8, 16, 32, 48, 64, 80, 96, 112
};

GBC_INLINE uint16_t gbc_apu_square_period(uint16_t frequency)
{
    return (uint16_t)((2048 - (frequency & 0x07FF)) << 2);
}

GBC_INLINE uint16_t gbc_apu_wave_period(uint16_t frequency)
{
    return (uint16_t)((2048 - (frequency & 0x07FF)) << 1);
}

GBC_INLINE uint32_t gbc_apu_noise_period(gbc_apu_noise_t *noise)
{
    return (uint32_t)gbc_apu_noise_divisors[noise->divisor_code & 0x07] << noise->clock_shift;
}

GBC_INLINE uint8_t gbc_apu_envelope_timer(uint8_t period)
{
    return period == 0 ? 8 : period;
}

static void gbc_apu_sync_nr52(gbc_t *gbc)
{
    uint8_t status = 0x70;

    if (gbc->apu.enabled) {
        status |= 0x80;
        if (gbc->apu.square1.enabled) {
            status |= 0x01;
        }
        if (gbc->apu.square2.enabled) {
            status |= 0x02;
        }
        if (gbc->apu.wave.enabled) {
            status |= 0x04;
        }
        if (gbc->apu.noise.enabled) {
            status |= 0x08;
        }
    }
    gbc->mmu.io[0x26] = status;
}

static void gbc_apu_disable_channels(gbc_t *gbc)
{
    gbc->apu.square1.enabled = 0;
    gbc->apu.square2.enabled = 0;
    gbc->apu.wave.enabled = 0;
    gbc->apu.noise.enabled = 0;
}

static void gbc_apu_trigger_square(gbc_t *gbc, gbc_apu_square_t *ch, uint8_t index)
{
    uint8_t nrx1 = gbc->mmu.io[index == 1 ? 0x11 : 0x16];
    uint8_t nrx2 = gbc->mmu.io[index == 1 ? 0x12 : 0x17];
    uint8_t nrx3 = gbc->mmu.io[index == 1 ? 0x13 : 0x18];
    uint8_t nrx4 = gbc->mmu.io[index == 1 ? 0x14 : 0x19];

    ch->dac_enabled = (uint8_t)((nrx2 & 0xF8) != 0);
    ch->enabled = ch->dac_enabled;
    ch->duty = nrx1 >> 6;
    if (ch->length_counter == 0) {
        ch->length_counter = 64;
    }
    ch->length_enabled = (uint8_t)((nrx4 & 0x40) != 0);
    ch->envelope_volume = nrx2 >> 4;
    ch->envelope_add = (uint8_t)((nrx2 & 0x08) != 0);
    ch->envelope_period = nrx2 & 0x07;
    ch->envelope_timer = gbc_apu_envelope_timer(ch->envelope_period);
    ch->frequency = (uint16_t)nrx3 | ((uint16_t)(nrx4 & 0x07) << 8);
    ch->timer = gbc_apu_square_period(ch->frequency);
    if (index == 1) {
        uint8_t nr10 = gbc->mmu.io[0x10];
        ch->shadow_frequency = ch->frequency;
        ch->sweep_period = (nr10 >> 4) & 0x07;
        ch->sweep_timer = gbc_apu_envelope_timer(ch->sweep_period);
        ch->sweep_negate = (uint8_t)((nr10 & 0x08) != 0);
        ch->sweep_negate_used = 0;
        ch->sweep_shift = nr10 & 0x07;
    }
    gbc_apu_sync_nr52(gbc);
}

static void gbc_apu_trigger_wave(gbc_t *gbc)
{
    gbc_apu_wave_t *wave = &gbc->apu.wave;
    uint8_t nr30 = gbc->mmu.io[0x1A];
    uint8_t nr31 = gbc->mmu.io[0x1B];
    uint8_t nr32 = gbc->mmu.io[0x1C];
    uint8_t nr33 = gbc->mmu.io[0x1D];
    uint8_t nr34 = gbc->mmu.io[0x1E];

    (void)nr31;
    wave->dac_enabled = (uint8_t)((nr30 & 0x80) != 0);
    wave->enabled = wave->dac_enabled;
    if (wave->length_counter == 0) {
        wave->length_counter = 256;
    }
    wave->length_enabled = (uint8_t)((nr34 & 0x40) != 0);
    wave->volume_code = (nr32 >> 5) & 0x03;
    wave->frequency = (uint16_t)nr33 | ((uint16_t)(nr34 & 0x07) << 8);
    wave->timer = gbc_apu_wave_period(wave->frequency);
    wave->position = 0;
    gbc_apu_sync_nr52(gbc);
}

static void gbc_apu_trigger_noise(gbc_t *gbc)
{
    gbc_apu_noise_t *noise = &gbc->apu.noise;
    uint8_t nr42 = gbc->mmu.io[0x21];
    uint8_t nr43 = gbc->mmu.io[0x22];
    uint8_t nr44 = gbc->mmu.io[0x23];

    noise->dac_enabled = (uint8_t)((nr42 & 0xF8) != 0);
    noise->enabled = noise->dac_enabled;
    if (noise->length_counter == 0) {
        noise->length_counter = 64;
    }
    noise->length_enabled = (uint8_t)((nr44 & 0x40) != 0);
    noise->envelope_volume = nr42 >> 4;
    noise->envelope_add = (uint8_t)((nr42 & 0x08) != 0);
    noise->envelope_period = nr42 & 0x07;
    noise->envelope_timer = gbc_apu_envelope_timer(noise->envelope_period);
    noise->clock_shift = nr43 >> 4;
    noise->width_mode = (uint8_t)((nr43 & 0x08) != 0);
    noise->divisor_code = nr43 & 0x07;
    noise->timer = gbc_apu_noise_period(noise);
    noise->lfsr = 0x7FFF;
    gbc_apu_sync_nr52(gbc);
}

static void gbc_apu_clock_square(gbc_apu_square_t *ch, uint8_t cycles)
{
    int16_t timer;
    uint16_t period;

    if (!ch->enabled) {
        return;
    }
    period = gbc_apu_square_period(ch->frequency);
    if (period == 0) {
        period = 4;
    }
    timer = (int16_t)ch->timer - cycles;
    while (timer <= 0) {
        timer = (int16_t)(timer + period);
        ch->duty_step = (uint8_t)((ch->duty_step + 1) & 0x07);
    }
    ch->timer = (uint16_t)timer;
}

static void gbc_apu_clock_wave(gbc_apu_wave_t *wave, uint8_t cycles)
{
    int16_t timer;
    uint16_t period;

    if (!wave->enabled) {
        return;
    }
    period = gbc_apu_wave_period(wave->frequency);
    if (period == 0) {
        period = 2;
    }
    timer = (int16_t)wave->timer - cycles;
    while (timer <= 0) {
        timer = (int16_t)(timer + period);
        wave->position = (uint8_t)((wave->position + 1) & 0x1F);
    }
    wave->timer = (uint16_t)timer;
}

static void gbc_apu_clock_noise(gbc_apu_noise_t *noise, uint8_t cycles)
{
    uint32_t timer;
    uint32_t period;
    uint8_t remaining;

    if (!noise->enabled) {
        return;
    }
    period = gbc_apu_noise_period(noise);
    if (period == 0) {
        period = 8;
    }
    timer = noise->timer;
    remaining = cycles;
    while (remaining > 0) {
        uint16_t bit = (uint16_t)((noise->lfsr ^ (noise->lfsr >> 1)) & 0x01);
        if (timer > remaining) {
            timer -= remaining;
            remaining = 0;
            break;
        }
        remaining = (uint8_t)(remaining - timer);
        timer = period;
        noise->lfsr = (uint16_t)((noise->lfsr >> 1) | (bit << 14));
        if (noise->width_mode) {
            noise->lfsr = (uint16_t)((noise->lfsr & ~(1U << 6)) | (bit << 6));
        }
    }
    noise->timer = timer;
}

static void gbc_apu_clock_lengths(gbc_t *gbc)
{
    if (gbc->apu.square1.length_enabled && gbc->apu.square1.length_counter > 0 &&
        --gbc->apu.square1.length_counter == 0) {
        gbc->apu.square1.enabled = 0;
    }
    if (gbc->apu.square2.length_enabled && gbc->apu.square2.length_counter > 0 &&
        --gbc->apu.square2.length_counter == 0) {
        gbc->apu.square2.enabled = 0;
    }
    if (gbc->apu.wave.length_enabled && gbc->apu.wave.length_counter > 0 &&
        --gbc->apu.wave.length_counter == 0) {
        gbc->apu.wave.enabled = 0;
    }
    if (gbc->apu.noise.length_enabled && gbc->apu.noise.length_counter > 0 &&
        --gbc->apu.noise.length_counter == 0) {
        gbc->apu.noise.enabled = 0;
    }
}

static void gbc_apu_clock_envelope(gbc_apu_square_t *ch)
{
    if (!ch->enabled || ch->envelope_period == 0) {
        return;
    }
    if (ch->envelope_timer > 0) {
        ch->envelope_timer--;
    }
    if (ch->envelope_timer == 0) {
        ch->envelope_timer = gbc_apu_envelope_timer(ch->envelope_period);
        if (ch->envelope_add && ch->envelope_volume < 15) {
            ch->envelope_volume++;
        } else if (!ch->envelope_add && ch->envelope_volume > 0) {
            ch->envelope_volume--;
        }
    }
}

static void gbc_apu_clock_noise_envelope(gbc_apu_noise_t *noise)
{
    if (!noise->enabled || noise->envelope_period == 0) {
        return;
    }
    if (noise->envelope_timer > 0) {
        noise->envelope_timer--;
    }
    if (noise->envelope_timer == 0) {
        noise->envelope_timer = gbc_apu_envelope_timer(noise->envelope_period);
        if (noise->envelope_add && noise->envelope_volume < 15) {
            noise->envelope_volume++;
        } else if (!noise->envelope_add && noise->envelope_volume > 0) {
            noise->envelope_volume--;
        }
    }
}

static void gbc_apu_clock_sweep(gbc_t *gbc)
{
    gbc_apu_square_t *ch = &gbc->apu.square1;
    uint16_t delta;
    uint16_t next;

    if (!ch->enabled || ch->sweep_period == 0) {
        return;
    }
    if (ch->sweep_timer > 0) {
        ch->sweep_timer--;
    }
    if (ch->sweep_timer != 0 || ch->sweep_shift == 0) {
        return;
    }
    ch->sweep_timer = gbc_apu_envelope_timer(ch->sweep_period);
    delta = (uint16_t)(ch->shadow_frequency >> ch->sweep_shift);
    if (ch->sweep_negate) {
        ch->sweep_negate_used = 1;
        next = (uint16_t)(ch->shadow_frequency - delta);
    } else {
        next = (uint16_t)(ch->shadow_frequency + delta);
    }
    if (next > 2047) {
        ch->enabled = 0;
    } else {
        ch->shadow_frequency = next;
        ch->frequency = next;
        gbc->mmu.io[0x13] = (uint8_t)next;
        gbc->mmu.io[0x14] = (uint8_t)((gbc->mmu.io[0x14] & 0xF8) | ((next >> 8) & 0x07));
    }
}

static void gbc_apu_clock_frame_sequencer(gbc_t *gbc, uint8_t cycles)
{
    gbc_apu_t *apu = &gbc->apu;

    apu->frame_acc += (uint32_t)cycles * 512U;
    while (apu->frame_acc >= GBC_CPU_CLOCK_FREQ) {
        apu->frame_acc -= GBC_CPU_CLOCK_FREQ;
        switch (apu->frame_step & 0x07) {
        case 0:
        case 4:
            gbc_apu_clock_lengths(gbc);
            break;
        case 2:
        case 6:
            gbc_apu_clock_lengths(gbc);
            gbc_apu_clock_sweep(gbc);
            break;
        case 7:
            gbc_apu_clock_envelope(&apu->square1);
            gbc_apu_clock_envelope(&apu->square2);
            gbc_apu_clock_noise_envelope(&apu->noise);
            break;
        default:
            break;
        }
        apu->frame_step = (uint8_t)((apu->frame_step + 1) & 0x07);
        gbc_apu_sync_nr52(gbc);
    }
}

GBC_INLINE int16_t gbc_apu_square_sample(gbc_apu_square_t *ch)
{
    if (!ch->enabled || !ch->dac_enabled) {
        return 0;
    }
    if (gbc_apu_duty_table[ch->duty & 0x03][ch->duty_step & 0x07] == 0) {
        return (int16_t)(-ch->envelope_volume);
    }
    return ch->envelope_volume;
}

GBC_INLINE int16_t gbc_apu_wave_sample(gbc_t *gbc)
{
    gbc_apu_wave_t *wave = &gbc->apu.wave;
    uint8_t packed;
    uint8_t sample;
    int8_t centered;

    if (!wave->enabled || !wave->dac_enabled || wave->volume_code == 0) {
        return 0;
    }
    packed = gbc->mmu.io[0x30 + (wave->position >> 1)];
    sample = (wave->position & 1) ? (packed & 0x0F) : (packed >> 4);
    /* Centre around 8 first, then apply volume to preserve sign */
    centered = (int8_t)sample - 8;
    switch (wave->volume_code) {
    case 1: break;
    case 2: centered = (int8_t)(centered / 2); break;
    case 3: centered = (int8_t)(centered / 4); break;
    default: centered = 0; break;
    }
    return (int16_t)centered;
}

GBC_INLINE int16_t gbc_apu_noise_sample(gbc_apu_noise_t *noise)
{
    if (!noise->enabled || !noise->dac_enabled) {
        return 0;
    }
    return (noise->lfsr & 1) ? (int16_t)(-noise->envelope_volume) : noise->envelope_volume;
}

static void gbc_apu_push_sample(gbc_t *gbc)
{
    gbc_apu_t *apu = &gbc->apu;
    uint8_t nr50 = gbc->mmu.io[0x24];
    uint8_t nr51 = gbc->mmu.io[0x25];
    int16_t ch1 = gbc_apu_square_sample(&apu->square1);
    int16_t ch2 = gbc_apu_square_sample(&apu->square2);
    int16_t ch3 = gbc_apu_wave_sample(gbc);
    int16_t ch4 = gbc_apu_noise_sample(&apu->noise);
    int16_t left = 0;
    int16_t right = 0;
    int32_t mixed_left;
    int32_t mixed_right;
    int16_t pcm_left;
    int16_t pcm_right;

    if (nr51 & 0x01) right = (int16_t)(right + ch1);
    if (nr51 & 0x02) right = (int16_t)(right + ch2);
    if (nr51 & 0x04) right = (int16_t)(right + ch3);
    if (nr51 & 0x08) right = (int16_t)(right + ch4);
    if (nr51 & 0x10) left = (int16_t)(left + ch1);
    if (nr51 & 0x20) left = (int16_t)(left + ch2);
    if (nr51 & 0x40) left = (int16_t)(left + ch3);
    if (nr51 & 0x80) left = (int16_t)(left + ch4);

    mixed_left = (int32_t)left * (((nr50 >> 4) & 0x07) + 1) * 24;
    mixed_right = (int32_t)right * ((nr50 & 0x07) + 1) * 24;
    if (mixed_left > 32767) {
        pcm_left = 32767;
    } else if (mixed_left < -32768) {
        pcm_left = -32768;
    } else {
        pcm_left = (int16_t)mixed_left;
    }
    if (mixed_right > 32767) {
        pcm_right = 32767;
    } else if (mixed_right < -32768) {
        pcm_right = -32768;
    } else {
        pcm_right = (int16_t)mixed_right;
    }
    apu->sample_buffer[apu->sample_index++] = (uint8_t)pcm_left;
    apu->sample_buffer[apu->sample_index++] = (uint8_t)((uint16_t)pcm_left >> 8);
    apu->sample_buffer[apu->sample_index++] = (uint8_t)pcm_right;
    apu->sample_buffer[apu->sample_index++] = (uint8_t)((uint16_t)pcm_right >> 8);
    if (apu->sample_index >= sizeof(apu->sample_buffer)) {
        gbc_sound_output(apu->sample_buffer, apu->sample_index);
        apu->sample_index = 0;
    }
}

#endif

void gbc_apu_reset(gbc_t *gbc)
{
#if (GBC_ENABLE_SOUND == 1)
    gbc_memset(&gbc->apu, 0, sizeof(gbc->apu));
    gbc->apu.enabled = (uint8_t)((gbc->mmu.io[0x26] & 0x80) != 0);
    gbc->apu.noise.lfsr = 0x7FFF;
    gbc_apu_sync_nr52(gbc);
#else
    (void)gbc;
#endif
}

uint8_t gbc_apu_read(gbc_t *gbc, uint8_t reg)
{
#if (GBC_ENABLE_SOUND == 1)
    if (reg == 0x26) {
        gbc_apu_sync_nr52(gbc);
    }
#endif
    return gbc->mmu.io[reg];
}

void gbc_apu_write(gbc_t *gbc, uint8_t reg, uint8_t data)
{
#if (GBC_ENABLE_SOUND == 1)
    gbc_apu_t *apu = &gbc->apu;

    if (reg >= 0x30 && reg <= 0x3F) {
        gbc->mmu.io[reg] = data;
        return;
    }

    if (reg == 0x26) {
        if ((data & 0x80) == 0) {
            apu->enabled = 0;
            gbc_apu_disable_channels(gbc);
            gbc_memset(&gbc->mmu.io[0x10], 0, 0x16);
            gbc->mmu.io[0x26] = 0x70;
        } else if (!apu->enabled) {
            apu->enabled = 1;
            gbc_apu_sync_nr52(gbc);
        }
        return;
    }

    if (!apu->enabled) {
        return;
    }

    gbc->mmu.io[reg] = data;
    switch (reg) {
    case 0x10:
        /* NR10: update CH1 sweep params immediately */
        apu->square1.sweep_period = (data >> 4) & 0x07;
        if (apu->square1.sweep_negate && ((data & 0x08) == 0) && apu->square1.sweep_negate_used) {
            apu->square1.enabled = 0;
        }
        apu->square1.sweep_negate = (uint8_t)((data & 0x08) != 0);
        apu->square1.sweep_shift = data & 0x07;
        break;
    case 0x11:
        apu->square1.duty = data >> 6;
        apu->square1.length_counter = (uint8_t)(64 - (data & 0x3F));
        break;
    case 0x12:
        apu->square1.dac_enabled = (uint8_t)((data & 0xF8) != 0);
        if (!apu->square1.dac_enabled) {
            apu->square1.enabled = 0;
        }
        break;
    case 0x13:
        /* NR13: CH1 frequency low byte – update immediately without trigger */
        apu->square1.frequency = (uint16_t)data |
                                  ((uint16_t)(gbc->mmu.io[0x14] & 0x07) << 8);
        break;
    case 0x14:
        /* NR14: CH1 frequency high bits and length_enabled always updated */
        apu->square1.frequency = (uint16_t)gbc->mmu.io[0x13] |
                                  ((uint16_t)(data & 0x07) << 8);
        apu->square1.length_enabled = (uint8_t)((data & 0x40) != 0);
        if (data & 0x80) {
            gbc_apu_trigger_square(gbc, &apu->square1, 1);
        }
        break;
    case 0x16:
        apu->square2.duty = data >> 6;
        apu->square2.length_counter = (uint8_t)(64 - (data & 0x3F));
        break;
    case 0x17:
        apu->square2.dac_enabled = (uint8_t)((data & 0xF8) != 0);
        if (!apu->square2.dac_enabled) {
            apu->square2.enabled = 0;
        }
        break;
    case 0x18:
        /* NR23: CH2 frequency low byte – update immediately without trigger */
        apu->square2.frequency = (uint16_t)data |
                                  ((uint16_t)(gbc->mmu.io[0x19] & 0x07) << 8);
        break;
    case 0x19:
        /* NR24: CH2 frequency high bits and length_enabled always updated */
        apu->square2.frequency = (uint16_t)gbc->mmu.io[0x18] |
                                  ((uint16_t)(data & 0x07) << 8);
        apu->square2.length_enabled = (uint8_t)((data & 0x40) != 0);
        if (data & 0x80) {
            gbc_apu_trigger_square(gbc, &apu->square2, 2);
        }
        break;
    case 0x1A:
        apu->wave.dac_enabled = (uint8_t)((data & 0x80) != 0);
        if (!apu->wave.dac_enabled) {
            apu->wave.enabled = 0;
        }
        break;
    case 0x1B:
        apu->wave.length_counter = (uint16_t)(256 - data);
        break;
    case 0x1C:
        /* NR32: wave volume code – update immediately without trigger */
        apu->wave.volume_code = (data >> 5) & 0x03;
        break;
    case 0x1D:
        /* NR33: wave frequency low byte – update immediately without trigger */
        apu->wave.frequency = (uint16_t)data |
                               ((uint16_t)(gbc->mmu.io[0x1E] & 0x07) << 8);
        break;
    case 0x1E:
        /* NR34: wave frequency high bits and length_enabled always updated */
        apu->wave.frequency = (uint16_t)gbc->mmu.io[0x1D] |
                               ((uint16_t)(data & 0x07) << 8);
        apu->wave.length_enabled = (uint8_t)((data & 0x40) != 0);
        if (data & 0x80) {
            gbc_apu_trigger_wave(gbc);
        }
        break;
    case 0x20:
        apu->noise.length_counter = (uint8_t)(64 - (data & 0x3F));
        break;
    case 0x21:
        apu->noise.dac_enabled = (uint8_t)((data & 0xF8) != 0);
        if (!apu->noise.dac_enabled) {
            apu->noise.enabled = 0;
        }
        break;
    case 0x23:
        /* NR44: noise length_enabled always updated */
        apu->noise.length_enabled = (uint8_t)((data & 0x40) != 0);
        if (data & 0x80) {
            gbc_apu_trigger_noise(gbc);
        }
        break;
    default:
        break;
    }
    gbc_apu_sync_nr52(gbc);
#else
    gbc->mmu.io[reg] = data;
#endif
}

void gbc_apu_step(gbc_t *gbc, uint8_t cycles)
{
#if (GBC_ENABLE_SOUND == 1)
    gbc_apu_t *apu = &gbc->apu;

    if (!apu->enabled) {
        return;
    }
    gbc_apu_clock_frame_sequencer(gbc, cycles);
    gbc_apu_clock_square(&apu->square1, cycles);
    gbc_apu_clock_square(&apu->square2, cycles);
    gbc_apu_clock_wave(&apu->wave, cycles);
    gbc_apu_clock_noise(&apu->noise, cycles);

    apu->sample_acc += (uint32_t)cycles * GBC_APU_SAMPLE_RATE;
    while (apu->sample_acc >= GBC_CPU_CLOCK_FREQ) {
        apu->sample_acc -= GBC_CPU_CLOCK_FREQ;
        gbc_apu_push_sample(gbc);
    }
#else
    (void)gbc;
    (void)cycles;
#endif
}

