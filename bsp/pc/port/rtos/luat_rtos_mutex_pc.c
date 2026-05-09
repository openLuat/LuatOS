#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"

#include "luat_posix_compat.h"

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
    pthread_mutex_t m;
    int lock;
} pc_mutex_t;

static int pc_mutex_init(pc_mutex_t *pm) {
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    int ret = pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    if (ret == 0) {
        ret = pthread_mutex_init(&pm->m, &attr);
    }
    pthread_mutexattr_destroy(&attr);
    if (ret != 0) {
        /* Fallback to default mutex if recursive not available */
        ret = pthread_mutex_init(&pm->m, NULL);
    }
    return ret;
}


/* -----------------------------------信号量模拟互斥锁，可以在中断中unlock-------------------------------*/
void *luat_mutex_create(void) {
    pc_mutex_t* m = luat_heap_malloc(sizeof(pc_mutex_t));
    if (m == NULL) {
        LLOGE("mutex 分配内存失败");
        return NULL;
    }
    memset(m, 0, sizeof(pc_mutex_t));
    int ret = pc_mutex_init(m);
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
    pthread_mutex_lock(&m->m);
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
        return -2;
    }
    pthread_mutex_unlock(&m->m);
    m->lock --;
    LLOGD("mutex unlock2 %p %d", m, m->lock);
    return 0;
}

void luat_mutex_release(void *mutex) {
    if (mutex == NULL)
        return;
    pc_mutex_t* m = (pc_mutex_t*)mutex;
    LLOGD("mutex release %p %d", m, m->lock);
    pthread_mutex_destroy(&m->m);
    luat_heap_free(m);
}

int luat_rtos_mutex_create(luat_rtos_mutex_t *mutex_handle) {
    if (mutex_handle == NULL) {
        return -1;
    }
    pc_mutex_t *m = luat_heap_malloc(sizeof(pc_mutex_t));
    if (m == NULL) {
        return -1;
    }
    memset(m, 0, sizeof(pc_mutex_t));
    int ret = pc_mutex_init(m);
    if (ret != 0) {
        luat_heap_free(m);
        return -1;
    }
    *mutex_handle = m;
    return 0;
}

int luat_rtos_mutex_lock(luat_rtos_mutex_t mutex_handle, uint32_t timeout) {
    if (mutex_handle == NULL) {
        return -1;
    }
    pc_mutex_t *m = (pc_mutex_t *)mutex_handle;

    if (timeout == 0) {
        int ret = pthread_mutex_trylock(&m->m);
        if (ret != 0) {
            return -1;
        }
        m->lock++;
        return 0;
    }

    if (timeout == LUAT_WAIT_FOREVER || timeout == (uint32_t)(-1)) {
        pthread_mutex_lock(&m->m);
        m->lock++;
        return 0;
    }

    uint32_t wait_time = timeout;
    while (1) {
        int ret = pthread_mutex_trylock(&m->m);
        if (ret == 0) {
            m->lock++;
            return 0;
        }
        if (ret != EBUSY) {
            return -1;
        }
        if (wait_time == 0) {
            return -1;
        }
        wait_time--;
        luat_sleep_ms(1);
    }
}

int luat_rtos_mutex_unlock(luat_rtos_mutex_t mutex_handle) {
    if (mutex_handle == NULL) {
        return -1;
    }
    pc_mutex_t *m = (pc_mutex_t *)mutex_handle;
    if (m->lock == 0) {
        return -2;
    }
    pthread_mutex_unlock(&m->m);
    m->lock--;
    return 0;
}

int luat_rtos_mutex_delete(luat_rtos_mutex_t mutex_handle) {
    if (mutex_handle == NULL) {
        return -1;
    }
    pc_mutex_t *m = (pc_mutex_t *)mutex_handle;
    pthread_mutex_destroy(&m->m);
    luat_heap_free(m);
    return 0;
}
