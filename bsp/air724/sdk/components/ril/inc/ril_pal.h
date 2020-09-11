
#ifndef _RIL_PAL_H_
#define _RIL_PAL_H_

#include "am_openat.h"


#ifndef HANDLE
#define HANDLE 		UINT32
#endif

typedef HANDLE		PAL_THREAD_ID;
typedef HANDLE		PAL_SEMAPHORE_ID;

#define PAL_SEMA_WAIT_FOREVER				0

#ifndef ssize_t
#define ssize_t		int
#endif

/* RIL PAL层结果值 */
#define PAL_RIL_SUCCESS			0

#define PAL_RIL_ERROR			1

/* 地址对齐4字节对齐 */
#define PAD_SIZE(l)							(((l)+3)&~3)


#define AT_TOK_DEBUG 

#ifdef AT_TOK_DEBUG    
#define RIL_DBG_OUT(s)						iot_debug_print s
#define LOGD								iot_debug_print
#define LOGW								iot_debug_print
#define LOGE								iot_debug_print
#define LOGI								iot_debug_print
#else
#define RIL_DBG_OUT(s)						
#define LOGD(...) 								
#define LOGW(...) 								
#define LOGE(...) 							
#define LOGI(...) 
#endif

char *__strdup (const char *s);

#define strdup				__strdup

void *RIL_Malloc(size_t size);

void RIL_Free(void *p);

void *RIL_Calloc(size_t number, size_t size);

PAL_THREAD_ID pal_ril_thread_create(CHAR *name, void (*thread_entry)(void *), UINT8 pri, UINT32 size, void* param_ptr);

PAL_THREAD_ID pal_ril_thread_self(void);

UINT pal_ril_send_signal(PAL_THREAD_ID thread_id, void *msg);

UINT pal_ril_send_high_prio_signal(PAL_THREAD_ID thread_id, void *msg);

UINT pal_ril_receive_signal(PAL_THREAD_ID thread_id, void **pp_msg);

PAL_SEMAPHORE_ID pal_ril_sema_create(CHAR *name, UINT32 count);

UINT pal_ril_sema_get(PAL_SEMAPHORE_ID id, UINT32 timeout);

UINT pal_ril_sema_put(PAL_SEMAPHORE_ID id);

UINT pal_ril_sema_delete(PAL_SEMAPHORE_ID id);

void pal_ril_sleep_msec(long msec);

int asprintf(char **str, const char *fmt, ...);


void pal_ril_channel_write(const char *s, int len,BOOL CR_flag);

int pal_ril_channel_read(char *buffer, int size);
UINT pal_ril_receive_signal_ex(PAL_THREAD_ID thread_id, void **pp_msg);

void  AT_DUMP(const char*  prefix, const char*  buff, int  len);


#endif/*_RIL_PAL_H_*/

