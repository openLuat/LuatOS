#include "string.h"
#include "iot_debug.h"
#include "iot_vat.h"
#include "iot_os.h"


typedef struct UrcEntityQueueTag
{
    UrcEntity urcEntityArray[URC_QUEUE_COUNT]; 
    u8 count;                                 
}UrcEntityQueue;

typedef struct AtCmdEntityQueueTag
{
    u8 current;                                 
    u8 last;                                    
    u8 funFirst;                                
    u8 funLast;                                 
    AtCmdEntity atCmdEntityArray[AT_CMD_QUEUE_COUNT]; 

}AtCmdEntityQueue;

#define MAX(a,b) ((a) > (b) ? (a) : (b))
#define MIN(a,b) ((a) < (b) ? (a) : (b))


int initstatus = FALSE;
static PAT_MESSAGE g_resp_cb = NULL;
gsmloc_cellinfo GSMLOC_CELL = {0};

static AtCmdEntityQueue s_atCmdEntityQueue={0};
static AtCmdRsp AtCmdCbDefault(char* pRspStr);   
static BOOL AtCmdDelayExe(u16 delay);
static BOOL iot_vat_queue_head_out(VOID);
static BOOL iot_vat_queue_tail_out(VOID);
static BOOL iot_vat_queue_fun_out(VOID);
static VOID iot_vat_queue_init(VOID);
static BOOL iot_vat_queue_is_empty(VOID);
static BOOL iot_vat_queue_fun_set(u8 funCount);
static BOOL iot_vat_queue_append(AtCmdEntity atCmdEntity);
static BOOL iot_vat_queue_fun_append(AtCmdEntity atCmdEntity[],u8 funCount);
static VOID iot_vat_SendCMD(VOID);
static VOID iot_vat_Modeuleinit(VOID);

static AtCmdRsp AtVatCmdCbDefault(char* pRspStr)
{
    iot_debug_print("[envelope] AtVatCmdCbDefault");
    AtCmdRsp  rspValue = AT_RSP_WAIT;
    char *rspStrTable[ ] = {"OK","ERROR","+CME ERROR"};
    s16  rspType = -1;
    u8  i = 0;
    if(g_resp_cb)
    {
        g_resp_cb((UINT8 *)pRspStr, (UINT16)strlen(pRspStr));
    }
    char  *p = pRspStr + 2;
    for (i = 0; i < sizeof(rspStrTable) / sizeof(rspStrTable[0]); i++)
    {
        if (!strncmp(rspStrTable[i], p, strlen(rspStrTable[i])))
        {
            rspType = i;
            break;
        }
    }
    switch (rspType)
    {
        case 0:  /* OK */
        case 1:  /* ERROR */
        case 2:  /* +CME ERROR */
            rspValue  = AT_RSP_CONTINUE;
            break;
        default:
            break;
    }
    return rspValue;
}

static AtCmdRsp AtCmdCbDefault(char* pRspStr)
{
	iot_debug_print("[vat] AtCmdCbDefault");
    AtCmdRsp  rspValue = AT_RSP_WAIT;
    char *rspStrTable[ ] = {"OK","ERROR"};
    s16  rspType = -1;
    u8  i = 0;
    char  *p = pRspStr + 2;
    for (i = 0; i < sizeof(rspStrTable) / sizeof(rspStrTable[0]); i++)
    {
        if (!strncmp(rspStrTable[i], p, strlen(rspStrTable[i])))
        {
            rspType = i;
            break;
        }
    }
    switch (rspType)
    {
        case 0:  /* OK */
        rspValue  = AT_RSP_CONTINUE;
        break;

        case 1:  /* ERROR */
        rspValue = AT_RSP_ERROR;
        break;

        default:
        break;
    }

    return rspValue;
}
    
