#include "ctype.h"
#include "at_process.h"
#include "ril_pal.h"
#include "at_tok.h"

#define MAX_AT_RESPONSE (1 * 1024)
#define NUM_ELEMS(x) (sizeof(x) / sizeof(x[0]))
bool g_IsSMSRdy = FALSE;
static HANDLE at_channel_ready_sem; //at ready
static PAL_THREAD_ID s_tid_reader = 0;
static HANDLE s_state_sem;

static PAL_SEMAPHORE_ID s_commandsem;

static ATCommandType s_type;
static const char *s_responsePrefix = NULL;
static const char *s_smsPDU = NULL;
static ATResponse *sp_response = NULL;

static char s_ATBuffer[MAX_AT_RESPONSE + 1];
static char *s_ATBufferCur = s_ATBuffer;
static int s_readCount = 0;

static void (*s_netStatusCb)(int status);

static ATUnsolHandler s_unsolHandler = NULL;

static const char *s_smsUnsoliciteds[] = {
    "+CMT:",
    //    "+CMGR:",
    "+CDS:",
    "+CBM:",
    //   "^MODE",
    //   "^CARDMODE",
    //  "+NITZ"
};

static const char *s_finalResponsesSuccess[] = {
    "OK",
    "SHUT OK"
    //"CONNECT"       /* some stacks start up data on another channel */
};

static const char *s_finalResponsesError[] = {
    "ERROR",
    "+CMS ERROR:",
    "+CME ERROR:",
    //    "NO CARRIER", /* sometimes! */
    "NO ANSWER",
    "NO DIALTONE",
};

static int strStartsWith(const char *line, const char *prefix)
{
    for (; *line != '\0' && *prefix != '\0'; line++, prefix++)
    {
        if (*line != *prefix)
        {
            return 0;
        }
    }

    return *prefix == '\0';
}
void RIL_WaitAtChannelReady(void)
{
    pal_ril_sema_get(at_channel_ready_sem, PAL_SEMA_WAIT_FOREVER);
}
void RIL_NotifyAtChannelReady(void)
{
    pal_ril_sema_put(at_channel_ready_sem);
    pal_ril_sema_delete(at_channel_ready_sem);
}

/**
 * Called by atchannel when an unsolicited line appears
 * This is called on atchannel's reader thread. AT commands may
 * not be issued here
 */
static void onUnsolicited(const char *s, const char *sms_pdu)
{
    static BOOL at_channel_ready = FALSE;
    int netStatus;

    LOGD("%s read %d URC: %s", __FUNCTION__, at_channel_ready, s);

    if (!at_channel_ready)
    {
        if (strStartsWith(s, "RDY"))
        {
            at_channel_ready = TRUE;
            RIL_NotifyAtChannelReady();
            return;
        }
    }

    if (strStartsWith(s, "+CEREG:"))
    {
        at_tok_start((char **)&s);
        at_tok_nextint((char **)&s, &netStatus);

        if (netStatus != 1 && netStatus != 5 && s_netStatusCb)
        {
            s_netStatusCb(netStatus + 0x80);
        }
    }
    else if (strStartsWith(s, "+CREG:"))
    {
        at_tok_start((char **)&s);
        at_tok_nextint((char **)&s, &netStatus);

        if (netStatus != 1 && netStatus != 5 && s_netStatusCb)
        {
            s_netStatusCb(netStatus);
        }
    }
    else if (strStartsWith(s, "*CGEV: DEACT"))
    {
        if (s_netStatusCb)
        {
            s_netStatusCb(0x90);
        }
    }
    else if (strStartsWith(s, "*CGEV: ACT"))
    {
        if (s_netStatusCb)
        {
            s_netStatusCb(0x91);
        }
    }
    else if (strStartsWith(s, "SMS READY"))
    {
    	g_IsSMSRdy = TRUE;
    }
    else if (strStartsWith(s, "+E_UTRAN Service"))
    {
        if (s_netStatusCb)
        {
            s_netStatusCb(0x81);
        }
    }
    else if (strStartsWith(s, "+GSM Service"))
    {
        if (s_netStatusCb)
        {
            s_netStatusCb(0x1);
        }
    }
}
static char *findNextEOL(char *cur)
{
    if (cur[0] == '>' && cur[1] == ' ' && cur[2] == '\0')
    {
        return cur + 2;
    }

    while (*cur != '\0' && *cur != '\r' && *cur != '\n')
        cur++;

    return *cur == '\0' ? NULL : cur;
}

