
#ifndef LUAT_DAC_H
#define LUAT_DAC_H

#include "luat_base.h"

typedef enum {
	LUAT_DAC_CHL_L = 0,
	LUAT_DAC_CHL_R,
	LUAT_DAC_CHL_LR,
	LUAT_DAC_CHL_MAX,
} luat_dac_chl_t;

typedef enum {
	LUAT_DAC_SAMP_8000  = 8000,
	LUAT_DAC_SAMP_12000 = 12000,
	LUAT_DAC_SAMP_22050 = 22050,
	LUAT_DAC_SAMP_24000 = 24000,
    LUAT_DAC_SAMP_32000 = 32000,
    LUAT_DAC_SAMP_44100 = 44100,
    LUAT_DAC_SAMP_48000 = 48000,
	LUAT_DAC_SAMP_MAX,
} luat_dac_samp_t;

typedef enum {
	LUAT_DAC_BITS_8  = 8,
    LUAT_DAC_BITS_16 = 16,
    LUAT_DAC_BITS_24 = 24,
    LUAT_DAC_BITS_32 = 32,
	LUAT_DAC_BITS_MAX,
} luat_dac_bits_t;

typedef struct {
	luat_dac_chl_t dac_chl;
	luat_dac_samp_t samp_rate;
    luat_dac_bits_t bits;
	uint32_t work_mode;
} luat_dac_config_t;

int luat_dac_setup(uint32_t ch, luat_dac_config_t* config);
int luat_dac_write(uint32_t ch, uint8_t* buff, size_t size);
int luat_dac_close(uint32_t ch);

#endif

