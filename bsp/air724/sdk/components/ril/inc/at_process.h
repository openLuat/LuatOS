#ifndef AT_PROCESS_H
#define AT_PROCESS_H

#include "string.h"
#include "am_openat_vat.h"


//AT命令流程
//1, 主动发送AT指令
//2, 读取AT指令结果
//3, 假设AT指令默认都是以OK或者ERROR结尾
//read at result thread
#define AT_SUCCESS       0

#define AT_ERROR_GENERIC -1
#define AT_ERROR_COMMAND_PENDING -2
#define AT_ERROR_CHANNEL_CLOSED -3
#define AT_ERROR_TIMEOUT -4
#define AT_ERROR_INVALID_THREAD -5 /* AT commands may not be issued from
                                       reader thread (or unsolicited response
                                       callback */
#define AT_ERROR_INVALID_RESPONSE -6 /* eg an at_send_command_singleline that
                                        did not get back an intermediate
                                        response */

/** a singly-lined list of intermediate responses */
typedef struct ATLine  {
    struct ATLine *p_next;
    char *line;
} ATLine;

/** Free this with at_response_free() */
typedef struct {
    int success;              /* true if final response indicates
                                    success (eg "OK") */
    char *finalResponse;      /* eg OK, ERROR */
    ATLine  *p_intermediates; /* any intermediate responses */
} ATResponse;

typedef struct RILChannelDataTag
{
	char 				*data;
    int 				len;
}RILChannelData;




typedef enum {
    NO_RESULT,   /* no intermediate response expected */
    NUMERIC,     /* a single intermediate response starting with a 0-9 */
    SINGLELINE,  /* a single intermediate response starting with a prefix */
    MULTILINE    /* multiple line intermediate response
                    starting with a prefix */
} ATCommandType;

#ifndef IVTBL
#define IVTBL(func) (g_s_InterfaceVtbl->func)
#endif
#ifndef ASSERT
#define ASSERT(condition) IVTBL(assert)(condition, (CHAR*)__FUNCTION__, __LINE__)
#endif

typedef void (*ATUnsolHandler)(const char *s, const char *sms_pdu);


/*********************************************************
  Function:    ril_set_cb
  Description: 注册iot_vat_init回调函数
  Input:
        pAtMessage:iot_vat_init回调函数

*********************************************************/
void ril_set_cb(PAT_MESSAGE pAtMessage);

/*********************************************************
  Function:    at_init
  Description: 初始化
  Input:

  Output:
  Return:      
  Others:  1，初始化读线程
           2，初始化等待信号量
           3，初始化系统变量
*********************************************************/

void at_init(void);
/*********************************************************
  Function:    at_regNetStatusCb
  Description: 初始化
  Input:

  Output:
  Return:  
*********************************************************/

void at_regNetStatusCb(void (*netStatusCb)(int));


/*********************************************************
  Function:    at_send_command_singleline
  Description: 发送AT指令，并等待结果
  Input:

  Output:
  Return:       AT_ERROR_xx/AT_SUCCESS
  Others:
*********************************************************/

int at_send_command_singleline (const char *command,
                                const char *responsePrefix,
                                 ATResponse **pp_outResponse);
/*********************************************************
  Function:    at_send_command_numeric
  Description: 发送AT指令，并等待结果
  Input:

  Output:
  Return:       AT_ERROR_xx/AT_SUCCESS
  Others:
*********************************************************/

int at_send_command_numeric (const char *command,
                                 ATResponse **pp_outResponse);
                                 
/*********************************************************
  Function:    at_send_command_multiline
  Description: 发送AT指令，并等待结果
  Input:

  Output:
  Return:       AT_ERROR_xx/AT_SUCCESS
  Others:
*********************************************************/

int at_send_command_multiline (const char *command,
                                const char *responsePrefix,
                                 ATResponse **pp_outResponse);
                                 
/*********************************************************
  Function:    at_send_command_sms
  Description: 发送AT指令，并等待结果
  Input:

  Output:
  Return:       AT_ERROR_xx/AT_SUCCESS
  Others:
*********************************************************/
int at_send_command_sms (const char *command,
                                const char *pdu,
                                const char *responsePrefix,
                                 ATResponse **pp_outResponse);

/*********************************************************
  Function:    at_send_command
  Description: 发送AT指令，不等待结果
  Input:

  Output:
  Return:       AT_ERROR_xx/AT_SUCCESS
  Others:
*********************************************************/

int at_send_command (const char *command, ATResponse **pp_outResponse);

/*********************************************************
  Function:    at_response_free
  Description: 释放结果
  Input:

  Output:
  Return:      
  Others:
*********************************************************/
void at_response_free(ATResponse *p_response);

#endif



