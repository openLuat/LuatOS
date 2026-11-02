#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"

#include "luat_posix_compat.h"

#define LUAT_LOG_TAG "rtos.mutex"
#include "luat_log.h"

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


/*
 * luat_mutex_* 按真机约定用信号量模拟，对象就是 pc_sem_t，初值 1。
 * lock 是 take，unlock 是 give。同线程第二次 lock 会堵住，
 * 直到别的线程 luat_rtos_semaphore_release。
 * 下面的 luat_rtos_mutex_* 仍是递归 pthread 互斥锁，两者不能混用。
 */
void *luat_mutex_create(void) {
    luat_rtos_semaphore_t sem = NULL;
    if (luat_rtos_semaphore_create(&sem, 1) != 0) {
        LLOGE("mutex 分配失败");
        return NULL;
    }
    return sem;
}

LUAT_RET luat_mutex_lock(void *mutex) {
    if (mutex == NULL) {
        return -1;
    }
    return luat_rtos_semaphore_take((luat_rtos_semaphore_t)mutex, LUAT_WAIT_FOREVER);
}

LUAT_RET luat_mutex_unlock(void *mutex) {
    if (mutex == NULL) {
        return -1;
    }
    return luat_rtos_semaphore_release((luat_rtos_semaphore_t)mutex);
}

void luat_mutex_release(void *mutex) {
    if (mutex == NULL) {
        return;
    }
    luat_rtos_semaphore_delete((luat_rtos_semaphore_t)mutex);
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

    /* 有限等待: 优先使用 pthread_mutex_timedlock (POSIX.1-2001 可选, pthreads4w 也支持) */
    {
        struct timespec abs;
        luat_calc_abs_timeout(&abs, timeout);
        int ret = pthread_mutex_timedlock(&m->m, &abs);
        if (ret != 0) {
            return -1;
        }
        m->lock++;
        return 0;
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
    /* 在真正 unlock 前递减。lock 计数和 pthread 互斥锁必须一起改。 */
    m->lock--;
    pthread_mutex_unlock(&m->m);
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
