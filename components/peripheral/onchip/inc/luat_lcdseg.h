
#ifndef LUAT_LCDSEG_H
#define LUAT_LCDSEG_H
#include "luat_base.h"

typedef struct luat_lcd_options
{
	/** Bias configuration */
	uint8_t  bias;
	/** Duty configuration */
	uint8_t  duty;
	/** Vlcd configuration */
	uint8_t  vlcd;
	/** com number */
	uint8_t	com_number;
	/** Fresh rate configuration */
	uint16_t fresh_rate;
	uint32_t com_mark;
	uint32_t seg_mark;
} luat_lcd_options_t;

int luat_lcdseg_setup(luat_lcd_options_t *opts);

int luat_lcdseg_enable(uint8_t enable);

int luat_lcdseg_power(uint8_t enable);

int luat_lcdseg_seg_set(uint8_t com, uint32_t seg, uint8_t val);

#endif