static int isSMSUnsolicited(const char *line)
{
    size_t i;

    for (i = 0; i < NUM_ELEMS(s_smsUnsoliciteds); i++)
    {
        if (strStartsWith(line, s_smsUnsoliciteds[i]))
        {
            return 1;
        }
    }

    return 0;
}

static int isFinalResponseSuccess(const char *line)
{
    size_t i;

    for (i = 0; i < NUM_ELEMS(s_finalResponsesSuccess); i++)
    {
        if (strStartsWith(line, s_finalResponsesSuccess[i]))
        {
            return 1;
        }
    }

    return 0;
}

static int isFinalResponseError(const char *line)
{
    size_t i;

    for (i = 0; i < NUM_ELEMS(s_finalResponsesError); i++)
    {
        if (strStartsWith(line, s_finalResponsesError[i]))
        {
            return 1;
        }
    }

    return 0;
}

/** add an intermediate response to sp_response*/
static void addIntermediate(const char *line)
{
    ATLine *p_new;

    p_new = (ATLine *)RIL_Malloc(sizeof(ATLine));

    p_new->line = strdup(line);

    /* note: this adds to the head of the list, so the list
       will be in reverse order of lines received. the order is flipped
       again before passing on to the command issuer */
    p_new->p_next = sp_response->p_intermediates;
    sp_response->p_intermediates = p_new;
}

/** assumes s_commandmutex is held */
static void handleFinalResponse(const char *line)
{
    sp_response->finalResponse = strdup(line);

    pal_ril_sema_put(s_commandsem);
}

static int writeCtrlZ (const char *s)
{
    int len = strlen(s);
    char ctrlz[2]={26,0}; // ctrl+z

    LOGD("AT> %s^Z\n", s);

    AT_DUMP( ">* ", s, strlen(s) );
    pal_ril_channel_write(s, len, FALSE);
    pal_ril_channel_write(ctrlz, 1, FALSE);
  
    return 0;
}

static const char *readline()
{
    ssize_t count;

    char *p_read = NULL;
    char *p_eol = NULL;
    char *ret;

    /* this is a little odd. I use *s_ATBufferCur == 0 to
     * mean "buffer consumed completely". If it points to a character, than
     * the buffer continues until a \0
     */
    if (*s_ATBufferCur == '\0')
    {
        /* empty buffer */
        s_ATBufferCur = s_ATBuffer;
        *s_ATBufferCur = '\0';
        p_read = s_ATBuffer;
        memset(s_ATBuffer, 0, sizeof(s_ATBuffer));
    }
    else
    { /* *s_ATBufferCur != '\0' */
        /* there's data in the buffer from the last read */

        // skip over leading newlines
        while (*s_ATBufferCur == '\r' || *s_ATBufferCur == '\n')
            s_ATBufferCur++;

        p_eol = findNextEOL(s_ATBufferCur);

        if (p_eol == NULL)
        {
            /* a partial line. move it up and prepare to read more */
            size_t len;

            len = strlen(s_ATBufferCur);

            memmove(s_ATBuffer, s_ATBufferCur, len + 1);
            p_read = s_ATBuffer + len;
            s_ATBufferCur = s_ATBuffer;

            if (len == 0)
            {
                memset(s_ATBuffer, 0, sizeof(s_ATBuffer));
            }
        }
        /* Otherwise, (p_eol !- NULL) there is a complete line  */
        /* that will be returned the while () loop below        */
    }

    while (p_eol == NULL)
    {
        if (0 == MAX_AT_RESPONSE - (p_read - s_ATBuffer))
        {
            LOGE("ERROR: Input line exceeded buffer\n");
            /* ditch buffer and start over again */
            s_ATBufferCur = s_ATBuffer;
            *s_ATBufferCur = '\0';
            p_read = s_ATBuffer;
            memset(s_ATBuffer, 0, sizeof(s_ATBuffer));
        }

        count = pal_ril_channel_read(p_read, MAX_AT_RESPONSE - (p_read - s_ATBuffer));

        if (count > 0)
        {

            AT_DUMP("<< ", p_read, count);
            s_readCount += count;

            p_read[count] = '\0';

            // skip over leading newlines
            while (*s_ATBufferCur == '\r' || *s_ATBufferCur == '\n')
                s_ATBufferCur++;

            p_eol = findNextEOL(s_ATBufferCur);
            p_read += count;
        }
        else if (count <= 0)
        {
            /* read error encountered or EOF reached */
            if (count == 0)
            {
                LOGD("atchannel: EOF reached");
            }
            else
            {
                LOGD("atchannel: read error ");
            }
            return NULL;
        }
    }

    /* a full line in the buffer. Place a \0 over the \r and return */

    ret = s_ATBufferCur;
    *p_eol = '\0';
    s_ATBufferCur = p_eol + 1; /* this will always be <= p_read,    */
                               /* and there will be a \0 at *p_read */

    LOGD("AT< %s\n", ret);
    return ret;
}

