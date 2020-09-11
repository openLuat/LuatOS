/*********************************************************
  Copyright (C), AirM2M Tech. Co., Ltd.
  Author: lifei
  Description: AMOPENAT 开放平台
  Others:
  History: 
    Version： Date:       Author:   Modification:
    V0.1      2012.12.14  lifei     创建文件
	V0.2      2012.12.26  brezen    添加pmd接口
	V0.3      2012.12.29  brezen    添加spi接口
	V0.4      2013.01.08  brezen    修改spi接口
	V0.5      2O13.01.14  brezen    1、增加黑白屏初始化参数
	                                2、增加黑白屏清屏接口
									3、减少黑白屏指令处理时间，满足单独使用指令刷屏
    V0.6      2013.01.14  brezen    修改黑白屏清屏接口参数
	V0.7      2013.01.15  brezen    修改黑白屏清屏接口参数
    V0.8      2013.01.17  brezen    1、添加系统电源控制接口 2、添加系统开关机接口
    V0.9      2013.01.23  brezen    修改SPI的编译warning  
    V1.0      2013.01.28  brezen    添加PSAM卡接口
    V1.1      2013.01.30  brezen    修改poweron_system函数参数
    V1.2      2013.02.06  Jack.li   添加摄像头接口
    V1.3      2013.02.07  Jack.li   添加视频录制、视频播放接口
    V1.4      2013.02.10  Jack.li   修改彩屏初始化接口
    V1.5      2013.02.26  brezen    添加enter_deepsleep/exit_deepsleep接口
    V1.6      2013.03.21  maliang    文件系统接口和播放音频文件接口的文件名改为unicode little ending类型
    V1.7      2013.04.03  Jack.li    增加I2C接口
    V1.8      2013.05.15  xc        增加tts接口
	V1.9      2013.07.18  brezen    添加set_dte_at_filter接口
	V2.0      2013.07.22  brezen    添加send_data_to_dte  send_data_to_ci set_dte_device接口
	V2.1      2013.08.20  brezen    针对PSAM卡双向认证失败，rw_psam添加分布发送参数stopClock
	V2.2      2013.09.16  brezen    添加flush_file接口，掉电之前强行写入flash
	V2.3      2013.09.24  brezen    添加NV接口
	V2.4      2013.09.26  brezen    支持两张PSAM卡
	V2.5      2013.12.30  brezen    添加蓝牙接口
	V2.6      2014.6.26   brezen    添加蓝牙spp接口
	V2.7      2015.04.21  panjun    增加OLED的延时、SPI接口
	V2.8      2015.05.20  panjun    Export two values 'lua_lcd_height' and 'lua_lcd_width'.
	V2.9      2015.06.22  panjun    Optimize mechanism of LUA's timer.
	V3.0      2015.07.04  panjun    Define a macro 'OPENAT_MAX_TIMER_ID', Increase quantity of OPENAT's timer.
	V3.1      2016.03.26  panjun    Add TTSPLY's API.
	V3.2      2016.05.03  panjun    Add an API "rtos.sysdisk_free".
*********************************************************/
#ifndef AM_OPENAT_H
#define AM_OPENAT_H

//#include "utils.h"
#include "am_openat_system.h"
#include "am_openat_fs.h"
#include "am_openat_drv.h"
#include "am_openat_vat.h"
#include "am_openat_tts.h"
#include "am_openat_image.h"
/*-\NEW\zhuwangbin\2020.3.25\添加jpg文件的解码和显示*/
/*+\NEW\WZQ\2014.11.7\加入SSL RSA功能*/
#ifdef AM_OPENAT_SSL_RSA_SUPPORT
#include "openat_SSLRSA.h"
#endif

#include "am_openat_zbar.h"
#include "openat_camera.h"
/*-\NEW\WZQ\2014.11.7\加入SSL RSA功能*/
/*+\NEW\WJ\2019.1.8\添加证书有效时间校验*/
typedef struct {
    int     sec;         /* seconds */
    int     min;         /* minutes */
    int     hour;        /* hours */
    int     day;      
    int     mon;         /* month */
    int     year;        /* year */
}t_time;
/*-\NEW\WJ\2019.1.8\添加证书有效时间校验*/

#define IVTBL(func) OPENAT_##func

#define PUB_TRACE(pFormat, ...)  IVTBL(print)(pFormat, ##__VA_ARGS__)

//#define  NUCLEUS_TIMER_MECHANISM_ENABLE
#define  OPENAT_MAX_TIMERS 50
#define  OPENAT_MAX_TIMER_ID 60000
#define  LUA_TIMER_BASE LUA_APP_TIMER_0
#define  LUA_GIF_TIMER_BASE LUA_GIF_TIMER_0

/*\+NEW\yezhishe\2018.11.23\添加GPIO8,9,10,11\*/
#define GPIO8_R28 8
#define GPIO9_R27 9
#define GPIO10_R26 10
#define GPIO11_R17 11
/*\-NEW\yezhishe\2018.11.23\添加GPIO8,9,10,11\*/
/*+\NEW\wangyuan\2020.05.07\BUG_1126:支持wifi定位功能*/
typedef struct
{
	UINT32 bssid_low;  	//< mac address low
	UINT16 bssid_high; 	//< mac address high
	UINT8 channel;	 	//< channel id
	signed char rssival; 	 	//< signal strength
} OPENAT_wifiApInfo;

typedef struct
{
	UINT32 max;		 ///< set by caller, must room count for store aps
	UINT32 found; 	 ///< set by wifi, actual found ap count
	UINT32 maxtimeout; ///< max timeout in milliseconds for each channel
	OPENAT_wifiApInfo *aps;	 ///< room for aps
} OPENAT_wifiScanRequest;
/*-\NEW\wangyuan\2020.05.07\BUG_1126:支持wifi定位功能*/
    /*******************************************
    **                 SYSTEM                 **
    *******************************************/
BOOL OPENAT_create_task(                          /* 创建线程接口 */
                            HANDLE* handlePtr,
                            PTASK_MAIN pTaskEntry,  /* 线程主函数 */
                            PVOID pParameter,       /* 作为参数传递给线程主函数 */
                            PVOID pStackAddr,       /* 线程栈地址，当前不支持，请传入NULL */
                            UINT32 nStackSize,      /* 线程栈大小 */
                            UINT8 nPriority,        /* 线程优先级，该参数越大，线程优先级越低 */
                            UINT16 nCreationFlags,  /* 线程启动标记， 请参考E_AMOPENAT_OS_CREATION_FLAG */
                            UINT16 nTimeSlice,      /* 暂时不支持，请传入0 */
                            PCHAR pTaskName         /* 线程名称 */
                          );
VOID OPENAT_delete_task(HANDLE         task);

HANDLE OPENAT_current_task(                         /* 获取当前线程接口 */
                            VOID
                          );
/*+\BUG\wangyuan\2020.06.30\BUG_2411:支持中云信安, 兼容2g CSDK的接口添加*/
BOOL OPENAT_suspend_task(                           /* 挂起线程接口 */
    HANDLE hTask            /* 线程句柄，create_task接口返回值 */
);

BOOL OPENAT_resume_task(                            /* 恢复线程接口 */
    HANDLE hTask            /* 线程句柄，create_task接口返回值 */
);
/*-\BUG\wangyuan\2020.06.30\BUG_2411:支持中云信安, 兼容2g CSDK的接口添加*/
BOOL OPENAT_get_task_info(                          /* 获取当前线程创建信息接口 */
                            HANDLE hTask,           /* 线程句柄，create_task接口返回值 */
                            T_AMOPENAT_TASK_INFO *pTaskInfo /* 线程信息存储接口 */
                         );



    /****************************** 线程消息队列接口 ******************************/
BOOL OPENAT_wait_message(
                                     HANDLE   task,
                                     int* msg_id,
                                     void* * ppMessage,
                                     UINT32 nTimeOut
                                     );



BOOL OPENAT_free_message(
                                     void* message_body
                                     );

    
BOOL OPENAT_send_message(                           /* 发送消息接口，添加到消息队列尾部 */
                                      HANDLE   destTask,
                                      int msg_id,
                                      void* pMessage,          /* 存储消息指针 */
                                      int message_length);

/*+\TASK\wangyuan\2020.06.28\task_255:支持中云信安, 兼容2g CSDK的接口添加*/
BOOL OPENAT_SendHighPriorityMessage(             /* 发送高优先级消息接口，添加到消息队列头部 */
											    HANDLE hTask,           /* 线程句柄，create_task接口返回值 */
											    PVOID pMessage          /* 要发送消息指针 */
											);
