#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include "luat_posix_compat.h"

#define LUAT_LOG_TAG "rtos.sem"
#include "luat_log.h"

/* Counting semaphore implemented with mutex + condvar */
typedef struct pc_sem {
    pthread_mutex_t m;
    pthread_cond_t  cv;
    int             count;
} pc_sem_t;

int luat_rtos_semaphore_create(luat_rtos_semaphore_t* semaphore_handle, uint32_t init_count) {
    if (semaphore_handle == NULL) return -1;
    pc_sem_t* sem = luat_heap_malloc(sizeof(pc_sem_t));
    if (sem == NULL) {
        LLOGE("semaphore malloc failed");
        return -1;
    }
    int ret = pthread_mutex_init(&sem->m, NULL);
    if (ret != 0) {
        LLOGE("semaphore mutex init failed %d", ret);
        luat_heap_free(sem);
        return -1;
    }
    ret = pthread_cond_init(&sem->cv, NULL);
    if (ret != 0) {
        LLOGE("semaphore cond init failed %d", ret);
        pthread_mutex_destroy(&sem->m);
        luat_heap_free(sem);
        return -1;
    }
    sem->count = (int)init_count;
    *semaphore_handle = sem;
    return 0;
}

int luat_rtos_semaphore_delete(luat_rtos_semaphore_t semaphore_handle) {
    if (semaphore_handle == NULL) return -1;
    pc_sem_t* sem = (pc_sem_t*)semaphore_handle;
    pthread_cond_destroy(&sem->cv);
    pthread_mutex_destroy(&sem->m);
    luat_heap_free(sem);
    return 0;
}

int luat_rtos_semaphore_take(luat_rtos_semaphore_t semaphore_handle, uint32_t timeout) {
    if (semaphore_handle == NULL) return -1;
    pc_sem_t* sem = (pc_sem_t*)semaphore_handle;

    pthread_mutex_lock(&sem->m);

    if (timeout == 0) {
        /* Non-blocking: return immediately if count == 0 */
        int ret = -1;
        if (sem->count > 0) {
            sem->count--;
            ret = 0;
        }
        pthread_mutex_unlock(&sem->m);
        return ret;
    }

    if (timeout == LUAT_WAIT_FOREVER || timeout == (uint32_t)(-1)) {
        while (sem->count <= 0) {
            pthread_cond_wait(&sem->cv, &sem->m);
        }
        sem->count--;
        pthread_mutex_unlock(&sem->m);
        return 0;
    }

    /* Timed wait */
    struct timespec abs;
    luat_calc_abs_timeout(&abs, timeout);
    int ret = 0;
    while (sem->count <= 0) {
        ret = pthread_cond_timedwait(&sem->cv, &sem->m, &abs);
        if (ret == ETIMEDOUT) {
            pthread_mutex_unlock(&sem->m);
            return -1;
        }
    }
    sem->count--;
    pthread_mutex_unlock(&sem->m);
    return 0;
}

int luat_rtos_semaphore_release(luat_rtos_semaphore_t semaphore_handle) {
    if (semaphore_handle == NULL) return -1;
    pc_sem_t* sem = (pc_sem_t*)semaphore_handle;
    pthread_mutex_lock(&sem->m);
    sem->count++;
    pthread_cond_signal(&sem->cv);
    pthread_mutex_unlock(&sem->m);
    return 0;
}