static void handleUnsolicited(const char *line)
{
    if (s_unsolHandler != NULL)
    {
        s_unsolHandler(line, NULL);
    }
}

static void processLine(const char *line)
{
    if (sp_response == NULL)
    {
        /* no command pending */
        handleUnsolicited(line);
    }
    else if (isFinalResponseSuccess(line))
    {
        sp_response->success = 1;
        handleFinalResponse(line);
    }
    else if (isFinalResponseError(line))
    {
        sp_response->success = 0;
        handleFinalResponse(line);
#if 1        
    } else if (s_smsPDU != NULL && 0 == strcmp(line, "> ")) {
        // See eg. TS 27.005 4.3
        // Commands like AT+CMGS have a "> " prompt
        writeCtrlZ(s_smsPDU);
        s_smsPDU = NULL;
#endif
    }
    else
        switch (s_type)
        {
        case NO_RESULT:
            handleUnsolicited(line);
            break;
        case NUMERIC:
            if (sp_response->p_intermediates == NULL && isdigit(line[0]))
            {
                addIntermediate(line);
            }
            else
            {
                /* either we already have an intermediate response or
                   the line doesn't begin with a digit */
                handleUnsolicited(line);
            }
            break;
            /*+\NewReq ATMMI-144\xiongjunqun\2012.01.05\修改手动搜网代码不合理的地方----重新修改ABORTED的上报*/
        case SINGLELINE:
            if (sp_response->p_intermediates == NULL && (strStartsWith(line, s_responsePrefix) || 0 == strncmp(line, "ABORTED", strlen("ABORTED"))))
            {
                addIntermediate(line);
            }
			else if((sp_response->finalResponse == NULL)&&(strstr(s_responsePrefix, "+CMGR") || strstr(s_responsePrefix, "+CMGL"))) /*将读到的短信内容返回到结果中*/
			{
				addIntermediate(line);
			}
            else
            {
                /* we already have an intermediate response */
                handleUnsolicited(line);
            }
            break;
        case MULTILINE:
            if (strStartsWith(line, s_responsePrefix) || 0 == strncmp(line, "ABORTED", strlen("ABORTED")))
            {
                addIntermediate(line);
            }
			else if((sp_response->finalResponse == NULL)&&(strstr(s_responsePrefix, "+CMGR") || strstr(s_responsePrefix, "+CMGL"))) /*将读到的短信内容返回到结果中*/
            {
                addIntermediate(line);
            }
            else
            {
                handleUnsolicited(line);
            }
            break;
            /*-\NewReq ATMMI-144\xiongjunqun\2012.01.05\修改手动搜网代码不合理的地方----重新修改ABORTED的上报*/
        default: /* this should never be reached */
            LOGE("Unsupported AT command type %d\n", s_type);
            handleUnsolicited(line);
            break;
        }
}

static void readerLoop(void *arg)
{
    LOGD("readerLoop: start");

    for (;;)
    {
        const char *line;

        line = readline();

        LOGD("%s line %s", __FUNCTION__, line);

        if (line == NULL)
        {
            break;
        }
        else if (isSMSUnsolicited(line))
        {
            char *line1;
            const char *line2;

            // The scope of string returned by 'readline()' is valid only
            // till next call to 'readline()' hence making a copy of line
            // before calling readline again.
            line1 = strdup(line);
            line2 = readline();

            if (line2 == NULL)
            {
                RIL_Free(line1);
                break;
            }

            if (s_unsolHandler != NULL)
            {
                s_unsolHandler(line1, line2);
            }
            RIL_Free(line1);
        }
        else
        {
            processLine(line);
        }
    }
    return;
}