/*-\TASK\wangyuan\2020.06.28\task_255:支持中云信安, 兼容2g CSDK的接口添加*/


BOOL OPENAT_available_message(                      /* 检测消息队列中是否有消息 */
                            HANDLE hTask            /* 线程句柄，create_task接口返回值 */
                             );

/******************************************************
   向OPENAT TASK发消息的接口
*******************************************************/
BOOL OPENAT_send_internal_message(                           /* 发送消息接口，添加到消息队列尾部 */
                                      int msg_id,
                                      void* pMessage,          /* 存储消息指针 */
                                      int message_length
                                      );

/****************************** 时间&定时器接口 ******************************/
HANDLE OPENAT_create_timer(                         /* 创建定时器接口 */
                            PTIMER_EXPFUNC pFunc,   /* 定时器到时处理函数 */
                            PVOID pParameter        /* 作为参数传递给定时器到时处理函数 */
                          );

/*+\NEW\zhuwangbin\2020.2.12\将timer的回调由中断改成task*/
HANDLE OPENAT_create_timerTask(                         /* 创建定时器接口 */
                            PTIMER_EXPFUNC pFunc,   /* 定时器到时处理函数 */
                            PVOID pParameter        /* 作为参数传递给定时器到时处理函数 */
                          );

/*-\NEW\zhuwangbin\2020.2.12\将timer的回调由中断改成task*/
HANDLE OPENAT_create_hir_timer(						/* 创建定时器接口 */
						PTIMER_EXPFUNC pFunc,	/* 定时器到时处理函数 */
						PVOID pParameter		/* 作为参数传递给定时器到时处理函数 */
					  );


BOOL OPENAT_start_timer(                            /* 启动定时器接口 */
                            HANDLE hTimer,          /* 定时器句柄，create_timer接口返回值 */
                            UINT32 nMillisecondes   /* 定时器时间 */
                       );

BOOL OPENAT_loop_start_timer(                            /* 启动循环定时器接口 */
                            HANDLE hTimer,          /* 定时器句柄，create_timer接口返回值 */
                            UINT32 nMillisecondes   /* 定时器时间 */
                       );

BOOL OPENAT_start_precise_timer(                            /* 启动定时器接口 */
                            HANDLE hTimer,          /* 定时器句柄，create_timer接口返回值 */
                            UINT32 nMillisecondes   /* 定时器时间 */
                       );

BOOL OPENAT_stop_timer(                             /* 停止定时器接口 */
                            HANDLE hTimer           /* 定时器句柄，create_timer接口返回值 */
                      );

UINT64 OPENAT_timer_remaining(
							HANDLE hTimer
						);

 BOOL OPENAT_play_gif(
                                             char* buff,
                                            UINT8* gif_buf, 
                                            int length,
                                            int x, 
                                            int y, 
                                            int times
                                            );



BOOL OPENAT_stop_gif(void);

VOID OPENAT_lcd_sleep(BOOL);

BOOL OPENAT_delete_timer(                           /* 删除定时器接口 */
                            HANDLE hTimer           /* 定时器句柄，create_timer接口返回值 */
                        );



BOOL OPENAT_available_timer(                        /* 检查定时器是否已经启动接口 */
                            HANDLE hTimer           /* 定时器句柄，create_timer接口返回值 */
                           );



BOOL OPENAT_get_minute_tick(                        /* minute indication infterface */
                            PMINUTE_TICKFUNC pFunc  /* if pFunc != NULL, one MINUTE interval timer will be started. else the timer will be stop */
                           );

UINT32 OPENAT_get_timestamp(void);
BOOL OPENAT_gmtime(UINT32 timestamp, T_AMOPENAT_SYSTEM_DATETIME* pDatetime);


BOOL OPENAT_get_system_datetime(                    /* 获取系统时间接口 */
                            T_AMOPENAT_SYSTEM_DATETIME* pDatetime/* 存储时间指针 */
                           );



BOOL OPENAT_set_system_datetime(                    /* 设置系统时间接口 */
                            T_AMOPENAT_SYSTEM_DATETIME* pDatetime/* 存储时间指针 */
                           );
/*+\NEW\wangyuan\2020.05.08\添加设置和获取当前时区的接口*/
void OPENAT_Set_TimeZone(INT32 timeZone);

INT8 OPENAT_get_TimeZone(VOID);
/*-\NEW\wangyuan\2020.05.08\添加设置和获取当前时区的接口*/

/****************************** ALARM接口 ******************************/
/*+\BUG\wangyuan\2020.04.30\BUG_1757:Air724目前没有alarm demo*/
BOOL OPENAT_InitAlarm(                                        /* 闹钟初始化接口 */
                            T_AMOPENAT_ALARM_CONFIG *pConfig   /* 闹钟配置参数 */
                       ); 



BOOL OPENAT_SetAlarm(                                        /* 闹钟设置/删除接口 */
                            T_AMOPENAT_ALARM_PARAM *pAlarmSet    /* 闹钟设置参数 */
                       );

/*-\BUG\wangyuan\2020.04.30\BUG_1757:Air724目前没有alarm demo*/

/****************************** 临界资源接口 ******************************/
HANDLE OPENAT_enter_critical_section(               /* 进入临界资源区接口，关闭所有中断 */
                            VOID
                                    );


VOID OPENAT_exit_critical_section(                  /* 退出临界资源区接口，开启中断 */
                            HANDLE hSection         /* 临界资源区句柄，enter_critical_section接口返回值 */
                                 );



/****************************** 信号量接口 ******************************/
HANDLE OPENAT_create_semaphore(                     /* 创建信号量接口 */
                            UINT32 nInitCount       /* 信号量数量 */
                              );



BOOL OPENAT_delete_semaphore(                       /* 删除信号量接口 */
                            HANDLE hSem             /* 信号量句柄，create_semaphore接口返回值 */
                            );



BOOL OPENAT_wait_semaphore(                         /* 获取信号量接口 */
                            HANDLE hSem,            /* 信号量句柄，create_semaphore接口返回值 */
                            UINT32 nTimeOut         /* 目前不支持 */
                          );



BOOL OPENAT_release_semaphore(
                            HANDLE hSem             /* 信号量句柄，create_semaphore接口返回值 */
                             );



UINT32 OPENAT_get_semaphore_value(                   /* 获取消耗量值*/
                            HANDLE hSem             /* 信号量句柄，create_semaphore接口返回值 */  
                            );



/****************************** 内存接口 ******************************/

#define OPENAT_malloc(size) OPENAT_malloc1(size, (char*)__FUNCTION__,(UINT32) __LINE__)
#define OPENAT_calloc(cnt,size) OPENAT_malloc1(cnt*size, (char*)__FUNCTION__,(UINT32) __LINE__)
PVOID OPENAT_malloc1(                                /* 内存申请接口 */
                            UINT32 nSize,            /* 申请的内存大小 */
							/*+\NEW \zhuwangbin\2020.02.3\修改warning*/
                            const char*  func,
							/*-\NEW \zhuwangbin\2020.02.3\修改warning*/
                            UINT32 line
                   );



PVOID OPENAT_realloc(                               /**/
                            PVOID pMemory,          /* 内存指针，malloc接口返回值 */
                            UINT32 nSize            /* 申请的内存大小 */
                    );



VOID OPENAT_free(                                   /* 内存释放接口 */
                            PVOID pMemory           /* 内存指针，malloc接口返回值 */
                );


/*+\bug2307\zhuwangbin\2020.06.20\添加OPENAT_MemoryUsed接口*/
VOID OPENAT_MemoryUsed(UINT32* total, UINT32* used); /* 获取可用内存使用情况*/
/*-\bug2307\zhuwangbin\2020.06.20\添加OPENAT_MemoryUsed接口*/
/****************************** 杂项接口 ******************************/
BOOL OPENAT_sleep(                                  /* 系统睡眠接口 */
                            UINT32 nMillisecondes   /* 睡眠时间 */
                 );

BOOL OPENAT_Delayms(                                  /* 延时接口 */
                            UINT32 nMillisecondes   /* 延时时间 */
                 );

INT64 OPENAT_get_system_tick(                      /* 获取系统tick接口 */
                            VOID
                             );



UINT32 OPENAT_rand(                                 /* 获取随机数接口 */
                            VOID
                  );



