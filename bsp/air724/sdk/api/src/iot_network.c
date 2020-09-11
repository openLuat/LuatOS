#include "string.h"
#include <stdio.h>
#include "at_process.h"
#include "at_tok.h"
#include "iot_debug.h"
#include "iot_network.h"

static F_OPENAT_NETWORK_IND_CB g_s_gsmStatusCb = NULL;
static unsigned char g_s_nwMode = 0;
static E_OPENAT_NETWORK_STATE nw_old_state = OPENAT_NETWORK_DISCONNECT;
static unsigned char at_init_flag=0;

static void gsmStatusCb( int status);




static BOOL iot_network_get_SYSINFO(int* srv_status,int*sys_mode,int*sim_state)
{
    ATResponse *p_response = NULL;
    bool result = FALSE;  
    int err = at_send_command_singleline("AT^SYSINFO", "^SYSINFO:", &p_response);
    if (err < 0 || p_response->success == 0)
    {
        iot_debug_print("[iot_network] at_send_command_singleline error %d",__LINE__);
        goto end;
    }
    char* line = p_response->p_intermediates->line;  
    err = at_tok_start(&line);
    if (err < 0)
        goto end;
    err = at_tok_nextint(&line,srv_status);
    if (err < 0)
        goto end;
    int temp=0;
    err = at_tok_nextint(&line,&temp);
    if (err < 0)
        goto end;
    err = at_tok_nextint(&line,&temp);
    if (err < 0)
        goto end;
    err = at_tok_nextint(&line,sys_mode);
    if (err < 0)
        goto end;
    err = at_tok_nextint(&line,sim_state);
    if (err < 0)
        goto end;
    result = TRUE;
end:              
    if(p_response!=NULL)
    {
        at_response_free(p_response);
        p_response=NULL;
    }  
    return result;
}


static BOOL iot_network_get_CSQ(int* rssi)
{

    ATResponse *p_response = NULL;
    bool result = FALSE;  
    int err = at_send_command_singleline("AT+CSQ", "+CSQ:", &p_response);
    if (err < 0 || p_response->success == 0)
        goto end;
    char* line = p_response->p_intermediates->line;  
    err = at_tok_start(&line);
    if (err < 0)
        goto end;
    err = at_tok_nextint(&line,rssi);
    if (err < 0)
        goto end; 
    result = TRUE;  
end:              
    if(p_response!=NULL)
    {
        at_response_free(p_response);
        p_response=NULL;
    }  
    return result;
}

/**获取网络状态
*@param     status:   返回网络状态
*@return    TRUE:    成功
            FLASE:   失败            
**/                                
BOOL iot_network_get_status(T_OPENAT_NETWORK_STATUS* status)
{
    if(at_init_flag==0)
    {
        at_init();
        at_init_flag=1;
    }


    int rssi=0;
    if(iot_network_get_CSQ(&rssi)==FALSE)
    {
        iot_debug_print("[iot_network] iot_network_get_CSQ error %d",__LINE__);
        return FALSE;
    }
    status->csq=rssi;
    //iot_debug_print("[iot_network] rssi:%d",rssi);   


    int srv_status=0,sys_mode=0,sim_state=0;
    if(iot_network_get_SYSINFO(&srv_status,&sys_mode,&sim_state)==FALSE)
    {
        iot_debug_print("[iot_network] iot_network_get_SYSINFO error %d",__LINE__);
        return FALSE;
    }
    if(sim_state!=1)
    {
        status->state=OPENAT_NETWORK_DISCONNECT;
        goto end;
    }
    if(srv_status!=2)
    {
        status->state=OPENAT_NETWORK_DISCONNECT;
        goto end;
    }
    if(sys_mode!=17)
    {
        status->state=OPENAT_NETWORK_READY;
        goto end;
    }

    status->state=OPENAT_NETWORK_LINKED;

end:
    status->simpresent=sim_state;
    //iot_debug_print("[iot_network] srv_status:%d,sys_mode:%d,sim_state:%d",srv_status, sys_mode, sim_state);
    return TRUE;  
}  