static BOOL AtCmdDelayExe(u16 delay)
{
	BOOL ret = FALSE;
	iot_debug_print("[vat]INFO: at cmd delay execute,%d",delay);
	if (delay == 0){
		delay = AT_CMD_EXECUTE_DELAY;
	}
	ret = iot_os_sleep(delay);
	iot_vat_SendCMD();
	return ret;
}

static VOID iot_vat_queue_init(VOID)
{
    u8 i = 0;
    u8 first = MIN(s_atCmdEntityQueue.current,s_atCmdEntityQueue.funFirst);
    for ( i=first; i<=s_atCmdEntityQueue.last; i++) {
        AtCmdEntity* atCmdEnt = NULL;
        atCmdEnt = &(s_atCmdEntityQueue.atCmdEntityArray[i]);
        if(atCmdEnt->p_atCmdStr){
            iot_os_free(atCmdEnt->p_atCmdStr);
            atCmdEnt->p_atCmdStr = NULL;
        }
        atCmdEnt->p_atCmdCallBack = NULL;
    }
    memset(&s_atCmdEntityQueue,0,sizeof(AtCmdEntityQueue));
}

static BOOL iot_vat_queue_head_out(VOID)
{
    AtCmdEntity* atCmdEnt = NULL;

   if(s_atCmdEntityQueue.current == s_atCmdEntityQueue.last) /* the queue is empty */
       return FALSE;

   if(s_atCmdEntityQueue.current>=s_atCmdEntityQueue.funLast
           || s_atCmdEntityQueue.current<=s_atCmdEntityQueue.funFirst){
       atCmdEnt = &(s_atCmdEntityQueue.atCmdEntityArray[s_atCmdEntityQueue.current]);
       if(atCmdEnt->p_atCmdStr){
           iot_os_free(atCmdEnt->p_atCmdStr);
           atCmdEnt->p_atCmdStr = NULL;
       }
       atCmdEnt->p_atCmdCallBack = NULL;
   }
   s_atCmdEntityQueue.current = (s_atCmdEntityQueue.current + 1) %  AT_CMD_QUEUE_COUNT;
   return TRUE;
}

static BOOL iot_vat_queue_tail_out(VOID)
{
    AtCmdEntity* atCmdEnt = NULL;
    if(s_atCmdEntityQueue.current == s_atCmdEntityQueue.last)
        return FALSE;
    s_atCmdEntityQueue.last = (s_atCmdEntityQueue.last + AT_CMD_QUEUE_COUNT - 1) % AT_CMD_QUEUE_COUNT;
    atCmdEnt = &(s_atCmdEntityQueue.atCmdEntityArray[s_atCmdEntityQueue.last]);
    if(atCmdEnt->p_atCmdStr){
        iot_os_free(atCmdEnt->p_atCmdStr);
        atCmdEnt->p_atCmdStr = NULL;
    }
    atCmdEnt->p_atCmdCallBack = NULL;
    return TRUE;
}

