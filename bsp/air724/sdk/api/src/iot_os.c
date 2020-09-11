#include "iot_os.h"
#include "am_openat.h"
#include "am_openat_debug.h"

BOOL g_s_traceflag = FALSE;

/*******************************************
**                 SYSTEM                 **
*******************************************/

/**创建线程
*@note  nPriority值的返回在0-20, 值越大优先级越低
*@param	pTaskEntry:		线程主函数
*@param	pParameter:		作为参数传递给线程主函数
*@param	nStackSize: 	线程栈大小
*@param	nPriority: 		线程优先级，该参数越大，线程优先级越低
*@param nCreationFlags: 线程启动标记， 请参考E_AMOPENAT_OS_CREATION_FLAG
*@param pTaskName: 		线程名称
*@return	HANDLE: 	创建成功返回线程句柄
**/
HANDLE iot_os_create_task(                         
                            PTASK_MAIN pTaskEntry, 
                            PVOID pParameter,     
                            UINT16 nStackSize,      
                            UINT8 nPriority,        
                            UINT16 nCreationFlags, 
                            PCHAR pTaskName         
                          )
{
    HANDLE h = NULL;
    OPENAT_create_task(&h, pTaskEntry, pParameter, NULL, 
                nStackSize, nPriority, nCreationFlags, 10, pTaskName);
    return h;
}
             
/**删除线程
*@param		hTask:		线程句柄
*@return	TURE:		删除线程成功
*			FALSE: 		删除线程失败
**/	
BOOL iot_os_delete_task(                           
                        HANDLE hTask            
                   )
{
    OPENAT_delete_task(hTask);
	return TRUE;
}

/**挂起线程
*@param		hTask:		线程句柄
*@return	TURE: 		挂起线程成功
*			FALSE  : 	挂起线程失败
**/
BOOL iot_os_suspend_task(                      
                            HANDLE hTask          
                        )
{
	return IVTBL(suspend_task)(hTask);
}

/**恢复线程
*@param		hTask:		线程句柄
*@return	TURE: 		恢复线程成功
*			FALSE  : 	恢复线程失败
**/
BOOL iot_os_resume_task(                           
                        HANDLE hTask          
                   )
{
    return IVTBL(resume_task)(hTask);
}

/**获取当前线程
*@return	HANDLE:		返回当前线程句柄
*
**/		
HANDLE iot_os_current_task(                         
                            VOID
                          )
{
    return OPENAT_current_task();
}

/**获取当前线程创建信息
*@param		hTask:		线程句柄
*@param		pTaskInfo:		线程信息存储接口
*@return	TURE: 		成功
*			FALSE  : 	失败
**/
BOOL iot_os_get_task_info(                         
                            HANDLE hTask,         
                            T_AMOPENAT_TASK_INFO *pTaskInfo 
                         )
{
    return IVTBL(get_task_info)(hTask, pTaskInfo);
}




/**获取线程消息
*@note 会阻塞
*@param		hTask:		线程句柄
*@param		ppMessage:	存储消息指针
*@return	TURE: 		成功
*			FALSE  : 	失败
**/
BOOL iot_os_wait_message(                          
                        HANDLE hTask,         
                        PVOID* ppMessage    
                    )
{
    int msgId;
    return OPENAT_wait_message(hTask, &msgId, ppMessage, 0);
}

/**发送线程消息
*@note 添加到消息队列尾部
*@param		hTask:		线程句柄
*@param		pMessage:	存储消息指针
*@return	TURE: 		成功
*			FALSE  : 	失败
**/
BOOL iot_os_send_message(                       
                        HANDLE hTask,         
                        PVOID pMessage         
                    )
{
    return OPENAT_send_message(hTask, 0, pMessage, 0);
}

/**发送高优先级线程消息
*@note      添加到消息队列头部
*@param		hTask:		线程句柄
*@param		pMessage:	存储消息指针
*@return	TURE: 		成功
*			FALSE  : 	失败
**/
BOOL iot_os_send_high_priority_message(          
                        HANDLE hTask,          
                        PVOID pMessage         
                                  )
{
    return IVTBL(SendHighPriorityMessage)(hTask, pMessage);
}

