
#ifndef LUAT_DAC_H
#define LUAT_DAC_H

#include "luat_base.h"

int luat_dac_setup(uint32_t ch, uint32_t freq, uint32_t mode);
int luat_dac_write(uint32_t ch, uint16_t* buff, size_t len);
int luat_dac_close(uint32_t ch);

#endif

