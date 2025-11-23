#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"

#include "uv.h"

#define LUAT_LOG_TAG "rtos.mutex"
#include "luat_log.h"

#ifndef LUAT_MUTEX_DEBUG
#define LUAT_MUTEX_DEBUG 0
#endif

#if LUAT_MUTEX_DEBUG == 0
#undef LLOGD
#define LLOGD(...)
#endif

typedef struct pc_mutex
{
    uv_mutex_t m;
    int lock;
}pc_mutex_t;


/* -----------------------------------信号量模拟互斥锁，可以在中断中unlock-------------------------------*/
void *luat_mutex_create(void) {
    pc_mutex_t* m = luat_heap_malloc(sizeof(pc_mutex_t));
    if (m == NULL) {
        LLOGE("mutex 分配内存失败");
        return NULL;
    }
    memset(m, 0, sizeof(pc_mutex_t));
    int ret = uv_mutex_init(&m->m);
    if (ret) {
        LLOGE("mutex 初始化失败 %d", ret);
        luat_heap_free(m);
        return NULL;
    }
    return m;
}
LUAT_RET luat_mutex_lock(void *mutex) {
    if (mutex == NULL) {
        return -1;
    }
    pc_mutex_t* m = (pc_mutex_t*)mutex;
    LLOGD("mutex lock1 %p %d", m, m->lock);
    uv_mutex_lock(&m->m);
    m->lock ++;
    LLOGD("mutex lock2 %p %d", m, m->lock);
    return 0;
}

LUAT_RET luat_mutex_unlock(void *mutex) {
    if (mutex == NULL)
        return -1;
    pc_mutex_t* m = (pc_mutex_t*)mutex;
    LLOGD("mutex unlock1 %p %d", m, m->lock);
    if (m->lock == 0) {
        //LLOGI("该mutex未加锁,不能unlock %p", mutex);
        return -2;
    }
    uv_mutex_unlock(&m->m);
    m->lock --;
    LLOGD("mutex unlock2 %p %d", m, m->lock);
    return 0;
}

void luat_mutex_release(void *mutex) {
    if (mutex == NULL)
        return;
    pc_mutex_t* m = (pc_mutex_t*)mutex;
    LLOGD("mutex release %p %d", m, m->lock);
    if (&m->lock == 0)
        uv_mutex_destroy(&m->m);
    luat_heap_free(m);
}