VOID OPENAT_srand(                                  /* 设置随机数种子接口 */
                            UINT32 seed             /* 随机数种子 */
                 );



VOID OPENAT_shut_down(                              /* 关机接口 */
                            VOID
                     );



VOID OPENAT_restart(                                /* 重启接口 */
                            VOID
                   );



/*+\NEW\liweiqiang\2013.7.1\[OpenAt]增加系统主频设置接口*/
VOID OPENAT_sys_request_freq(                       /* 主频控制接口 */
                            E_AMOPENAT_SYS_FREQ freq/* 主频值 */
                   );



UINT16 OPENAT_unicode_to_ascii(UINT8 *pOutBuffer, WCHAR *pInBuffer);


UINT16 OPENAT_ascii_to_unicode(WCHAR *pOutBuffer, UINT8 *pInBuffer);

    
/*-\NEW\liweiqiang\2013.7.1\[OpenAt]增加系统主频设置接口*/
    /*******************************************
    **              FILE SYSTEM               **
    *******************************************/
INT32 OPENAT_open_file(                             /* 打开文件接口 *//* 正常句柄返回值从0开始，小于0错误发生 */
/*+\BUG WM-719\maliang\2013.3.21\文件系统接口和播放音频文件接口的文件名改为unicode little ending类型*/
                            char* pszFileNameUniLe,/* 文件全路径名称 unicode little endian*/
                            UINT32 iFlag,           /* 打开标志 */
	                        UINT32 iAttr            /* 文件属性，暂时不支持，请填入0 */
                      );



INT32 OPENAT_close_file(                            /* 关闭文件接口 */
                            INT32 iFd               /* 文件句柄，open_file 或 create_file 返回的有效参数 */
                       );



INT32 OPENAT_read_file(                             /* 读取文件接口 */
                            INT32 iFd,              /* 文件句柄，open_file 或 create_file 返回的有效参数 */
                            UINT8 *pBuf,            /* 数据保存指针 */
                            UINT32 iLen             /* buf长度 */
                      );



INT32 OPENAT_write_file(                            /* 写入文件接口*/
                            INT32 iFd,              /* 文件句柄，open_file 或 create_file 返回的有效参数 */
                            UINT8 *pBuf,            /* 需要写入的数据指针 */
                            UINT32 iLen             /* 数据长度 */
                       );



INT32 OPENAT_flush_file(                            /* 立即写入flash*/
                            INT32 iFd               /* 文件句柄，open_file 或 create_file 返回的有效参数 */
                       );    



INT32 OPENAT_seek_file(                             /* 文件定位接口 */
                            INT32 iFd,              /* 文件句柄，open_file 或 create_file 返回的有效参数 */
                            INT32 iOffset,          /* 偏移量 */
                            UINT8 iOrigin           /* 偏移起始位置 */
                      );

INT32 OPENAT_tell_file(                             /* 文件定位接口 */
                            INT32 iFd              /* 文件句柄，open_file 或 create_file 返回的有效参数 */
                      );

INT32 OPENAT_rename_file(char* name, char* new);

INT32 OPENAT_create_file(                           /* 创建文件接口 */
                            char* pszFileNameUniLe,/* 文件全路径名称 unicode little endian*/
                            UINT32 iAttr            /* 文件属性，暂时不支持，请填入0 */
                        );
UINT32 OPENAT_get_file_size(char* pszFileNameUniLe);
UINT32 OPENAT_get_file_size_h(int handle);


INT32 OPENAT_delete_file(                           /* 删除文件接口 */
                            char* pszFileNameUniLe/* 文件全路径名称 unicode little endian*/
                        );



INT32 OPENAT_change_dir(                            /* 切换当前工作目录接口 */
                            char* pszDirNameUniLe  /* 目录路径 unicode little endian */
                       );



INT32 OPENAT_make_dir(                              /* 创建目录接口 */
                            char* pszDirNameUniLe, /* 目录路径 unicode little endian */
                            UINT32 iMode            /* 目录属性，详细请参见 E_AMOPENAT_FILE_ATTR */
                     );



INT32 OPENAT_remove_dir(                            /* 删除目录接口 *//* 该目录必须为空，接口才能返回成功 */
                            char* pszDirNameUniLe  /* 目录路径 unicode little endian */
                       );



INT32 OPENAT_remove_dir_rec(                        /* 递归删除目录接口 *//* 该目录下所有文件、目录都会被删除 */
                            char* pszDirNameUniLe  /* 目录路径 unicode little endian */
                           );
                           

INT32 OPENAT_remove_file_rec(                        /* 递归删除文件接口 *//* 该目录下所有文件都会被删除 */
                            char* pszDirNameUniLe  /* 目录路径 unicode little endian */
                           );                          



INT32 OPENAT_get_current_dir(                       /* 获取当前目录接口 */
                            char* pCurDirUniLe,    /* 存储目录信息 unicode little endian */
                            UINT32 uUnicodeSize     /* 存储目录信息空间大小 */
                            );



INT32 OPENAT_find_first_file(                       /* 查找文件接口 */
                            char* pszFileNameUniLe,/* 目录路径或文件全路径 unicode little endian */
/*-\BUG WM-719\maliang\2013.3.21\文件系统接口和播放音频文件接口的文件名改为unicode little ending类型*/
                            PAMOPENAT_FS_FIND_DATA  pFindData /* 查找结果数据 */
                            );




INT32 OPENAT_find_next_file(                        /* 继续查找文件接口 */
                            INT32 iFd,              /* 查找文件句柄，为 find_first_file 接口返回参数 */
                            PAMOPENAT_FS_FIND_DATA  pFindData /* 查找结果数据 */
                           );




INT32 OPENAT_find_close(                            /* 查找结束接口 */
                            INT32 iFd               /* 查找文件句柄，为 find_first_file 接口返回参数 */
                       );

INT32 OPENAT_ftell(                             /* 文件定位接口 */
                            INT32 iFd             /* 文件句柄，open_file 或 create_file 返回的有效参数 */
                      );

/*+\NewReq WM-743\maliang\2013.3.28\[OpenAt]增加接口获取文件系统信息*/
INT32 OPENAT_get_fs_info(                            /* 获取文件系统信息接口 */
                            E_AMOPENAT_FILE_DEVICE_NAME       devName,            /*获取哪块device name的信息*/
                            T_AMOPENAT_FILE_INFO               *fileInfo,                   /*文件系统的信息*/
                            INT32 isSD,                  /*是否获取SD 卡信息*/
							INT32 type
                       );


/*-\NewReq WM-743\maliang\2013.3.28\[OpenAt]增加接口获取文件系统信息*/
    
    /*+\NewReq\Jack.li\2013.1.17\增加T卡接口*/
INT32 OPENAT_init_tflash(                            /* 初始化T卡接口 */
                            PAMOPENAT_TFLASH_INIT_PARAM pTlashInitParam/* T卡初始化参数 */
                       );



    /*-\NewReq\Jack.li\2013.1.17\增加T卡接口*/

E_AMOPENAT_MEMD_ERR OPENAT_flash_erase(              /*flash擦写 128K对齐*/
                            UINT32 startAddr,
                            UINT32 endAddr
                       );


    
E_AMOPENAT_MEMD_ERR OPENAT_flash_write(              /*写flash*/
                            UINT32 startAddr,
                            UINT32 size,
                            UINT32* writenSize,
                            CONST UINT8* buf
                       );



E_AMOPENAT_MEMD_ERR OPENAT_flash_read(               /*读flash*/
                            UINT32 startAddr,
                            UINT32 size,
                            UINT32* readSize,
                            UINT8* buf
                       );
                       
UINT32 OPENAT_flash_page(void);

E_OPENAT_OTA_RESULT OPENAT_fota_init(void);
E_OPENAT_OTA_RESULT OPENAT_fota_download(const char* data, UINT32 len, UINT32 total);
E_OPENAT_OTA_RESULT OPENAT_fota_done(void);
    
    /*******************************************
    **                 NV                     **
    *******************************************/    
    /*因为下面的接口会直接操作flash，会引起系统阻塞，不要在中断或者要求比较高的TASK中运行*/    
INT32 OPENAT_nv_init(                                /*NV 初始化接口*/
                      UINT32 addr1,                  /*NV 存放地址1 4KByte地址对齐 大小4KByte*/
                      UINT32 addr2                   /*NV 存放地址2 4KByte地址对齐 大小4KByte*/
                    );