/**
 * Starts AT handler on stream "fd'
 * returns 0 on success, -1 on error
 */
int at_open(void)
{
    s_unsolHandler = onUnsolicited;
    s_responsePrefix = NULL;
    s_smsPDU = NULL;
    sp_response = NULL;

    s_commandsem = pal_ril_sema_create("s_commandsem", 0);

    s_tid_reader = pal_ril_thread_create("RIL_ReadlineTask", readerLoop, 5, 5 * 1024, NULL);

    return 0;
}

PAL_THREAD_ID RIL_GetReaderThreadId(void)
{
    return s_tid_reader;
}

PAT_MESSAGE pIotVatMessage = NULL;

static VOID at_message(UINT8 *pData, UINT16 length)
{
    RILChannelData *pMessage;

    if (NULL == pData || 0 == length)
    {
        return;
    }
    if (pIotVatMessage != NULL)
    {
        pIotVatMessage(pData, length);
    }
    iot_debug_print("[ril] at_message (%d) %s", length, pData);

    if (RIL_GetReaderThreadId() != 0)
    {
        pMessage = iot_os_malloc(sizeof(RILChannelData));

        if (NULL != pMessage)
        {
            //copy data
            pMessage->data = iot_os_malloc(length);
            if (NULL != pMessage->data)
            {
                memcpy(pMessage->data, pData, length);
                pMessage->len = length;
                iot_os_send_message(RIL_GetReaderThreadId(), pMessage);
            }
            else
            {
                ASSERT(0);
                iot_os_free(pMessage);
            }
        }
    }
}

static void reverseIntermediates(ATResponse *p_response)
{
    ATLine *pcur, *pnext;

    pcur = p_response->p_intermediates;
    p_response->p_intermediates = NULL;

    while (pcur != NULL)
    {
        pnext = pcur->p_next;
        pcur->p_next = p_response->p_intermediates;
        p_response->p_intermediates = pcur;
        pcur = pnext;
    }
}

static int writeline(const char *s, ATCommandType type, const char *responsePrefix, const char *smspdu)
{
    int len = strlen(s);
    UINT32 sc;

    sc = IVTBL(enter_critical_section)();

    if (sp_response != NULL)
    {
        IVTBL(exit_critical_section)
        (sc);
        return AT_ERROR_COMMAND_PENDING;
    }

    //pal_ril_sleep_msec(20);
    s_type = type;
    s_responsePrefix = responsePrefix;
    s_smsPDU = smspdu;
    sp_response = (ATResponse *)RIL_Calloc(1, sizeof(ATResponse));

    IVTBL(exit_critical_section)
    (sc);

    LOGD("AT> %s\n", s);

    pal_ril_channel_write(s, len, TRUE);
    //    pal_ril_channel_write("\r\n", 1);

    return 0;
}

static int at_send_command_full_nolock(const char *command, ATCommandType type,
                                       const char *responsePrefix, const char *smspdu,
                                       long timeoutMsec, ATResponse **pp_outResponse)
{
    int err = 0;
#if 0
    static BOOL atReady = FALSE;

    if(!atReady)
    {
      RIL_WaitAtChannelReady();
      atReady = TRUE;
    }
#endif
    err = writeline(command, type, responsePrefix, smspdu);

    if (err == AT_ERROR_COMMAND_PENDING)
    {
        return err;
    }

    if (err >= 0)
    {
#if 0
    while (sp_response->finalResponse == NULL && s_readerClosed == 0)
#endif
        {
            /*TODO: timeoutMsec*/
            pal_ril_sema_get(s_commandsem, 0);
        }
        if (pp_outResponse == NULL)
        {
            at_response_free(sp_response);
        }
        else
        {
            /* line reader stores intermediate responses in reverse order */
            reverseIntermediates(sp_response);
            *pp_outResponse = sp_response;
        }

        sp_response = NULL;

        err = 0;
    }

    return err;
}

/*********************************************************
  Function:    at_iot_vat_init
  Description: 注册iot_vat_init回调函数
  Input:
        pAtMessage:iot_vat_init回调函数

*********************************************************/
void ril_set_cb(PAT_MESSAGE pAtMessage)
{
    pIotVatMessage = pAtMessage;
    OPENAT_init_at(at_message);
}

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