static BOOL iot_vat_queue_fun_out(VOID)
{
    u8 i = 0;
    if (s_atCmdEntityQueue.funLast == 0)        /* no at cmd func */
        return FALSE;

    if (s_atCmdEntityQueue.funLast < s_atCmdEntityQueue.funFirst)
	{
	    for (i = s_atCmdEntityQueue.funFirst; i < AT_CMD_QUEUE_COUNT; i++) 
		{
           AtCmdEntity* atCmdEnt = NULL;
           atCmdEnt = &(s_atCmdEntityQueue.atCmdEntityArray[i]);
           if(atCmdEnt->p_atCmdStr){
               iot_os_free(atCmdEnt->p_atCmdStr);
               atCmdEnt->p_atCmdStr = NULL;
           }
           atCmdEnt->p_atCmdCallBack = NULL;
       }
	
	    for (i = 0;i <= s_atCmdEntityQueue.funLast; i++)
		{
            AtCmdEntity* atCmdEnt = NULL;
            atCmdEnt = &(s_atCmdEntityQueue.atCmdEntityArray[i]);
            if(atCmdEnt->p_atCmdStr){
                iot_os_free(atCmdEnt->p_atCmdStr);
                atCmdEnt->p_atCmdStr = NULL;
            }
            atCmdEnt->p_atCmdCallBack = NULL;
        }
    }
	else
	{
	    for ( i=s_atCmdEntityQueue.funFirst ;i<=s_atCmdEntityQueue.funLast ; i++) {
	        AtCmdEntity* atCmdEnt = NULL;
	        atCmdEnt = &(s_atCmdEntityQueue.atCmdEntityArray[i]);
	        if(atCmdEnt->p_atCmdStr){
	            iot_os_free(atCmdEnt->p_atCmdStr);
	            atCmdEnt->p_atCmdStr = NULL;
	        }
	        atCmdEnt->p_atCmdCallBack = NULL;
	    }
	}

    if(s_atCmdEntityQueue.current != s_atCmdEntityQueue.funLast){
        s_atCmdEntityQueue.current = s_atCmdEntityQueue.funLast;
    }

    s_atCmdEntityQueue.current = (s_atCmdEntityQueue.current + 1) % AT_CMD_QUEUE_COUNT;
    s_atCmdEntityQueue.funLast = 0;
    s_atCmdEntityQueue.funFirst = 0;
    return TRUE;

}

static BOOL iot_vat_queue_is_empty(VOID)
{
    return (s_atCmdEntityQueue.current == s_atCmdEntityQueue.last);
}

static BOOL iot_vat_queue_fun_set(u8 funCount)
{
    u8 first =  MAX(s_atCmdEntityQueue.current,s_atCmdEntityQueue.funFirst);
    u8 freeCount = 0;
	#if 0
    if (s_atCmdEntityQueue.funLast != s_atCmdEntityQueue.funFirst){
        iot_debug_print("[vat]ERROR: fun is exist!");
        return FALSE;                           /* just one func exist */
    }
	#endif
    if(iot_vat_queue_is_empty()){
        freeCount = AT_CMD_QUEUE_COUNT;
    }
    else {
        freeCount = (first - s_atCmdEntityQueue.last + AT_CMD_QUEUE_COUNT) % AT_CMD_QUEUE_COUNT;
    }
    if(funCount > freeCount) {
        iot_debug_print("[vat]ERROR: the queue is full! %d,%d,%d",first,funCount,freeCount);
        return FALSE;                           /* the space is poor */
    }

    s_atCmdEntityQueue.funFirst = s_atCmdEntityQueue.last;
    s_atCmdEntityQueue.funLast = (s_atCmdEntityQueue.last + funCount - 1 + AT_CMD_QUEUE_COUNT) % AT_CMD_QUEUE_COUNT;
    iot_debug_print("[vat]INFO: the at cmd func's range is %d-%d", s_atCmdEntityQueue.funFirst, s_atCmdEntityQueue.funLast);
    return TRUE;
}

static BOOL iot_vat_queue_append(AtCmdEntity atCmdEntity)
{
                                                /* get first index */
    u8 first =  MAX(s_atCmdEntityQueue.current,s_atCmdEntityQueue.funFirst);

    if (atCmdEntity.p_atCmdStr == NULL){
        iot_debug_print("[vat]ERROR: at cmd str is null!");
        return FALSE;
    }

    if (atCmdEntity.p_atCmdCallBack == NULL)    /* set default callback function */
        atCmdEntity.p_atCmdCallBack = AtCmdCbDefault;

    if((s_atCmdEntityQueue.last + 1) % AT_CMD_QUEUE_COUNT == first){
        iot_debug_print("[vat]ERROR: at cmd queue is full!");
        return FALSE;                           /* the queue is full */
    }
    else{
        char* pAtCmd = NULL; 

        pAtCmd = iot_os_malloc(atCmdEntity.cmdLen+1);
		pAtCmd[atCmdEntity.cmdLen] = 0;
        if (!pAtCmd){
            iot_debug_print("[vat]ERROR: memory alloc error!");
            return FALSE;
        }

        memcpy(pAtCmd,atCmdEntity.p_atCmdStr,atCmdEntity.cmdLen);
        s_atCmdEntityQueue.atCmdEntityArray[s_atCmdEntityQueue.last].cmdLen = atCmdEntity.cmdLen;
        s_atCmdEntityQueue.atCmdEntityArray[s_atCmdEntityQueue.last].p_atCmdStr = pAtCmd;
        s_atCmdEntityQueue.atCmdEntityArray[s_atCmdEntityQueue.last].p_atCmdCallBack = atCmdEntity.p_atCmdCallBack;
        s_atCmdEntityQueue.last = (s_atCmdEntityQueue.last + 1) %  AT_CMD_QUEUE_COUNT;
	    iot_debug_print("[vat]pAtCmd : %s",pAtCmd);
        return TRUE;
    }
}

