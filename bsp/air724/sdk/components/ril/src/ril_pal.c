
#include <stdio.h>
#include <string.h>

#include "at_process.h"
#include "ril_pal.h"


typedef struct _UART_DATA {
	UINT32 DataLen;
	UINT8 DataBuf[0];
} UART_DATA, *PUART_DATA, **PPUART_DATA;

extern PAL_THREAD_ID RIL_GetReaderThreadId(void);
extern HANDLE ATC_GetThreadID(void);

void RIL_SendAtData(void* data, int len,BOOL CR_flag);


void *RIL_Malloc(size_t size)
{
	return OPENAT_malloc(size);
}

void RIL_Free(void *p)
{
	OPENAT_free(p);
}

void *RIL_Calloc(size_t number, size_t size)
{
	void *p;
    
	p = OPENAT_malloc(number*size);

	ASSERT(p != NULL);

  memset(p, 0, number*size);

  return p;
}
PAL_THREAD_ID pal_ril_thread_create(CHAR *name, void (*thread_entry)(void *), UINT8 pri, UINT32 size, void* param_ptr)
{
    HANDLE threadID;
    OPENAT_create_task(&threadID, thread_entry, param_ptr, NULL, size, pri, 0, 10, name);
	ASSERT(threadID != 0);
    return threadID;
}

void pal_ril_thread_sleep(UINT32 ms)
{
	OPENAT_sleep(ms);
}

UINT pal_ril_send_signal(PAL_THREAD_ID thread_id, void *msg)
{
    return (OPENAT_send_message(thread_id, 0,msg,0)? PAL_RIL_SUCCESS : PAL_RIL_ERROR);
}



UINT pal_ril_send_high_prio_signal(PAL_THREAD_ID thread_id, void *msg)
{
    return (IVTBL(SendHighPriorityMessage)(thread_id, msg)? PAL_RIL_SUCCESS : PAL_RIL_ERROR);
}


UINT pal_ril_receive_signal(PAL_THREAD_ID thread_id, void **pp_msg)
{
	ASSERT(thread_id != 0);
    

    int msgId;
    OPENAT_wait_message(thread_id, &msgId, pp_msg, 0);

    ASSERT(*pp_msg != NULL);

    return PAL_RIL_SUCCESS;
}

PAL_SEMAPHORE_ID pal_ril_sema_create(CHAR *name, UINT32 count)
{
	return (PAL_SEMAPHORE_ID)OPENAT_create_semaphore(count);
}

UINT pal_ril_sema_get(PAL_SEMAPHORE_ID id, UINT32 timeout)
{
	return (OPENAT_wait_semaphore((HANDLE)id, timeout)? PAL_RIL_SUCCESS : PAL_RIL_ERROR);
}

UINT pal_ril_sema_put(PAL_SEMAPHORE_ID id)
{
    return (OPENAT_release_semaphore((HANDLE)id)? PAL_RIL_SUCCESS : PAL_RIL_ERROR);
}

UINT pal_ril_sema_delete(PAL_SEMAPHORE_ID id)
{
	return (OPENAT_delete_semaphore(id) ? PAL_RIL_SUCCESS : PAL_RIL_ERROR);
}

void pal_ril_sleep_msec(long msec)
{
	OPENAT_sleep(msec);
}

int asprintf(char **str, const char *fmt, ...)
{
    va_list ap;
	size_t str_l;

    *str = RIL_Malloc(1024/*TODO*/);
    
	va_start(ap, fmt);
    str_l = vsprintf(*str, fmt, ap);
    va_end(ap);

    return str_l;
}

/*-\bug WM-25\wangzhiqiang\2011.10.8\加入内存泄漏的测试代码*/

void pal_ril_channel_write(const char *s, int len, BOOL CR_flag )
{
    RIL_SendAtData((void *)s, len,CR_flag);
}

int pal_ril_channel_read(char *buffer, int size)
{
	RILChannelData *p_msg;
    int len;
    
	pal_ril_receive_signal(RIL_GetReaderThreadId(), (void **)&p_msg);

	len = p_msg->len;
    
	if(size < p_msg->len)
    {
		len = size;

        RIL_DBG_OUT(("[pal_ril_channel_read]: data lost,buffer size(%d) data len(%d)", size, p_msg->len));
    }

    RIL_DBG_OUT(("[ril] %s (%d) %s", __FUNCTION__, p_msg->len, p_msg->data));
	
    memcpy(buffer, p_msg->data, len);

    if(NULL != p_msg->data)
    {
        OPENAT_free(p_msg->data);
    }
    OPENAT_free(p_msg);
    
	return len;
}


char *
__strdup (const char *s)
{
  size_t len = strlen (s) + 1;
  void *new_s = RIL_Malloc (len);

  ASSERT(new_s != NULL);

  memcpy (new_s, s, len);

  return (char *)new_s; 
}



UINT pal_ril_receive_signal_ex(PAL_THREAD_ID thread_id, void **pp_msg)
{
	pal_ril_receive_signal(thread_id, pp_msg);

	return PAL_RIL_SUCCESS;
}

void RIL_SendAtData(void* data, int len,BOOL CR_flag)
{
    UINT8 *pData;

    if(TRUE == CR_flag)
    {
        len += 2;
    }
    pData = iot_os_malloc(len+1);
    
    ASSERT(NULL != pData);
    
    if(TRUE == CR_flag)
    {
        memcpy(pData, data, len - 2);
        pData[len - 2] = '\r';
        pData[len - 1] = '\n';
    }
    else//not with CR
    {
        memcpy(pData, data, len);
    }
    pData[len] = '\0';
    
    IVTBL(send_at_command)(pData, len);
    iot_os_free(pData);
}


void  AT_DUMP(const char*  prefix, const char*  buff, int  len)
{
    if (len < 0)
    {
	    LOGD("%s", buff);
    }    
	else
    {
		char traceBuffer[400+1];

		memcpy(traceBuffer, buff, len);

        traceBuffer[len] = '\0';

        LOGD("%s", traceBuffer);
    }
}