INT32 OPENAT_nv_add(                                 /*增加一个NV存储区域*/
                      UINT32 nv_id,                  /*NV ID 目前只支持0-255*/
                      UINT32 nv_size                 /*NV 区域大小,单位Byte,最大512Byte*/
                    );


INT32 OPENAT_nv_delete(                              /*删除NV*/
                      UINT32 nv_id
                      );                 


INT32 OPENAT_nv_read(                                /*读取NV内容*/
                     UINT32 nv_id,                   /*NV ID 目前只支持0-255*/
                     UINT8* buf,                     /*buf*/
                     UINT32 bufSize,                 /*buf的大小*/
                     UINT32* readSize                /*实际读取长度*/
                    );

    
INT32 OPENAT_nv_write(                               /*写入NV内容*/
                      UINT32 nv_id,                  /*NV ID 目前只支持0-255*/
                      UINT8* buf,                    /*buf*/
                      UINT32 bufSize,                /*buf的大小*/
                      UINT32* writeSize              /*实际写入长度*/
                     );          
    /*******************************************
    **                Hardware                **
    *******************************************/
    /****************************** GPIO ******************************/
BOOL OPENAT_config_gpio(                          
                            E_AMOPENAT_GPIO_PORT port,  /* GPIO编号 */
                            T_AMOPENAT_GPIO_CFG *cfg    /* 输出或输入 */
                       );


    
BOOL OPENAT_set_gpio(                               
                            E_AMOPENAT_GPIO_PORT port,  /* GPIO编号 */
                            UINT8 value                 /* 0 or 1 */
                    );



/*+:\NewReq WM-475\brezen\2012.12.14\修改gpio接口 */				
BOOL OPENAT_read_gpio(                            
                            E_AMOPENAT_GPIO_PORT port,  /* GPIO编号 */
                            UINT8* value                /* 结果 0 or 1 */
                      );
/*-:\NewReq WM-475\brezen\2012.12.14\修改gpio接口 */

/*+\BUG WM-720\rufei\2013.3.21\ 增加gpio的close接口*/
BOOL OPENAT_close_gpio(                            
                            E_AMOPENAT_GPIO_PORT port/* GPIO编号 */
                      );
/*-\BUG WM-720\rufei\2013.3.21\ 增加gpio的close接口*/



/****************************** PMD ******************************/
BOOL OPENAT_init_pmd(     
                            E_AMOPENAT_PM_CHR_MODE chrMode,     /* 充电方式 */
/*+\NEW WM-746\rufei\2013.3.30\增加芯片IC充电*/
                            T_AMOPENAT_PMD_CFG*    cfg,         /*充电配置*/
/*-\NEW WM-746\rufei\2013.3.30\增加芯片IC充电*/
                            PPM_MESSAGE            pPmMessage   /* 消息回调函数 */
                    );



VOID OPENAT_get_batteryStatus(
                            T_AMOPENAT_BAT_STATUS* batStatus    /* 电池状态 OUT */
                             );



VOID OPENAT_get_chargerStatus(
                            T_AMOPENAT_CHARGER_STATUS* chrStatus/* 充电器状态 OUT */
                             );



/*+\NEW\RUFEI\2014.2.13\增加OPENAT查询充电器HW状态接口*/
E_AMOPENAT_CHR_HW_STATUS OPENAT_get_chargerHwStatus(
                            VOID
                            );


/*-\NEW\RUFEI\2014.2.13\增加OPENAT查询充电器HW状态接口*/
/*+\TASK\wangyuan\2020.06.28\task_255:支持中云信安, 兼容2g CSDK的接口添加*/
int OPENAT_get_chg_param(BOOL *battStatus, u16 *battVolt, u8 *battLevel, BOOL *chargerStatus, u8 *chargeState);
/*-\TASK\wangyuan\2020.06.28\task_255:支持中云信安, 兼容2g CSDK的接口添加*/
BOOL OPENAT_poweron_system(                                     /* 正常开机 */  
                            E_AMOPENAT_STARTUP_MODE simStartUpMode,/* 开启SIM卡方式 */
                            E_AMOPENAT_STARTUP_MODE nwStartupMode/* 开启协议栈方式 */
                          );



VOID OPENAT_poweroff_system(                                    /* 正常关机，包括关闭协议栈和供电 */        
                            VOID
                           );



BOOL OPENAT_poweron_ldo(                                        /* 打开LDO */
                            E_AMOPENAT_PM_LDO    ldo,
                            UINT8                level          /*0-7 0:关闭 1~7电压等级*/
                       );



BOOL OPENAT_gpio_disable_pull(                            /* GPIO配置接口 */
                            E_AMOPENAT_GPIO_PORT port  /* GPIO编号 */
        );

VOID OPENAT_enter_deepsleep(VOID);                                   /* 进入睡眠 */
                      


VOID OPENAT_exit_deepsleep(VOID);                                     /* 退出睡眠 */

void OPENAT_deepSleepControl(E_AMOPENAT_PMD_M m, BOOL sleep, UINT32 timeout);



/*+NEW OPEANT-104\RUFEI\2014.6.17\ 增加获取开机原因值接口*/
 E_AMOPENAT_POWERON_REASON OPENAT_get_poweronCause (VOID);             /*获取开机原因值*/
/*-NEW OPEANT-104\RUFEI\2014.6.17\ 增加获取开机原因值接口*/


    /****************************** UART ******************************/
BOOL OPENAT_config_uart(
                            E_AMOPENAT_UART_PORT port,          /* UART 编号 */
                            T_AMOPENAT_UART_PARAM *cfg          /* 初始化参数 */
                       );



/*+\NEW\liweiqiang\2013.4.20\增加关闭uart接口*/
BOOL OPENAT_close_uart(
                            E_AMOPENAT_UART_PORT port           /* UART 编号 */
                       );
/*-\NEW\liweiqiang\2013.4.20\增加关闭uart接口*/




UINT32 OPENAT_read_uart(                                        /* 实际读取长度 */
                            E_AMOPENAT_UART_PORT port,          /* UART 编号 */
                            UINT8* buf,                         /* 存储数据地址 */
                            UINT32 bufLen,                      /* 存储空间长度 */
                            UINT32 timeoutMs                    /* 读取超时 ms */
                       );



UINT32 OPENAT_write_uart(                                       /* 实际写入长度 */
                            E_AMOPENAT_UART_PORT port,          /* UART 编号 */
                            UINT8* buf,                         /* 写入数据地址 */
                            UINT32 bufLen                       /* 写入数据长度 */
                        );

UINT32 OPENAT_write_uart_sync(E_AMOPENAT_UART_PORT port,          /* UART 编号 */
                           UINT8* buf,                         /* 写入数据地址 */
                           UINT32 bufLen                       /* 写入数据长度 */
                           );


/*+\NEW\liweiqiang\2014.4.12\增加串口接收中断使能接口 */
BOOL OPENAT_uart_enable_rx_int(
                            E_AMOPENAT_UART_PORT port,          /* UART 编号 */
                            BOOL enable                         /* 是否使能 */
                                );
/*-\NEW\liweiqiang\2014.4.12\增加串口接收中断使能接口 */




/*+\NEW\liweiqiang\2013.12.25\添加host uart发送数据功能 */
    /****************************** HOST ******************************/
BOOL OPENAT_host_init(PHOST_MESSAGE hostCallback);



BOOL OPENAT_host_send_data(uint8 *data, uint32 len);
/*-\NEW\liweiqiang\2013.12.25\添加host uart发送数据功能 */



    /******************************* SPI ******************************/
/*+\NEW\zhuwangbin\2020.3.7\添加openat spi接口*/
BOOL OPENAT_OpenSPI( E_AMOPENAT_SPI_PORT port, T_AMOPENAT_SPI_PARAM *cfg);
UINT32 OPENAT_ReadSPI(E_AMOPENAT_SPI_PORT port, CONST UINT8 * buf, UINT32 bufLen);
UINT32 OPENAT_WriteSPI(E_AMOPENAT_SPI_PORT port, CONST UINT8 * buf, UINT32 bufLen, BOOLEAN type);
UINT32 OPENAT_RwSPI(E_AMOPENAT_SPI_PORT port, CONST UINT8* txBuf, CONST UINT8* rxBuf,UINT32 bufLen);
BOOL OPENAT_CloseSPI( E_AMOPENAT_SPI_PORT port);
/*-\NEW\zhuwangbin\2020.3.7\添加openat spi接口*/







