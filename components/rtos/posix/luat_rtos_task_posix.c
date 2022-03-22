
#include "luat_base.h"
#include "luat_rtos.h"

#include "pthread.h"
#include "string.h"
#include "luat_malloc.h"
#include "limits.h"

#define LUAT_LOG_TAG "posix"
#include "luat_log.h"

#define PTHREAD_COUNT 16

static pthread_t threads[PTHREAD_COUNT] = {0};

static int next_thread_id(void) {
    for (size_t i = 0; i < PTHREAD_COUNT; i++)
    {
        if (threads[i] == NULL)
            return i;
    }
    return -1;
}

static void* pthread_proxy(void* params) {
    luat_thread_t* t = (luat_thread_t*) params;
    t->entry(t->userdata);
    threads[t->id] = NULL;
    return NULL;
}

LUAT_RET luat_thread_start(luat_thread_t* thread) {
    pthread_attr_t tattr; 
    size_t size; 
    int ret; 
    size = (PTHREAD_STACK_MIN + 0x1000); 
    /* setting a new size */ 
    ret = pthread_attr_setstacksize(&tattr, size);

    int thread_id = next_thread_id();
    if (thread_id < 0) {
        LLOGW("too many thread, can't create new thread");
        return LUAT_ERR_FAIL;
    }
    thread->id = thread_id;
    LLOGD("thread id %d", thread_id);
    ret = pthread_create(&threads[thread_id], NULL, pthread_proxy, thread);
    if (ret != 0) {
        LLOGW("pthread_create fail %d", ret);
        return LUAT_ERR_FAIL;
    }
    return LUAT_ERR_OK;
}

LUAT_RET luat_thread_stop(luat_thread_t* thread) {
    LLOGE("thread stop isn't supported");
    return LUAT_ERR_FAIL;
}

LUAT_RET luat_thread_delete(luat_thread_t* thread) {
    LLOGE("thread stop isn't supported");
    return LUAT_ERR_FAIL;
}
