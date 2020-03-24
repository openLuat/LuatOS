#ifndef LUAT_TIMER
#define LUAT_TIMER

#include "luat_base.h"
#include "luat_msgbus.h"

typedef struct luat_timer
{
    void* os_timer;
    size_t id;
    size_t timeout;
    size_t type;
    int repeat;
    luat_msg_handler func;
}luat_timer_t;


int luat_timer_start(luat_timer_t* timer);
int luat_timer_stop(luat_timer_t* timer);
luat_timer_t* luat_timer_get(size_t timer_id);


int luat_timer_mdelay(size_t ms);

#endif