/******************************* I2C ******************************/
BOOL OPENAT_open_i2c(
                            E_AMOPENAT_I2C_PORT  port,          /* I2C 编号 */
                            T_AMOPENAT_I2C_PARAM *param         /* 初始化参数 */
                      );




BOOL OPENAT_close_i2c(
                            E_AMOPENAT_I2C_PORT  port           /* I2C 编号 */
                      );



UINT32 OPENAT_write_i2c(                                        /* 实际写入长度 */
                            E_AMOPENAT_I2C_PORT port,          /* I2C 编号 */
                            UINT8 salveAddr,
                            CONST UINT8 *pRegAddr,              /* I2C外设寄存器地址 */
                            CONST UINT8* buf,                   /* 写入数据地址 */
                            UINT32 bufLen                       /* 写入数据长度 */
                       );




UINT32 OPENAT_read_i2c(                                         /* 实际读取长度 */
                            E_AMOPENAT_I2C_PORT port,          /* I2C 编号 */
                            UINT8 slaveAddr, 
                            CONST UINT8 *pRegAddr,              /* I2C外设寄存器地址 */
                            UINT8* buf,                         /* 存储数据地址 */
                            UINT32 bufLen                       /* 存储空间长度 */
                      );



BOOL  OPENAT_open_bt(
                            T_AMOPENAT_BT_PARAM* param
                     );



BOOL  OPENAT_close_bt(VOID);
                           



BOOL  OPENAT_poweron_bt(VOID);

  
BOOL  OPENAT_poweroff_bt(VOID);

BOOL  OPENAT_send_cmd_bt
                      (
                            E_AMOPENAT_BT_CMD cmd, 
                            U_AMOPENAT_BT_CMD_PARAM* param
                      );    

BOOL  OPENAT_build_rsp_bt
                      (
                            E_AMOPENAT_BT_RSP rsp,
                            U_AMOPENAT_BT_RSP_PARAM* param
                      );   

/*本端作为DevA设备，主动发起连接，连接结果OPENAT_BT_SPP_CONNECT_CNF
如果作为DevB设备，即对端主动发起连接，那就不需要调用这个接口，
对端连接后会收到OPENAT_BT_SPP_CONNECT_IND消息*/
BOOL  OPENAT_connect_spp                              
                      (
                            T_AMOPENAT_BT_ADDR* addr,
                            T_AMOPENAT_UART_PARAM* portParam    /*暂时不支持,可以写NULL，默认配置为9600,8(data),1(stop),none(parity)*/
                      );

BOOL  OPENAT_disconnect_spp                                    /*断开连接，结果 OPENAT_BT_SPP_DISCONNECT_CNF*/
                      (
                            UINT8   port                        /*端口号，会在OPENAT_BT_SPP_CONNECT_IND/OPENAT_BT_SPP_CONNECT_CNF中上报*/
                      ); 

INT32  OPENAT_write_spp                                         /*发送结果会在回调函数里的OPENAT_BT_SPP_SEND_DATA_CNF事件中上报*/
                                                                /*返回值为实际执行写入的长度，如果为0表示根本没有数据被发送，也没有
                                                                  OPENAT_BT_SPP_SEND_DATA_CNF事件上报*/
                      (
                            UINT8   port,                       /*端口号，会在OPENAT_BT_SPP_CONNECT_IND/OPENAT_BT_SPP_CONNECT_CNF中上报*/
                            UINT8*  buf,                        /*不能传输"rls开头的字符串，否则会认为是设置RFCOMM的状态，例如rls0*/
                            UINT32  bufLen                      /*一次最多传输T_AMOPENAT_BT_SPP_CONN_IND.maxFrameSize大小字节的数据*/
                      );


INT32  OPENAT_read_spp                                         /*回调函数中收到OPENAT_BT_SPP_DATA_IND事件后，调用该接口读取*/
                                                                /*返回值为实际读取长度*/
                      (
                            UINT8   port,                       /*端口号，会在OPENAT_BT_SPP_CONNECT_IND/OPENAT_BT_SPP_CONNECT_CNF中上报*/
                            UINT8*  buf,
                            UINT32  bufLen
                      );   


/****************************** AUDIO ******************************/
BOOL OPENAT_open_tch(VOID);                                       /* 打开语音，在通话开始时调用 */
                           


BOOL OPENAT_close_tch(VOID);                                         /* 关闭语音，通话结束时调用 */

                            
BOOL OPENAT_play_tone(                                          /* 播放TONE音接口 */
                            E_AMOPENAT_TONE_TYPE toneType,      /* TONE音类型 */
                            UINT16 duration,                    /* 播放时长 */
                            E_AMOPENAT_SPEAKER_GAIN volume      /* 播放音量 */
                     );


BOOL OPENAT_stop_tone(VOID);                                          /* 停止播放TONE音接口 */


                            
BOOL OPENAT_play_dtmf(                                          /* 播放DTMF音接口 */
                            E_AMOPENAT_DTMF_TYPE dtmfType,      /* DTMF类型 */
                            UINT16 duration,                    /* 播放时长 */
                            E_AMOPENAT_SPEAKER_GAIN volume      /* 播放音量 */
                     );


BOOL OPENAT_stop_dtmf(VOID);                                          /* 停止播放DTMF音接口 */


int OPENAT_streamplay(E_AMOPENAT_AUD_FORMAT playformat,AUD_PLAY_CALLBACK_T cb,char* data,int len);

                            
/*+\NewReq WM-584\maliang\2013.2.21\[OpenAt]支持T卡播放MP3*/
BOOL OPENAT_play_music(T_AMOPENAT_PLAY_PARAM*  playParam);
/*-\NewReq WM-584\maliang\2013.2.21\[OpenAt]支持T卡播放MP3*/


BOOL OPENAT_stop_music(VOID);                                         /* 停止音频播放接口 */


                            
BOOL OPENAT_pause_music(VOID);                                        /* 暂停音频播放接口 */


                            
BOOL OPENAT_resume_music(VOID);                                      /* 停止音频播放接口 */

                           
/*+\NewReq WM-710\maliang\2013.3.18\ [OpenAt]增加接口设置MP3播放的音效*/
BOOL OPENAT_set_eq(                                       /* 设置MP3音效*/
                            E_AMOPENAT_AUDIO_SET_EQ setEQ
                          );
/*-\NewReq WM-710\maliang\2013.3.18\ [OpenAt]增加接口设置MP3播放的音效*/

BOOL OPENAT_open_mic(VOID);                                           /* 开启MIC接口 */
                            


BOOL OPENAT_close_mic(VOID);                                          /* 关闭MIC接口 */

                           
BOOL OPENAT_mute_mic(VOID);                                           /* MIC静音接口 */


BOOL OPENAT_unmute_mic(VOID);                                         /* 解除MIC静音接口 */

                            
BOOL OPENAT_set_mic_gain(                                       /* 设置MIC增益接口 */
                            UINT16 micGain                      /* 设置MIC的增益，最大为20 */
                        );



int OPENAT_audio_record( 									  /* 录音接口 */
										E_AMOPENAT_RECORD_PARAM* param,
										AUD_RECORD_CALLBACK_T cb);



int OPENAT_audio_stop_record(VOID);

BOOL OPENAT_open_speaker(VOID);                                       /* 打开扬声器接口 */


BOOL OPENAT_close_speaker(VOID);                                      /* 关闭扬声器接口 */


BOOL OPENAT_mute_speaker(VOID);                                       /* 扬声器静音接口 */


BOOL OPENAT_unmute_speaker(VOID);                                     /* 解除扬声器静音接口 */


                           
BOOL OPENAT_set_speaker_gain(                                   /* 设置扬声器的增益 */
                            E_AMOPENAT_SPEAKER_GAIN speakerGain /* 设置扬声器的增益 */
                            );



/*+\bug\wj\2020.5.6\增加通话中调节音量接口*/
BOOL OPENAT_set_sph_vol(								   
						UINT32 vol);
/*-\bug\wj\2020.5.6\增加通话中调节音量接口*/
/*+\BUG\wangyuan\2020.08.10\BUG_2801: 思特CSDK 通过iot_audio_set_speaker_vol()接口设置通过音量无效 AT+CLVL可以修改通话音量*/
UINT32 OPENAT_get_sph_vol(void);
/*-\BUG\wangyuan\2020.08.10\BUG_2801: 思特CSDK 通过iot_audio_set_speaker_vol()接口设置通过音量无效 AT+CLVL可以修改通话音量*/

