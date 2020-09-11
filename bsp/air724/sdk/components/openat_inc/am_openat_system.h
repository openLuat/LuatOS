/*********************************************************
  Copyright (C), AirM2M Tech. Co., Ltd.
  Author: lifei
  Description: AMOPENAT 开放平台
  Others:
  History: 
    Version： Date:       Author:   Modification:
    V0.1      2012.12.14  lifei     创建文件
*********************************************************/
#ifndef AM_OPENAT_SYSTEM_H
#define AM_OPENAT_SYSTEM_H

#include "am_openat_common.h"

/****************************** SYSTEM ******************************/
#define OPENAT_CUST_TASKS_PRIORITY_BASE 128
#define OPENAT_SEMAPHORE_TIMEOUT_MIN_PERIOD 5 //5ms
#define OPENAT_MSG_PROC_COUNT (30)

#define OPENAT_OS_SUSPENDED   (0xFFFFFFFF)






typedef enum E_AMOPENAT_OS_CREATION_FLAG_TAG
{
    OPENAT_OS_CREATE_DEFAULT = 0,   /* 线程创建后，立即启动 */
    OPENAT_OS_CREATE_SUSPENDED = 1, /* 线程创建后，先挂起 */
}E_AMOPENAT_OS_CREATION_FLAG;

typedef struct T_AMOPENAT_TASK_INFO_TAG
{
    UINT16 nStackSize;
    UINT16 nPriority;
    CONST UINT8 *pName;
}T_AMOPENAT_TASK_INFO;

/*+\NEW\liweiqiang\2013.7.1\[OpenAt]增加系统主频设置接口*/
typedef enum E_AMOPENAT_SYS_FREQ_TAG
{
    OPENAT_SYS_FREQ_32K    = 32768,
    OPENAT_SYS_FREQ_13M    = 13000000,
    OPENAT_SYS_FREQ_26M    = 26000000,
    OPENAT_SYS_FREQ_39M    = 39000000,
    OPENAT_SYS_FREQ_52M    = 52000000,
    OPENAT_SYS_FREQ_78M    = 78000000,
    OPENAT_SYS_FREQ_104M   = 104000000,
    OPENAT_SYS_FREQ_156M   = 156000000,
    OPENAT_SYS_FREQ_208M   = 208000000,
    OPENAT_SYS_FREQ_250M   = 249600000,
    OPENAT_SYS_FREQ_312M   = 312000000,
}E_AMOPENAT_SYS_FREQ;
/*-\NEW\liweiqiang\2013.7.1\[OpenAt]增加系统主频设置接口*/

/****************************** TIME ******************************/
typedef struct T_AMOPENAT_SYSTEM_DATETIME_TAG
{
    UINT16 nYear;
    UINT8  nMonth;
    UINT8  nDay;
    UINT8  nHour;
    UINT8  nMin;
    UINT8  nSec;
    UINT8  DayIndex; /* 0=Sunday */
}T_AMOPENAT_SYSTEM_DATETIME;


typedef struct
{
  //uint8               alarmIndex;  /*只能设置1个*/
  bool                alarmOn; /* 1 set,0 clear*/
/*+\NEW\RUFEI\2015.3.9\提交闹钟消息*/
  //E_AMOPENAT_ALARM_RECURRENT     alarmRecurrent;/*只支持1个闹钟*/
/*-\NEW\RUFEI\2015.3.9\提交闹钟消息*/
  T_AMOPENAT_SYSTEM_DATETIME alarmTime;
}T_AMOPENAT_ALARM_PARAM;

/****************************** TIMER ******************************/
#define OPENAT_TIMER_MIN_PERIOD 5 //5ms

typedef struct T_AMOPENAT_TIMER_PARAMETER_TAG
{
    HANDLE hTimer;      /* create_timer 接口返回的 HANDLE */
    UINT32 period;      /* start_timer 接口传入的 nMillisecondes */
    PVOID  pParameter;  /* create_timer 接口传入的 pParameter */
}T_AMOPENAT_TIMER_PARAMETER;

/* 定时器到时回调函数，参数 pParameter 为栈变量指针，客户程序中不需要释放该指针 */
typedef VOID (*PTIMER_EXPFUNC)(VOID *pParameter);

typedef VOID (*PMINUTE_TICKFUNC)(VOID);

typedef  void(*openat_msg_proc)(void *pParameter);


typedef VOID (*PTASK_MAIN)(PVOID pParameter);

typedef struct {
    uint8 *buf;
    uint32 size;        
    uint32 head;
    uint32 tail;
    unsigned empty: 1;
    unsigned full:  1;
    unsigned overflow:  1;  
}CycleQueue;

void QueueClean(CycleQueue *Q_ptr);

int QueueInsert(CycleQueue *Q_ptr, uint8 *data, uint32 len);

int QueueDelete(CycleQueue *Q_ptr, uint8 *data, uint32 len);

int QueueGetFreeSpace(CycleQueue *Q_ptr);

int QueueLen(CycleQueue *Q_ptr);



#endif /* AM_OPENAT_SYSTEM_H */