static BOOL iot_vat_queue_fun_append(AtCmdEntity atCmdEntity[],u8 funCount)
{
    u8 i = 0;
    BOOL ret = FALSE;
    ret = iot_vat_queue_fun_set(funCount);
    if(!ret)
        return FALSE;

    for ( i=0; i<funCount; i++) {
        BOOL ret = FALSE;
        ret = iot_vat_queue_append(atCmdEntity[i]);
        if (!ret){
            break;
        }
    }

    if(i != funCount){                           /* error is ocur */
        for ( i=funCount; i > 0; i--) {
            iot_vat_queue_tail_out();
        }
        iot_debug_print("[vat]ERROR: add to queue is error!,%d",funCount);
        return FALSE;
    }

    iot_debug_print("[vat]INFO: funFirst:%d  funLast:%d", s_atCmdEntityQueue.funFirst, s_atCmdEntityQueue.funLast);
    return TRUE;
}

static int iot_vat_atoi(char* str_p)
{
	int i;
	int num = 0;
	char* p;
	p = str_p;
	int len = strlen(str_p);
	for(i = 0; i < len; i++)
	{
		if(*(p+i) >= '0' && *(p+i)<='9')
			num = num*10 + STR_TO_INT(*(p+i));
	}
	return num;
}
/*获取小区和邻小区信息*/
static VOID GetCellInfo(UINT8 *pData)
{
	int cut = 0;
	char* p = (char *)pData;
	char buf[50][15] = {0};
	/*LTE cellinfo*/
	if(!strncmp((char *)pData, "\r\n+EEMLTESVC:", strlen("\r\n+EEMLTESVC:")))	
	{
		p = p + strlen("\r\n+EEMLTESVC:");
		char* b = strtok(p, ",");
		while(b != NULL)
		{

			strcpy(buf[cut], b);
			cut++;
			b = strtok(NULL, ",");
		}
		GSMLOC_CELL.Cellinfo[0].Mcc = (u16)iot_vat_atoi(buf[0]);
		GSMLOC_CELL.Cellinfo[0].Mnc = (u16)iot_vat_atoi(buf[2]);
		GSMLOC_CELL.Cellinfo[0].Lac= (u32)iot_vat_atoi(buf[3]);
		GSMLOC_CELL.Cellinfo[0].CellId = (u32)iot_vat_atoi(buf[9]);
		GSMLOC_CELL.Cellinfo[0].rssi = (u16)iot_vat_atoi(buf[14])/3;
		iot_debug_print("[vat] mcc: %d,  mnc: %d,  lac: %d,  ci: %d,  rssi: %d,",
			GSMLOC_CELL.Cellinfo[0].Mcc,
			GSMLOC_CELL.Cellinfo[0].Mnc,
			GSMLOC_CELL.Cellinfo[0].Lac,
			GSMLOC_CELL.Cellinfo[0].CellId,
			GSMLOC_CELL.Cellinfo[0].rssi);
	}
	/*UMT cellinfo*/
	if(!strncmp((char *)pData, "\r\n+EEMUMTSSVC:", strlen("\r\n+EEMUMTSSVC:")))	
	{
		UINT16 cellMeasureFlag;
		UINT16 cellParamFlag;
		UINT16 offset = 3;
		p = p + strlen("\r\n+EEMUMTSSVC:");
		char* b = strtok(p, ",");
		while(b != NULL)
		{

			strcpy(buf[cut], b);
			cut++;
			b = strtok(NULL, ",");
		}
		cellMeasureFlag = (UINT16)iot_vat_atoi(buf[1]);
		cellParamFlag = (UINT16)iot_vat_atoi(buf[2]);
		if(cellMeasureFlag != 0)
		{
			offset = offset + 2;
			GSMLOC_CELL.Cellinfo[0].rssi = (u16)iot_vat_atoi(buf[offset])/3;
			offset = offset + 4;
		}
		else
		{
			offset = offset + 2;
			GSMLOC_CELL.Cellinfo[0].rssi = (u16)iot_vat_atoi(buf[offset])/3;
			offset = offset + 2;
		}
		if(cellParamFlag != 0)

		{
			offset = offset + 3;
			iot_debug_print("[vat] buf[%d]: %s,  buf[%d]: %s,  buf[%d]: %s,  buf[%d]: %s,",
				offset, buf[offset],
				offset+1, buf[offset+1],
				offset+2, buf[offset+2],
				offset+3, buf[offset+3]);
			GSMLOC_CELL.Cellinfo[0].Mcc = (u16)iot_vat_atoi(buf[offset]);
			GSMLOC_CELL.Cellinfo[0].Mnc = (u16)iot_vat_atoi(buf[offset+1]);
			GSMLOC_CELL.Cellinfo[0].Lac= (u32)iot_vat_atoi(buf[offset+2]);
			GSMLOC_CELL.Cellinfo[0].CellId = (u32)iot_vat_atoi(buf[offset+3]);
		}
		iot_debug_print("[vat] mcc: %d,  mnc: %d,  lac: %d,  ci: %d,  rssi: %d,",
			GSMLOC_CELL.Cellinfo[0].Mcc,
			GSMLOC_CELL.Cellinfo[0].Mnc,
			GSMLOC_CELL.Cellinfo[0].Lac,
			GSMLOC_CELL.Cellinfo[0].CellId,
			GSMLOC_CELL.Cellinfo[0].rssi);
	}
	/*GSM curCellInfo*/
	if(!strncmp((char *)pData, "\r\n+EEMGINFOSVC:", strlen("\r\n+EEMGINFOSVC:")))	
	{
		p = p + strlen("\r\n+EEMGINFOSVC:");
		char* b = strtok(p, ",");
		while(b != NULL)
		{

			strcpy(buf[cut], b);
			cut++;
			b = strtok(NULL, ",");
		}
		GSMLOC_CELL.Cellinfo[0].Mcc = (u16)iot_vat_atoi(buf[0]);
		GSMLOC_CELL.Cellinfo[0].Mnc = (u16)iot_vat_atoi(buf[1]);
		GSMLOC_CELL.Cellinfo[0].Lac= (u32)iot_vat_atoi(buf[2]);
		GSMLOC_CELL.Cellinfo[0].CellId = (u32)iot_vat_atoi(buf[3]);
		if(iot_vat_atoi(buf[9]) > 31)
		{
			GSMLOC_CELL.Cellinfo[0].rssi = 31;
		}
		else if(iot_vat_atoi(buf[9]) < 0)
		{
			GSMLOC_CELL.Cellinfo[0].rssi = 0;
		}
		else
		{
			GSMLOC_CELL.Cellinfo[0].rssi = iot_vat_atoi(buf[9]);
		}
		iot_debug_print("[vat] mcc: %d,  mnc: %d,  lac: %d,  ci: %d,  rssi: %d,",
			GSMLOC_CELL.Cellinfo[0].Mcc,
			GSMLOC_CELL.Cellinfo[0].Mnc,
			GSMLOC_CELL.Cellinfo[0].Lac,
			GSMLOC_CELL.Cellinfo[0].CellId,
			GSMLOC_CELL.Cellinfo[0].rssi);
	}
	/*GSM nbrCellInfo*/
	if(!strncmp((char *)pData, "\r\n+EEMGINFONC:", strlen("\r\n+EEMGINFONC:")))	
	{
		p = p + strlen("\r\n+EEMGINFONC:");
		char* b = (char*)strtok(p, (const char *)',');
		u8 id = 0;
		while(b != NULL)
		{

			strcpy(buf[cut], b);
			cut++;
			b = (char*)strtok(NULL, (const char *)',');
		}
		id = iot_vat_atoi(buf[0]);
		GSMLOC_CELL.Cellinfo[id+1].Mcc = (u16)iot_vat_atoi(buf[1]);
		GSMLOC_CELL.Cellinfo[id+1].Mnc = (u16)iot_vat_atoi(buf[2]);
		GSMLOC_CELL.Cellinfo[id+1].Lac= (u32)iot_vat_atoi(buf[3]);
		GSMLOC_CELL.Cellinfo[id+1].CellId = (u32)iot_vat_atoi(buf[5]);
		GSMLOC_CELL.Cellinfo[id+1].rssi = (u16)iot_vat_atoi(buf[6]);
		iot_debug_print("[vat] mcc: %d,  mnc: %d,  lac: %d,  ci: %d,  rssi: %d,",
			GSMLOC_CELL.Cellinfo[id+1].Mcc,
			GSMLOC_CELL.Cellinfo[id+1].Mnc,
			GSMLOC_CELL.Cellinfo[id+1].Lac,
			GSMLOC_CELL.Cellinfo[id+1].CellId,
			GSMLOC_CELL.Cellinfo[id+1].rssi);
	}
}
static VOID iot_vat_ATCmdIndHandle(UINT8 *pData, UINT16 length)
{
    if (length > 0) 
	{
		iot_debug_print("[vat] pData : %s , %d", pData, length);
		
	    AtCmdRsp atCmdRsp = AT_RSP_ERROR;

	    if (s_atCmdEntityQueue.atCmdEntityArray[s_atCmdEntityQueue.current].p_atCmdCallBack)
		{
	        atCmdRsp = s_atCmdEntityQueue.atCmdEntityArray[s_atCmdEntityQueue.current].p_atCmdCallBack((char*)pData);

	        iot_debug_print("[vat]INFO: callback return %d,%d",s_atCmdEntityQueue.current,atCmdRsp);
	        switch ( atCmdRsp )
			{
	            case AT_RSP_ERROR:
	                iot_debug_print("[vat]ERROR: at cmd execute error, initial at cmd queue!");
	                iot_vat_queue_init();
	                break;
	            case AT_RSP_CONTINUE:	
	            case AT_RSP_FINISH:	
	                iot_vat_queue_head_out();
	                AtCmdDelayExe(0);
	                break;
				case AT_RSP_PAUSE:				/*添加暂停执行AT队列命令*/
					iot_vat_queue_head_out();
					break;
	            case AT_RSP_FUN_OVER:	
	                iot_vat_queue_fun_out();
	                AtCmdDelayExe(0);
	                break;

	            case AT_RSP_WAIT:
	                break;

	            default:	
	                if(atCmdRsp>=AT_RSP_STEP_MIN && atCmdRsp<=AT_RSP_STEP_MAX) 
				   {
	                    s8 step = s_atCmdEntityQueue.current + atCmdRsp - AT_RSP_STEP;
	                    iot_debug_print("[vat]DEBUG: cur %d,step %d",s_atCmdEntityQueue.current,step);
					  iot_debug_print("[vat]s_atCmdEntityQueue.funFirst = %d, s_atCmdEntityQueue.funLast = %d",s_atCmdEntityQueue.funFirst, s_atCmdEntityQueue.funLast);
	                    if(step<=s_atCmdEntityQueue.funLast && step>= s_atCmdEntityQueue.funFirst)
					  {
	                        s_atCmdEntityQueue.current = step;
	                        AtCmdDelayExe(0);
	                    }
	                    else
					  {
	                        iot_debug_print("[vat]ERROR: return of AtCmdRsp is error!");
	                    }
	                }
	                break;
	        }
	    }
	}
}