E_AMOPENAT_SPEAKER_GAIN OPENAT_get_speaker_gain(VOID);                /* 获取扬声器的增益接口 */



BOOL OPENAT_set_channel(                                        /* 设置音频通道接口 */
                            E_AMOPENAT_AUDIO_CHANNEL channel    /* 通道 */
                       );

/*+\BUG\wangyuan\2020.06.08\BUG_2163:CSDK提供audio音频播放接口*/
BOOL OPENAT_set_music_volume(UINT32 vol);		/* 设置音频音量接口 */

UINT32 OPENAT_get_music_volume(void);		/* 获取音频音量接口 */

void OPENAT_delete_record(VOID);
/*-\BUG\wangyuan\2020.06.08\BUG_2163:CSDK提供audio音频播放接口*/

VOID OPENAT_set_channel_with_same_mic(                          /* 设置共用同一个MIC音频通道接口 */
                        E_AMOPENAT_AUDIO_CHANNEL channel_1,     /* 通道 1 */
                        E_AMOPENAT_AUDIO_CHANNEL channel_2      /* 通道 2 */
                   );



/*+\BUG WM-882\rufei\2013.7.18\完善通道设置*/
BOOL set_hw_channel(
                          E_AMOPENAT_AUDIO_CHANNEL hfChanne,    /*手柄通道*/
                          E_AMOPENAT_AUDIO_CHANNEL erChanne,    /*耳机通道*/
                          E_AMOPENAT_AUDIO_CHANNEL ldChanne    /*免提通道*/
                         );
/*-\BUG WM-882\rufei\2013.7.18\完善通道设置*/

/*+\NEW\zhuwangbin\2020.8.11\添加耳机插拔配置*/
int OPENAT_headPlug(E_OPENAT_AUD_HEADSET_TYPE type);
/*-\NEW\zhuwangbin\2020.8.11\添加耳机插拔配置*/

E_AMOPENAT_AUDIO_CHANNEL OPENAT_get_current_channel(VOID);



/*+\NewReq WM-711\maliang\2013.3.18\[OpenAt]增加接口打开或关闭音频回环测试*/
/*+\New\lijiaodi\2014.7.30\修改音频回环测试接口，增加IsSpkLevelAdjust跟SpkLevel两参数
                           如果IsSpkLevelAdjust为FALSE,spkLevel为默认的值，否则为SpkLevel指定的值*/
BOOL  OPENAT_audio_loopback(BOOL  start,                    /*开始或停止回环测试*/
                                        E_AMOPENAT_AUDIO_LOOPBACK_TYPE type,   /*回环测试的类型*/
                                        BOOL IsSpkLevelAdjust,   /*SPK声音大小是否可指定*/
                                        UINT8 SpkLevel);   /*SPK指定的声音大小SpkLevel取值范围AUD_SPK_MUTE--AUD_SPK_VOL_7*/
/*-\New\lijiaodi\2014.7.30\修改音频回环测试接口，增加IsSpkLevelAdjust跟SpkLevel两参数
                           如果IsSpkLevelAdjust为FALSE,spkLevel为默认的值，否则为SpkLevel指定的值*/
/*-\NewReq WM-711\maliang\2013.3.18\[OpenAt]增加接口打开或关闭音频回环测试*/



BOOL  OPENAT_audio_inbandinfo(PINBANDINFO_CALLBACK callback); 

int OPENAT_WritePlayData(char* data, unsigned size);

    
/****************************** ADC ******************************/
/*+\BUG\wangyuan\2020.06.30\BUG_2424:CSDK-8910 ADC 的API 编译错误*/
BOOL OPENAT_InitADC(
				    E_AMOPENAT_ADC_CHANNEL channel  /* ADC编号 */,
				    E_AMOPENAT_ADC_CFG_MODE mode
				);


BOOL OPENAT_ReadADC(
				    E_AMOPENAT_ADC_CHANNEL channel,  /* ADC编号 */
				    kal_uint32*               adcValue,   /* adc值 */
				    kal_uint32*               voltage    /* 电压值*/
				);
/*-\BUG\wangyuan\2020.06.30\BUG_2424:CSDK-8910 ADC 的API 编译错误*/


/****************************** LCD ******************************/
/* MONO */                                                  /* 黑白屏*/			
BOOL OPENAT_init_mono_lcd(                                      /* 屏幕初始化接口 */
                            T_AMOPENAT_MONO_LCD_PARAM*  monoLcdParamP
                    );

/*+\bug2958\czm\2020.9.1\disp.close() 之后再执行disp.init 无提示直接重启*/
BOOL OPENAT_close_mono_lcd(void);/* Lcd关闭接口 */
/*-\bug2958\czm\2020.9.1\disp.close() 之后再执行disp.init 无提示直接重启*/

VOID OPENAT_send_mono_lcd_command(                              /* 发送命令接口 */
                            UINT8 cmd                           /* 命令 */
                                 );


VOID OPENAT_send_mono_lcd_data(                                 /* 发送数据接口 */
                            UINT8 data                          /* 数据 */
                              );



VOID OPENAT_update_mono_lcd_screen(                             /* 更新屏幕接口 */
                            T_AMOPENAT_LCD_RECT_T* rect         /* 需要刷新的区域 */
                                  );


VOID OPENAT_clear_mono_lcd(                                     /* 清屏，一般用于实际LCD RAM比显示区域大的情况 */
                            UINT16 realHeight,                  /* 实际LCD RAM 高度 */
                            UINT16 realWidth                    /* 实际LCD RAM 宽度，必须是4的倍数 */
                          );


/* COLOR */                                                 /* 彩色屏 */
BOOL OPENAT_init_color_lcd(                                     /* 屏幕初始化接口 */
                            T_AMOPENAT_COLOR_LCD_PARAM *param   /* 彩屏初始化参数 */
                          );

/*+\bug2958\czm\2020.9.1\disp.close() 之后再执行disp.init 无提示直接重启*/
BOOL OPENAT_close_color_lcd(void);/* Lcd关闭接口 */
/*-\bug2958\czm\2020.9.1\disp.close() 之后再执行disp.init 无提示直接重启*/

BOOL OPENAT_spiconfig_color_lcd(                     /* 彩屏SPI配置 */
                        void                    
                        );

VOID OPENAT_send_color_lcd_command(                             /* 发送命令接口 */
                            UINT8 cmd                           /* 命令 */
                                  );


VOID OPENAT_send_color_lcd_data(                                /* 发送数据接口 */
                            UINT8 data                          /* 数据 */
                               );


VOID OPENAT_update_color_lcd_screen(                            /* 更新屏幕接口 */
                            T_AMOPENAT_LCD_RECT_T* rect,        /* 需要刷新的区域 */
                            UINT16 *pDisplayBuffer              /* 刷新的缓冲区 */
                                   );


void OPENAT_layer_flatten(OPENAT_LAYER_INFO* layer1,
                                   OPENAT_LAYER_INFO* layer2,
                                   OPENAT_LAYER_INFO* layer3) ;



/*+\NEW\Jack.li\2013.2.9\增加摄像头视频录制接口 */
BOOL OPENAT_camera_videorecord_start(                           /* 开始录制视频 */
                    INT32 iFd                               /* 录像文件句柄 */
                    );


BOOL OPENAT_camera_videorecord_pause(                           /* 暂停录制视频 */
                    void                    
                    );


BOOL OPENAT_camera_videorecord_resume(                          /* 恢复录制视频 */
                        void                    
                        );


BOOL OPENAT_camera_videorecord_stop(                            /* 停止录制视频 */
                        void                    
                        );


/*-\NEW\Jack.li\2013.2.9\增加摄像头视频录制接口 */

/*-\NEW\Jack.li\2013.1.28\增加摄像头驱动*/

/*+\NEW\Jack.li\2013.2.10\增加视频播放接口 */
BOOL OPENAT_video_open(                                         /* 打开视频环境 */
                        T_AMOPENAT_VIDEO_PARAM *param           /* 视频参数 */
                        );


BOOL OPENAT_video_close(                                        /* 关闭视频环境 */
                        void
                        );


BOOL OPENAT_video_get_info(                                     /* 获取视频信息 */
                        T_AMOPENAT_VIDEO_INFO *pInfo            /* 视频信息 */
                        );


