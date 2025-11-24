
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_timer.h"
#include "luat_pcconf.h"

#include "uv.h"

#define LUAT_LOG_TAG "timer"
#include "luat_log.h"

extern uv_loop_t *main_loop;

#define TIMER_ID_MAX (1024)
static uv_timer_t* timers[TIMER_ID_MAX];

extern uv_mutex_t timer_lock;

static int get_free_timer_id(void)
{
    for (size_t i = 0; i < TIMER_ID_MAX; i++)
    {
        if (timers[i] == NULL)
        {
            return i;
        }
    }
    return -1;
}

static uv_timer_t *get_timer_by_id(size_t id)
{
    for (size_t i = 0; i < TIMER_ID_MAX; i++)
    {
        if (timers[i] == NULL || timers[i]->data == NULL)
        {
            continue;
        }
        luat_timer_t *timer = (luat_timer_t *)timers[i]->data;
        if (timer->id == id)
        {
            return timers[i];
        }
    }
    return NULL;
}

int luat_timer_mdelay(size_t ms)
{
    if (ms)
        uv_sleep(ms);
    return 0;
}

static void timer_cb(uv_timer_t *handle)
{
    // LLOGD("timer cb");
    int ret = 0;
    luat_timer_t *timer = (luat_timer_t *)handle->data;
    int id = timer->id;
    uv_timer_t *t = get_timer_by_id(id);
    if (t == NULL)
    {
        LLOGE("no such timer %d", id);
        return;
    }
    // LLOGD("found timer, msgbus put");
    timer = (luat_timer_t *)t->data;
    if (timer->repeat > 0) {
        // LLOGD("timer againt %d", timer->repeat);
        timer->repeat --;
        ret = uv_timer_start(t, timer_cb, timer->timeout, 0);
        // LLOGD("uv_timer_again %d", ret);
    }
    else if (timer->repeat == -1) {
        // LLOGD("timer again, repeat forever");
        ret = uv_timer_start(t, timer_cb, timer->timeout, 0);
        // LLOGD("uv_timer_again %d", ret);
    }
    else {
        // LLOGD("single time timer");
    }
    if (ret)
        LLOGD("timer 出错了");
    rtos_msg_t msg;
    msg.handler = timer->func;
    msg.ptr = NULL;
    msg.arg1 = timer->id;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 0);
}

int luat_timer_start(luat_timer_t *timer)
{
    uv_mutex_lock(&timer_lock);
    int ret = 0;
    int id = get_free_timer_id();
    if (id < 0)
    {
        LLOGE("too many timer created");
        uv_mutex_unlock(&timer_lock);
        return -1;
    }
    timers[id] = luat_heap_malloc(sizeof(uv_timer_t));
    uv_timer_t *timer_req = timers[id];
    ret = uv_timer_init(main_loop, timer_req);
    if (ret) {
        LLOGE("uv_timer_init %d", ret);
        free_uv_handle(timers[id]);
        timers[id] = NULL;
        uv_mutex_unlock(&timer_lock);
        return -1;
    }
    // LLOGD("uv_timer_init %d", ret);
    timer_req->data = timer;
    timer->os_timer = timer_req;
    ret = uv_timer_start(timer_req, timer_cb, timer->timeout, 0);
    if (ret) {
        LLOGE("uv_timer_start %d", ret);
    }
    // else
    //     LLOGD("timer[%d] 启动成功 %d %d", id, timer->timeout, timer->repeat);
    uv_mutex_unlock(&timer_lock);
    return ret;
}
int luat_timer_stop(luat_timer_t *timer)
{
    uv_mutex_lock(&timer_lock);
    // LLOGD("timer stop %d", timer);
    uv_timer_t *timer_req = (uv_timer_t *)timer->os_timer;
    int ret = 0;
    for (size_t i = 0; i < TIMER_ID_MAX; i++)
    {
        if (timer_req == timers[i]) {
            // LLOGD("释放timer %p", timer_req);
            ret = uv_timer_stop(timer_req);
            if (ret)
                LLOGI("uv_timer_stop %d", ret);
            free_uv_handle(timer_req);
            timers[i] = NULL;
            uv_mutex_unlock(&timer_lock);
            return 0;
        }
    }
    // LLOGD("没有找到对应的timer");
    uv_mutex_unlock(&timer_lock);
    return -1;
}
luat_timer_t *luat_timer_get(size_t timer_id)
{
    // LLOGD("timer get");
    uv_mutex_lock(&timer_lock);
    uv_timer_t *timer = get_timer_by_id(timer_id);
    if (timer == NULL) {
        uv_mutex_unlock(&timer_lock);
        return NULL;
    }
    luat_timer_t * t = (luat_timer_t *)timer->data;
    uv_mutex_unlock(&timer_lock);
    return t;
}

void luat_timer_us_delay(size_t us)
{
    (void)us;
}