static VOID iot_vat_SendCMD(VOID)
{
	char* pCmd = s_atCmdEntityQueue.atCmdEntityArray[s_atCmdEntityQueue.current].p_atCmdStr;
	u16 len = s_atCmdEntityQueue.atCmdEntityArray[s_atCmdEntityQueue.current].cmdLen;
	if(pCmd){
		u16 lenAct = 0;
		iot_debug_print("[vat]DEBUG:at cmd is:%d,%s,%d",s_atCmdEntityQueue.current,pCmd,len);
		if (!strncmp((char*)AT_CMD_DELAY, pCmd, strlen((char*)AT_CMD_DELAY))) {  /* delay some seconds to run next cmd */
			uint32 delay = 0;
			int i = 0;
			for(i = 0; i < (len - strlen((char*)AT_CMD_DELAY)); i++)
			{
				if(pCmd[strlen((char*)AT_CMD_DELAY)+i]>='0' && pCmd[strlen((char*)AT_CMD_DELAY)+i] <= '9')
				{
					delay = delay*10 + STR_TO_INT(pCmd[strlen(AT_CMD_DELAY)+i]);
				}else
				{
					break;
				}
			}
			iot_vat_queue_head_out();
			AtCmdDelayExe(delay);
			return;
		}
		lenAct = OPENAT_send_at_command((UINT8 *)pCmd,(UINT16)len);
		if(!lenAct)
			iot_debug_print("[vat]ERROR: send at cmd error!");
		else{
			iot_debug_print("[vat]send at cmd:%s",pCmd);
		}
	}
}

