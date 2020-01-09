#ifndef LUAT_TIMER
#define LUAT_TIMER

#include "luat_base.h"
#include "luat_msgbus.h"

typedef struct luat_timer_t
{
    void* os_timer;
    int timeout;
    int _type;
    int _repeat;
    luat_msg_handler func;
}luat_timer_t;


int luat_timer_start(struct luat_timer_t* timer);
int luat_timer_stop(struct luat_timer_t* timer);


int luat_timer_mdelay(size_t ms);

#endif
