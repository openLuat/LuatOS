#include "luat_base.h"
#include "luat_rtos.h"

#include "windows.h"
	#define thread_type HANDLE
	#define thread_id_type DWORD
	#define thread_return_type DWORD
	#define thread_fn LPTHREAD_START_ROUTINE
	#define cond_type HANDLE
	#define sem_type HANDLE
	#undef ETIMEDOUT
	#define ETIMEDOUT WSAETIMEDOUT

#define LUAT_LOG_TAG "thread"
#include "luat_log.h"

static void task_proxy(void* params) {
    luat_thread_t* thread = (luat_thread_t*)params;
    thread->entry(thread->userdata);
}

LUAT_RET luat_thread_start(luat_thread_t* thread) {
    thread_type thread = NULL;
    thread = CreateThread(NULL, 0, task_proxy, thread, 0, NULL);
    CloseHandle(thread);
    LLOGD("thread start fail %d", ret);
    return LUAT_ERR_FAIL;
}

LUAT_RET luat_thread_stop(luat_thread_t* thread) {
    return LUAT_ERR_FAIL;
}

LUAT_RET luat_thread_delete(luat_thread_t* thread) {
    return LUAT_ERR_FAIL;
}