BOOL OPENAT_video_play(                                         /* 播放 */
                        void
                        );


BOOL OPENAT_video_pause(                                        /* 暂停 */
                        void
                        );


BOOL OPENAT_video_resume(                                       /* 恢复 */
                        void
                        );


BOOL OPENAT_video_stop(                                         /* 停止 */
                        void
                        );
    /*-\NEW\Jack.li\2013.2.10\增加视频播放接口 */

#if 0 
void OPENAT_ttsply_Error_Callback(S32 ttsResult);
void OPENAT_ttsply_State_Callback(int ttsplyState);
BOOL OPENAT_ttsply_initEngine(AMOPENAT_TTSPLY_PARAM *param);
BOOL OPENAT_ttsply_setParam(U16 playParam, S16 value);
S16 OPENAT_ttsply_getParam(U16 playParam);
BOOL OPENAT_ttsply_play(AMOPENAT_TTSPLY *param);
BOOL OPENAT_ttsply_pause(void);
BOOL OPENAT_ttsply_stop(void);
#endif //__AM_LUA_TTSPLY_SUPPORT__


void OPENAT_AW9523B_display(
                                                                u8 num1, 
                                                                u8 num2, 
                                                                u8 num3
                                                                );



void OPENAT_AW9523B_set_gpio(
                                                                    u8 pin_num, 
                                                                    u8 value
                                                                    );

void OPENAT_AW9523B_init(void);


BOOL OPENAT_register_msg_proc(
                                                                    int msg_id, 
                                                                    openat_msg_proc msg_proc
                                                                    );



void OPENAT_SLI3108_init(openat_msg_proc msg_proc);


typedef enum SLI3108_STATUS_TAG
{
    SLI3108_STATUS_INVALID,
    SLI3108_STATUS_LOW,                          /*超出最低阀值，表示未佩戴*/
    SLI3108_STATUS_HIGH,                         /*超出最高阀值，表示已佩戴*/
}SLI3108_STATUS; 


    /* NULL */
    /****************************** KEYPAD ******************************/
BOOL OPENAT_init_keypad(                                        /* 键盘初始化接口 */
                            T_AMOPENAT_KEYPAD_CONFIG *pConfig   /* 键盘配置参数 */
                       );
    

    /****************************** TOUCHSCREEN ******************************/
BOOL OPENAT_init_touchScreen(                                   /* 触摸屏初始化接口 */
                            PTOUCHSCREEN_MESSAGE pTouchScreenMessage /* 触屏消息回调函数 */
                            );
    


VOID OPENAT_TouchScreen_Sleep_In(VOID);



VOID OPENAT_TouchScreen_Sleep_Out(VOID);

    
/******************************** PSAM ***********************************/
/* 注意:::PSAM卡接口在操作设备时会导致调用者被挂起，直到设备有响应或者2s+超时 */
E_AMOPENAT_PSAM_OPER_RESULT OPENAT_open_psam(                   /* 打开psam */
                            E_AMOPENAT_PSAM_ID id               /* 硬件SIM卡接口 */
                                            );


VOID OPENAT_close_psam(                                         /* 关闭psam */
                            E_AMOPENAT_PSAM_ID id               /* 硬件SIM卡接口 */
                      );
	/*  rw_psam接口使用说明
		psam 指令包
		-------------------------
	    代码  |	值
		-------------------------
		CLA     80
		INS  	82
		P1	    00
		P2	    00或密钥版本（KID）
		Lc	    08
		DATA	加密数据
		-------------------------

	针对需要DATA参数的PSAM指令，需要分步发送，
	  第一步 发送DATA之前的命令部分，同时设置rxLen=1，stopClock = FALSE
	  	返回值可能为Ins 、 ~Ins 
	  		如果返回是Ins，进入第三步
	  		如果返回是~Ins，则进入第二步
	  第二步 如果DATA中剩余的数据大于1个字节，发送一个字节的DATA剩余数据，同时设置rxLen=1，stopClock = FALSE，
	        否则，直接进入第三步
	     返回值的处理和第一步返回值处理一致
		   
	  第三步发送DATA中的剩余数据，同时设置stopClock=TRUE,rxLen根据需要设置
	*/					  
E_AMOPENAT_PSAM_OPER_RESULT OPENAT_rw_psam(                     /* 传输数据 */
                            E_AMOPENAT_PSAM_ID id,              /* 硬件SIM卡接口 */
                            CONST UINT8*  txBuf,                /* 写缓存 */
                            UINT16        txLen,                /* 写缓存长度 */
                            UINT8*        rxBuf,                /* 读缓存 */
                            UINT16        rxLen,                /* 读缓存长度 */
                            BOOL          stopClock             /* 命令分开发送设置为FALSE, 命令一次发送或者为分布发送的最后一步设置为TRUE*/  
                                          );


    
E_AMOPENAT_PSAM_OPER_RESULT OPENAT_reset_psam(                  /* 复位PSAM */
                            E_AMOPENAT_PSAM_ID id,              /* 硬件SIM卡接口 */
                            UINT8*      atrBuf,                 /* ATR 缓存 */
                            UINT16      atrBufLen,              /* ATR 缓存长度 */
                            E_AMOPENAT_PSAM_VOLT_CLASS volt     /* 工作电压 */
                                             );



E_AMOPENAT_PSAM_OPER_RESULT OPENAT_setfd_psam(                  /* 设置F值和D值，默认F=372 D=1 */
                            E_AMOPENAT_PSAM_ID id,              /* 硬件SIM卡接口 */
                            UINT16      f,                      /* F值 */
                            UINT8       d                       /* D值 */
                                             );

    /******************************** PWM ***********************************/
/*+\NEW\RUFEI\2015.9.8\Add pwm function */
BOOL OPENAT_OpenPwm(E_AMOPENAT_PWM_PORT port);

BOOL OPENAT_SetPwm(T_AMOPENAT_PWM_CFG *cfg);

BOOL OPENAT_ClosePwm(E_AMOPENAT_PWM_PORT port);
/*-\NEW\RUFEI\2015.9.8\Add pwm function */

    /****************************** FM ******************************/
BOOL OPENAT_open_fm(											/* 打开FM */
                            T_AMOPENAT_FM_PARAM *fmParam        /* 初始化数据 */
                   );


BOOL OPENAT_tune_fm(											/* 调到指定频率 */
                            UINT32 frequency                    /* 频率(KHZ) */
                   );


BOOL OPENAT_seek_fm(											/* 搜索下一个台 */
                            BOOL seekDirection					/* TRUE:频率增加的方向 FALSE::频率减小的方向 */		
                   );


BOOL OPENAT_stopseek_fm(										/* 停止搜索 */
                            void
                       );


BOOL OPENAT_setvol_fm(											/* 设置音效 */
                            E_AMOPENAT_FM_VOL_LEVEL volume, 	/* 设置音量 */
                            BOOL bassBoost, 
                            BOOL forceMono
                     );



BOOL OPENAT_getrssi_fm(											/* 获取FM信号 */
                            UINT32* pRssi
                      );


BOOL OPENAT_close_fm(											/* 关闭FM */
                            void
                    );


/*******************************************
**               AT COMMAND               **
*******************************************/
BOOL OPENAT_init_at(                                            /* 虚拟AT通路初始化接口 */
                            PAT_MESSAGE pAtMessage              /* AT消息回调函数 */
                   );



BOOL OPENAT_send_at_command(                                    /* 发送AT命令接口 */
                            UINT8 *pAtCommand,                  /* AT命令 */
                            UINT16 nLength                      /* AT命令长度 */
                           );



/*+\NEW WM-733\xc\2013.04.19\修改加密卡流程(添加openat存取接口) */
/*******************************************
**               加密卡设置               **
*******************************************/
BOOL OPENAT_set_encinfo(                         /* 设置密钥信息 */
                        UINT8 *encInfo,
                        UINT32 len
              );


BOOL OPENAT_get_encinfo(                         /* 读取密钥信息 */
                        UINT8 *encInfo,
                        UINT32 len
              );



UINT8 OPENAT_get_encresult(                         /* 读取加密校验结果 */
                        void
              );



/*+\NEW WM-733\xc\2013.05.06\修改加密卡流程5(添加获取卡类型的接口) */
UINT8 OPENAT_get_cardtype(                         /* 读取卡类型 0未知  1加密卡  2普通卡  */
                        void
              );