static void gsmStatusCb( int status)
{
  E_OPENAT_NETWORK_STATE nw_state;

  if(status >= 0x80 && status < 0x90)
  {
      //LTE 
      status = status - 0x80;
      if(status == 1 || status == 5)
      {
          nw_state = OPENAT_NETWORK_READY;

          g_s_nwMode = 4;
      }
      else
      {
          nw_state = OPENAT_NETWORK_DISCONNECT;

          g_s_nwMode = 0;
      }
  }
  else if(status >= 0x90)
  {
      status = status - 0x90;
      if(status == 1)
      {
          nw_state = OPENAT_NETWORK_LINKED;
      }
      else
      {
          nw_state = OPENAT_NETWORK_GOING_DOWN;
      }
  }
  else
  {
      if(status == 1 || status == 5)
      {
          nw_state = OPENAT_NETWORK_READY;
          g_s_nwMode = 2;
      }
      else
      {
          nw_state = OPENAT_NETWORK_DISCONNECT;
          g_s_nwMode = 0;  
      }
  }

  iot_debug_print("[iot_network] %s old %d new %d", __FUNCTION__, nw_old_state, nw_state);

  if(g_s_gsmStatusCb && nw_old_state != nw_state)
  {
    g_s_gsmStatusCb(nw_state);
    nw_old_state = nw_state;
  }
  
}
                           
/**设置网络状态回调函数
*@param     indCb:   回调函数
*@return    TRUE:    成功
            FLASE:   失败
**/                            
BOOL iot_network_set_cb(F_OPENAT_NETWORK_IND_CB indCb)
{
    if(at_init_flag==0)
    {    
        at_init();
        at_init_flag=1;
    }
    at_regNetStatusCb(gsmStatusCb);
    g_s_gsmStatusCb = indCb;
}        


static bool gsmGprsPDPActive(const char* apn, const char* user, const char* pwd )
{
  int err;
  ATResponse *p_response = NULL;
  char cmd[64] = {0};

  memset(cmd, 0, 64);

  sprintf(cmd, "AT+CGDCONT=5,IP,%s\r\n",apn);
            
  err = at_send_command(cmd, &p_response);
  iot_debug_print("[iot_network] CGDCONT error %d, success %d", err,(p_response?p_response->success:-1));
  if (err < 0 || p_response->success == 0){
    goto error;
  }

  at_response_free(p_response);
  
  memset(cmd, 0, 64);
  sprintf(cmd, "AT+CGACT=1,5");
            
  err = at_send_command(cmd, &p_response);
  iot_debug_print("[iot_network] CGACT error %d, success %d", err,(p_response?p_response->success:-1));
  if (err < 0 || p_response->success == 0){
    goto error;
  }

  at_response_free(p_response);
  return TRUE;

error:
  at_response_free(p_response);
  return FALSE;
}

/**建立网络连接，实际为pdp激活流程
*@param     connectParam:  网络连接参数，需要设置APN，username，passwrd信息
*@return    TRUE:    成功
            FLASE:   失败
@note      该函数为异步函数，返回后不代表网络连接就成功了，indCb会通知上层应用网络连接是否成功，连接成功后会进入OPENAT_NETWORK_LINKED状态
           创建socket连接之前必须要建立网络连接
           建立连接之前的状态需要为OPENAT_NETWORK_READY状态，否则会连接失败
**/                          
BOOL iot_network_connect(T_OPENAT_NETWORK_CONNECT* connectParam)
{
    //1. 等待4G网络准备好
    if(g_s_nwMode == 4) //4G直接用。默认激活pdp
    {
        return TRUE;
        
    }
    else if(g_s_nwMode == 2)//如果是2g，就回去重新激活一路pdp
    {
        if(gsmGprsPDPActive(connectParam->apn, connectParam->username, connectParam->password))
        {
            return TRUE;
        }
        else
        {
            return FALSE;
        }
    }
    else
    {
        return FALSE;
    }

}      



static bool gsmGprsPDPDeactive(void)
{
  int err;
  ATResponse *p_response = NULL;
  char cmd[64] = {0};
  
  memset(cmd, 0, 64);
  sprintf(cmd, "AT+CGACT=0,6");
            
  err = at_send_command(cmd, &p_response);
  if (err < 0 || p_response->success == 0){
    goto error;
  }

  at_response_free(p_response);
  return TRUE;

error:
  at_response_free(p_response);
  return FALSE;
}


/**断开网络连接，实际为pdp去激活
*@param     flymode:   暂时不支持，设置为FLASE
*@return    TRUE:    成功
            FLASE:   失败
@note      该函数为异步函数，返回后不代表网络连接立即就断开了，indCb会通知上层应用
           连接断开后网络状态会回到OPENAT_NETWORK_READY状态
           此前创建socket连接也会失效，需要close掉
**/                                        
BOOL iot_network_disconnect(BOOL flymode)
{
    if(g_s_nwMode == 4) //4G
    {
        return TRUE;
    }
    else if(g_s_nwMode == 2)
    {
        if(gsmGprsPDPDeactive())
        {
            return TRUE;
        }
        else
        {
            return FALSE;
        }
    }
    else
    {
        return FALSE;
    }
    
}                          

