#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include "uv.h"

#define LUAT_LOG_TAG "rtos.sem"
#include "luat_log.h"

typedef struct pc_sem {
    uv_sem_t s;
} pc_sem_t;

int luat_rtos_semaphore_create(luat_rtos_semaphore_t* semaphore_handle, uint32_t init_count) {
    if (semaphore_handle == NULL) return -1;
    pc_sem_t* sem = luat_heap_malloc(sizeof(pc_sem_t));
    if (sem == NULL) {
        LLOGE("semaphore malloc failed");
        return -1;
    }
    int ret = uv_sem_init(&sem->s, init_count);
    if (ret != 0) {
        LLOGE("uv_sem_init failed %d", ret);
        luat_heap_free(sem);
        return -1;
    }
    *semaphore_handle = sem;
    return 0;
}

int luat_rtos_semaphore_delete(luat_rtos_semaphore_t semaphore_handle) {
    if (semaphore_handle == NULL) return -1;
    pc_sem_t* sem = (pc_sem_t*)semaphore_handle;
    uv_sem_destroy(&sem->s);
    luat_heap_free(sem);
    return 0;
}

int luat_rtos_semaphore_take(luat_rtos_semaphore_t semaphore_handle, uint32_t timeout) {
    if (semaphore_handle == NULL) return -1;
    pc_sem_t* sem = (pc_sem_t*)semaphore_handle;

    if (timeout == 0) {
        return uv_sem_trywait(&sem->s) == 0 ? 0 : -1;
    }
    if (timeout == LUAT_WAIT_FOREVER || timeout == (uint32_t)(-1)) {
        uv_sem_wait(&sem->s);
        return 0;
    }
    // 超时等待：逐毫秒轮询
    uint32_t remaining = timeout;
    while (remaining > 0) {
        if (uv_sem_trywait(&sem->s) == 0) {
            return 0;
        }
        uv_sleep(1);
        remaining--;
    }
    return -1; // timeout
}

int luat_rtos_semaphore_release(luat_rtos_semaphore_t semaphore_handle) {
    if (semaphore_handle == NULL) return -1;
    pc_sem_t* sem = (pc_sem_t*)semaphore_handle;
    uv_sem_post(&sem->s);
    return 0;
}