/**检测消息队列中是否有消息
*@param		hTask:		线程句柄
*@return	TURE: 		成功
*			FALSE  : 	失败
**/
BOOL iot_os_available_message(                     
                        HANDLE hTask           
                         )
{
    return IVTBL(available_message)(hTask);
}


/**创建定时器
*@param		pFunc:			定时器到时处理函数
*@param		pParameter:		作为参数传递给定时器到时处理函数
*@return	HANDLE: 		返回定时器句柄
*			
**/	
HANDLE iot_os_create_timer(                        
                        PTIMER_EXPFUNC pFunc,   
                        PVOID pParameter        
                      )
{
    return OPENAT_create_timerTask(pFunc, pParameter);
}

/**启动定时器
*@param		hTimer:				定时器句柄，create_timer接口返回值
*@param		nMillisecondes:		定时器时间
*@return	TURE: 				成功
*			FALSE  : 			失败
**/
BOOL iot_os_start_timer(                         
                        HANDLE hTimer,         
                        UINT32 nMillisecondes   
                   )
{
    return OPENAT_start_timer(hTimer, nMillisecondes);
}

/**停止定时器
*@param		hTimer:				定时器句柄，create_timer接口返回值
*@return	TURE: 				成功
*			FALSE  : 			失败
**/	
BOOL iot_os_stop_timer(                          
                        HANDLE hTimer
                    )
{
    return OPENAT_stop_timer(hTimer);
}

/**删除定时器
*@param		hTimer:				定时器句柄，create_timer接口返回值
*@return	TURE: 				成功
*			FALSE  : 			失败
**/	
BOOL iot_os_delete_timer(                         
                        HANDLE hTimer          
                    )
{
    return OPENAT_delete_timer(hTimer);
}

/**检查定时器是否已经启动
*@param		hTimer:				定时器句柄，create_timer接口返回值
*@return	TURE: 				成功
*			FALSE  : 			失败
**/
BOOL iot_os_available_timer(                      
                        HANDLE hTimer         
                       )
{
    return IVTBL(available_timer)(hTimer);
}

/**获取系统时间
*@param		pDatetime:		存储时间指针
*@return	TURE: 			成功
*			FALSE  : 		失败
**/	
BOOL iot_os_get_system_datetime(                   
                        T_AMOPENAT_SYSTEM_DATETIME* pDatetime
                       )
{
    return OPENAT_get_system_datetime(pDatetime);
}

/**设置系统时间
*@param		pDatetime:		存储时间指针
*@return	TURE: 			成功
*			FALSE  : 		失败
**/	
BOOL iot_os_set_system_datetime(                   
                        T_AMOPENAT_SYSTEM_DATETIME* pDatetime
                       )
{
    return OPENAT_set_system_datetime(pDatetime);
}

/**闹钟初始化接口
*@param		pConfig:		闹钟配置参数
*@return	TURE: 			成功
*			FALSE: 		    失败
**/
BOOL iot_os_init_alarm(                                       
                        T_AMOPENAT_ALARM_CONFIG *pConfig 
                   )
{
    return IVTBL(InitAlarm)(pConfig);
}
				   
/**闹钟设置/删除接口
*@param		pAlarmSet:		闹钟设置参数
*@return	TURE: 			成功
*			FALSE: 		    失败
**/
BOOL iot_os_set_alarm(                                        
                        T_AMOPENAT_ALARM_PARAM *pAlarmSet    
                   )
{
    return IVTBL(SetAlarm)(pAlarmSet);
}

/**进入临界资源区接口，关闭所有中断
*@return	HANDLE:    返回临界资源区句柄，
**/
HANDLE iot_os_enter_critical_section(            
                        VOID
                                )
{
    return OPENAT_enter_critical_section(); 
}
								
/**退出临界资源区接口，开启中断
*@param		hSection:		临界资源区句柄
**/
VOID iot_os_exit_critical_section(                
                        HANDLE hSection       
                             )
{
    OPENAT_exit_critical_section(hSection); 
}

/**创建信号量接口
*@param		nInitCount:		信号量数量
*@return	HANDLE: 	    返回信号量句柄
**/
HANDLE iot_os_create_semaphore(                   
                        UINT32 nInitCount     
                          )
{
    return OPENAT_create_semaphore(nInitCount); 
}