/*-\NEW WM-733\xc\2013.05.06\修改加密卡流程5(添加获取卡类型的接口) */


/*+\NEW WM-733\xc\2013.04.23\修改加密卡流程2(用openat接口代替at设置密钥信息。添加信号量) */
BOOL OPENAT_set_enc_data_ok(                         /* mmi中准备好密钥信息后要用这个发出通知 */
                        void
              );
/*-\NEW WM-733\xc\2013.04.23\修改加密卡流程2(用openat接口代替at设置密钥信息。添加信号量) */
/*+\NEW WM-733\xc\2013.04.19\修改加密卡流程(添加openat存取接口) */



/*+\NEW\xiongjunqun\2014.04.02\调整TTS的代码*/
/* delete TTS改用发送AT 指令的形式 */
/*-\NEW\xiongjunqun\2014.04.02\调整TTS的代码*/
/*+\NEW AMOPENAT-91 \zhangyang\2013.11.19\增加USB HID功能*/
void OPENAT_uhid_open(
        void OPENAT_handler(uint8 *, uint32));



void OPENAT_uhid_close(
        void);


int32 OPENAT_uhid_write(
        uint8 *data_p, 
        uint32 length);
/*-\NEW AMOPENAT-91 \zhangyang\2013.11.19\增加USB HID功能*/


/*+\NEW\RUFEI\2014.8.20\增加gps接口实现*/
    /*******************************************
    **               RDAGPS                      **
    *******************************************/
BOOL OPENAT_Gps_open(
        T_AMOPENAT_RDAGPS_PARAM *cfg);

BOOL OPENAT_Gps_close(
        T_AMOPENAT_RDAGPS_PARAM *cfg);
/*-\NEW\RUFEI\2014.8.20\增加gps接口实现*/
    /*******************************************
    **                 DEBUG                  **
    *******************************************/
VOID OPENAT_print(                                              /* trace log输出接口 */
                            CHAR * fmt, ...
                 );

VOID OPENAT_openat_print(CHAR * fmt, ...);

VOID OPENAT_lua_print(CHAR * fmt, ...);

VOID OPENAT_openat_dump(char* head, char* hex, UINT32 len);


VOID OPENAT_assert(                                             /* 断言接口 */
                            BOOL condition,                     /* 条件 */
                            CHAR *func,                         /* 函数名称 */
                            UINT32 line                         /* 行数 */
                  );



VOID OPENAT_enable_watchdog(BOOL enable);                            /*打开看门狗*/

/*+\NEW\xiongjunqun\2015.06.11\增加factory接口库*/
boolean OPENAT_factory_check_calib(void);
/*-\NEW\xiongjunqun\2015.06.11\增加factory接口库*/


void OPENAT_watchdog_restart(void);
/*+\NEW\brezen\2016.03.03\增加watchdog使能接口*/
BOOL OPENAT_watchdog_enable(BOOL enable, UINT16 count);
/*-\NEW\brezen\2016.03.03\增加watchdog使能接口*/


#ifdef HRD_SENSOR_SUPPORT
/***********************************************/
VOID OPENAT_hrd_sensor_start(void);
VOID OPENAT_hrd_sensor_close(void);
int OPENAT_hrd_sensor_getrate(void);
/***********************************************/
#endif

INT64 OPENAT_disk_free(int drvtype);
INT32 OPENAT_disk_volume(int drvtype);


/*+\BUG WM-656\lifei\2013.03.07\[OpenAT] 修改cust区域检查条件*/
#define OPENAT_CUST_VTBL_DEFUALT_MAGIC 0x87654321
/*-\BUG WM-656\lifei\2013.03.07\[OpenAT] 修改cust区域检查条件*/

typedef enum E_AMOPENAT_CUST_INIT_RESULT_TAG
{
    OPENAT_CUST_INIT_RES_OK,        /* 客户程序初始化成功，可以调用cust_main函数 */
    OPENAT_CUST_INIT_RES_ERROR,     /* 客户程序初始化失败，不会调用cust_main函数 */
    OPENAT_CUST_INIT_RES_MAX
}E_AMOPENAT_CUST_INIT_RESUL;

extern u16 lua_lcd_height;
extern u16 lua_lcd_width;

#define OPENAT_TICKS_TO_MILLSEC(t) ((UINT64)(t)*5)
#define OPENAT_TICKS_TO_SEC(t) ((UINT64)(t)*5/1000)

BOOL OPENAT_set_trace_port(UINT8 port, UINT8 usb_port_diag_output);
UINT8 OPENAT_get_trace_port(void);
/*+\NEW\WJ\2018.10.10\去掉USES_NOR_FLASH宏*/
BOOL OPENAT_is_nor_flash(void);
UINT32 OPENAT_turn_addr(UINT32 addr);
/*-\NEW\WJ\2018.10.10\去掉USES_NOR_FLASH宏*/

/*+\NEW\shenyuanyuan\2019.4.19\开发AT+TRANSDATA命令*/
void OPENAT_rtos_sendok(char *src);
/*-\NEW\shenyuanyuan\2019.4.19\开发AT+TRANSDATA命令*/
/*+\NEW\shenyuanyuan\2019.11.01\开发rtos.set_lua_info接口和AT+LUAINFO？命令*/
void OPENAT_rtos_set_luainfo(char *src);
/*-\NEW\shenyuanyuan\2019.11.01\开发rtos.set_lua_info接口和AT+LUAINFO？命令*/
/*+\NEW\WANGJIAN\2019.4.28\添加开机设置相应模块对应的频段*/
int OPENAT_set_band();
/*-\NEW\WANGJIAN\2019.4.28\添加开机设置相应模块对应的频段*/
/*+\NEW\wangyuan\2020.05.07\BUG_1126:支持wifi定位功能*/
void OPENAT_get_wifiinfo(OPENAT_wifiScanRequest* wifi_info);
/*-\NEW\wangyuan\2020.05.07\BUG_1126:支持wifi定位功能*/
void OPENAT_get_channel_wifiinfo(OPENAT_wifiScanRequest* wifi_info, uint32 channel);

#ifdef __AM_LUA_TTSPLY_SUPPORT__
BOOL OPENAT_tts_init(TTS_PLAY_CB fCb);
BOOL OPENAT_tts_set_param(OPENAT_TTS_PARAM_FLAG flag,u32 value);
BOOL OPENAT_tts_play(char *text,u32 len);
BOOL OPENAT_tts_stop();
#endif
#endif /* AM_OPENAT_H */

/*+\NEW\zhuwangbin\2020.05.14\添加openat speex接口*/
BOOL openat_speexEncoderInit(void);
int  openat_speexEncode(short decoded[], int decoded_size, char *output, int output_size);
BOOL openat_speexEncoderDestroy(void);

BOOL openat_speexDecoderInit(void);
int openat_speexDecoder(char encoded[], int encoded_size, short output[], int output_size);
BOOL openat_speexDecoderDestroy(void);
/*-\NEW\zhuwangbin\2020.05.14\添加openat speex接口*/

/*+\bug2767\zhuwangbin\2020.8.5\添加外部pa设置接口*/
BOOL OPENAT_ExPASet(OPENAT_EXPA_T * exPaCtrl);
/*-\bug2767\zhuwangbin\2020.8.5\添加外部pa设置接口*/

/*+\new\zhuwangbin\2020.6.2\添加音频功放类型设置接口*/
BOOL OPENAT_setpa(OPENAT_SPKPA_TYPE_T type);
OPENAT_SPKPA_TYPE_T OPENAT_getpa(void);
/*-\new\zhuwangbin\2020.6.2\添加音频功放类型设置接口*/
/*+\BUG\wnagyuan\2020.06.10\BUG_1930:Lua需要sd卡默认关闭,需要时由Lua脚本决定开启sd卡功能*/
BOOL OPENAT_fs_mount_sdcard(void);
BOOL OPENAT_fs_umount_sdcard(void);
/*-\BUG\wnagyuan\2020.06.10\BUG_1930:Lua需要sd卡默认关闭,需要时由Lua脚本决定开启sd卡功能*/
/*+\BUG\wangyuan\2020.07.29\BUG_2663:普玄：请参考2G CSDK开发iot_debug_set_fault_mode接口*/
VOID OPENAT_SetFaultMode(E_OPENAT_FAULT_MODE mode);
/*-\BUG\wangyuan\2020.07.29\BUG_2663:普玄：请参考2G CSDK开发iot_debug_set_fault_mode接口*/