void at_init()
{
    at_channel_ready_sem = pal_ril_sema_create("at_channel_ready_sem", 0);

    s_state_sem = pal_ril_sema_create("s_state_sem", 1);

    memset(s_ATBuffer, 0, sizeof(s_ATBuffer));

    at_open();

    OPENAT_init_at(at_message);
    //网络状态主动上报
    at_send_command("ATE0", NULL);
    at_send_command("AT+CREG=1", NULL);
    at_send_command("AT+CEREG=1", NULL);
}

void at_regNetStatusCb(void (*netStatusCb)(int))
{
    s_netStatusCb = netStatusCb;
}

/*********************************************************
  Function:    at_send_command_singleline
  Description: 发送AT指令，并等待结果
  Input:

  Output:
  Return:       AT_ERROR_xx/AT_SUCCESS
  Others:
*********************************************************/

int at_send_command_singleline(const char *command,
                               const char *responsePrefix,
                               ATResponse **pp_outResponse)
{
    int err;

    err = at_send_command_full_nolock(command, SINGLELINE, responsePrefix,
                                      NULL, 0, pp_outResponse);

    if (err == 0 && pp_outResponse != NULL && (*pp_outResponse)->success > 0 && (*pp_outResponse)->p_intermediates == NULL)
    {
        /* successful command must have an intermediate response */
        at_response_free(*pp_outResponse);
        *pp_outResponse = NULL;
        return AT_ERROR_INVALID_RESPONSE;
    }

    return err;
}

/*********************************************************
  Function:    at_send_command_numeric
  Description: 发送AT指令，并等待结果
  Input:

  Output:
  Return:       AT_ERROR_xx/AT_SUCCESS
  Others:
*********************************************************/

int at_send_command_numeric(const char *command,
                            ATResponse **pp_outResponse)
{
    int err;

    err = at_send_command_full_nolock(command, NUMERIC, NULL,
                                      NULL, 0, pp_outResponse);

    if (err == 0 && pp_outResponse != NULL && (*pp_outResponse)->success > 0 && (*pp_outResponse)->p_intermediates == NULL)
    {
        /* successful command must have an intermediate response */
        at_response_free(*pp_outResponse);
        *pp_outResponse = NULL;
        return AT_ERROR_INVALID_RESPONSE;
    }

    return err;
}

/*********************************************************
  Function:    at_send_command_multiline
  Description: 发送AT指令，并等待结果
  Input:

  Output:
  Return:       AT_ERROR_xx/AT_SUCCESS
  Others:
*********************************************************/

int at_send_command_multiline(const char *command,
                              const char *responsePrefix,
                              ATResponse **pp_outResponse)
{
    int err;

    err = at_send_command_full_nolock(command, MULTILINE, responsePrefix,
                                      NULL, 0, pp_outResponse);

    return err;
}

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
                                 ATResponse **pp_outResponse)
{
    int err;

    err = at_send_command_full_nolock(command, SINGLELINE, responsePrefix,
                                    pdu, 0, pp_outResponse);

    if (err == 0 && pp_outResponse != NULL
        && (*pp_outResponse)->success > 0
        && (*pp_outResponse)->p_intermediates == NULL
    ) {
        /* successful command must have an intermediate response */
        at_response_free(*pp_outResponse);
        *pp_outResponse = NULL;
        return AT_ERROR_INVALID_RESPONSE;
    }

    return err;
}

/*********************************************************
  Function:    at_send_command
  Description: 发送AT指令，不等待结果
  Input:

  Output:
  Return:       AT_ERROR_xx/AT_SUCCESS
  Others:
*********************************************************/

int at_send_command(const char *command, ATResponse **pp_outResponse)
{
    int err;

    err = at_send_command_full_nolock(command, NO_RESULT,
                                      NULL, NULL,
                                      0, pp_outResponse);
    return err;
}

/*********************************************************
  Function:    at_response_free
  Description: 释放结果
  Input:

  Output:
  Return:      
  Others:
*********************************************************/

void at_response_free(ATResponse *p_response)
{
    ATLine *p_line;

    if (p_response == NULL)
        return;

    p_line = p_response->p_intermediates;

    while (p_line != NULL)
    {
        ATLine *p_toFree;

        p_toFree = p_line;
        p_line = p_line->p_next;

        RIL_Free(p_toFree->line);
        RIL_Free(p_toFree);
    }

    RIL_Free(p_response->finalResponse);
    RIL_Free(p_response);
}