/**删除信号量接口
*@param		hSem:		信号量句柄
*@return	TURE: 		成功
*			FALSE: 		失败
**/
BOOL iot_os_delete_semaphore(                      
                        HANDLE hSem            
                        )
{
    return OPENAT_delete_semaphore(hSem);  
}

/**等待信号量接口
*@param		hSem:		信号量句柄
*@param		nTimeOut:   等待信号量超时时间，if nTimeOut < 5ms, means forever
*@return	TURE: 		成功
*			FALSE: 		失败
**/
BOOL iot_os_wait_semaphore(                  
                        HANDLE hSem,           
                        UINT32 nTimeOut        
                      )
{
    return OPENAT_wait_semaphore(hSem, nTimeOut);
}

/**释放信号量接口
*@param		hSem:		信号量句柄
*@return	TURE: 		成功
*			FALSE: 		失败
**/
BOOL iot_os_release_semaphore(
                        HANDLE hSem           
                         )
{
    return OPENAT_release_semaphore(hSem);
}

/**获取消耗量值
*@param		hSem:		 信号量句柄
*@return	nInitCount:  信号量的个数
**/
UINT32 iot_os_get_semaphore_value (                  
                        HANDLE hSem            
                        )
{
    return IVTBL(get_semaphore_value)(hSem);
}

/**内存申请接口malloc
*@param		nSize:		 申请的内存大小
*@return	PVOID:       内存指针
**/
PVOID iot_os_malloc(                                
                        UINT32 nSize           
               )
{
    return OPENAT_malloc(nSize);
}

/**内存申请接口realloc
*@param		pMemory:	     内存指针，malloc接口返回值
*@param		nSize:	     申请的内存大小
*@return	PVOID:       内存指针
**/
PVOID iot_os_realloc(                            
                        PVOID pMemory,          
                        UINT32 nSize           
                )
{
    return OPENAT_realloc(pMemory, nSize);
}

/**内存释放接口
*@param		pMemory:	     内存指针，malloc接口返回值
**/
VOID iot_os_free(                                  
                        PVOID pMemory          
            )
{
    OPENAT_free(pMemory);
}

/**获取堆空间大小
*@param		total:	     总共大小
*@param   used:        已经使用
**/
VOID iot_os_mem_used(                                  
                        UINT32* total,
                        UINT32* used   
            )
{
    IVTBL(MemoryUsed)(total, used);
} 

/**系统睡眠接口
*@param		nMillisecondes:	     睡眠时间
*@return	TURE: 		成功
*			FALSE: 		失败
**/
BOOL iot_os_sleep(                                 
                        UINT32 nMillisecondes  
             )
{
    return OPENAT_sleep(nMillisecondes);
}
			 
/**获取系统tick接口
*@return	tick_num:   返回系统时间tick值
**/
UINT32 iot_os_get_system_tick(                   
                        VOID
                         )
{
    return OPENAT_get_system_tick();
}

/**获取随机数接口
*@return	rand_num:   返回随机数
**/
UINT32 iot_os_rand(                                
                        VOID
              )
{
    return OPENAT_rand();
}

/**设置随机数种子接口
*@param		seed:	     随机数种子
**/
VOID iot_os_srand(                              
                        UINT32 seed           
             )
{
    IVTBL(srand)(seed);
}

/**关机接口
**/
VOID iot_os_shut_down(                             
                        VOID
                 )
{
    IVTBL(shut_down)();
}

/**重启接口
**/
VOID iot_os_restart(                              
                        VOID
               )
{
    IVTBL(restart)();
}

/**设置trace打印口
*@param		port:		0: uart1
                        1: uart2
                        2: uart3
                        3: usb modem
                        4: usb AP & UART Host口抓log(默认)
*@return	TURE: 			成功
*			FALSE  : 		失败
**/
BOOL iot_os_set_trace_port(UINT8 port)
{
	if((port > OPENAT_TRACE_QTY) || port < 0)
		return FALSE;
	if(4 == port)
	{
		g_s_traceflag = FALSE;
		return TRUE;
	}
	else
		g_s_traceflag = TRUE;
    return IVTBL(set_trace_port)(port,0);
}

/**获取wifiscan参数接口
*@param		wifi_info:	wifiscan参数     
**/
VOID iot_wifi_scan(OPENAT_wifiScanRequest* wifi_info)
{
	return IVTBL(get_wifiinfo)(wifi_info);
}


