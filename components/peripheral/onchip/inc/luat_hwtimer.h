
#ifndef LUAT_HWTIMER_H
#define LUAT_HWTIMER_H
#include "luat_base.h"

typedef struct luat_hwtimer_conf {
    uint8_t   unit;           /**< timer accuracy */
    uint32_t  timeout;        /**< timeout period */
    uint8_t   is_repeat;      /**< cycle timer */
}luat_hwtimer_conf_t;

int luat_hwtimer_create(luat_hwtimer_conf_t *conf);
int luat_hwtimer_start(int id);
int luat_hwtimer_stop(int id);
int luat_hwtimer_read(int id);
int luat_hwtimer_change(int id, uint32_t newtimeout);
int luat_hwtimer_destroy(int id);

#endif
