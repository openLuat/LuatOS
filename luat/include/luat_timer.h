#ifndef LUAT_TIMER_H
#define LUAT_TIMER_H

#include "luat_base.h"
#ifdef __LUATOS__
#include "luat_msgbus.h"
#endif

typedef struct luat_timer
{
    void* os_timer;
    size_t id;
    size_t timeout;
    size_t type;
    int repeat;
#ifdef __LUATOS__
    luat_msg_handler func;
#endif

}luat_timer_t;


int luat_timer_start(luat_timer_t* timer);
int luat_timer_stop(luat_timer_t* timer);
luat_timer_t* luat_timer_get(size_t timer_id);


int luat_timer_mdelay(size_t ms);

#endif