static VOID iot_vat_Modeuleinit(VOID)
{
	if(initstatus)
	{
		return;
	}
	initstatus = TRUE;
	iot_vat_queue_init();
	ril_set_cb(iot_vat_ATCmdIndHandle);
	//OPENAT_init_at(iot_vat_ATCmdIndHandle);	
}

/**用来批量发送AT命令
*@param		cmd:  AT命令参数
*@param   	cmd_count:  AT命令个数
*@return	TRUE: 成功   FALSE: 失败
**/
BOOL iot_vat_push_cmd(AtCmdEntity cmd[],u8 cmd_count)
{
	BOOL result = FALSE;
	iot_vat_Modeuleinit();
	result = iot_vat_queue_fun_append(cmd,cmd_count);
    iot_vat_SendCMD();
    return result;
}

/**用来设置虚拟AT通道的回调函数
*@param		vatHandle:  虚拟AT主动上报或者AT命令结果返回的回调函数
*@return	TRUE: 成功   FALSE: 失败
**/
BOOL iot_vat_init(PAT_MESSAGE vatHandle)
{
    iot_vat_Modeuleinit();
    if(vatHandle)
    {
        g_resp_cb = vatHandle;
    }
    return TRUE;
}

/**用来发送AT命令
*@param		cmdStr:  AT命令字符串
*@param   	cmdLen:  AT命令长度
*@return	TRUE: 成功   FALSE: 失败
*@note      注意，AT命令字符串cmdStr中需要包含"\r\n"或者"\r"结尾
**/
BOOL iot_vat_send_cmd(UINT8* cmdStr, UINT16 cmdLen)
{
    BOOL result = FALSE;
    AtCmdEntity atCmdInit[]={
    	{(char *)cmdStr,cmdLen,AtVatCmdCbDefault},
    };
    result = iot_vat_queue_fun_append(atCmdInit,sizeof(atCmdInit) / sizeof(atCmdInit[0]));
    iot_vat_SendCMD();
    return result;    
}


