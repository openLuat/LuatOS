#include "port.h"
#include "stdint.h"
#include "lcd_cfg.h"
#define FB_CNT  2
#define TP_EVENT_CNT    (128)
#define KEY_EVENT_CNT   (128)
#define SRV_EVENT_CNT   (128)
void luatos_main_entry(void);

typedef struct
{
	uint32_t event_id;
	uint32_t param1;
	uint32_t param2;
	uint32_t param3;
    uint32_t lock;
}__event_t;

typedef struct
{
    __krnl_event_t  *msg_queue;
    __event_t *event_buf;
    volatile uint32_t event_pos;
}__event_queue_t;

typedef struct
{
    __krnl_event_t  *psys_msg_queue;				// msg 消息队列
    __event_t tp_event_buf[TP_EVENT_CNT];
    __event_t key_event_buf[KEY_EVENT_CNT];
    __event_t srv_event_buf[SRV_EVENT_CNT];
    volatile uint32_t tp_event_pos;
    volatile uint32_t key_event_pos;
    volatile uint32_t srv_event_pos;
	__hdle  		h_tpGraber;
	__hdle  		h_keyGraber;
    __s32		    last_touch_action;
    __u8			msg_srv_tid;
    __u8 			ksrv_th_id;
}kernel_ctrlstruct;


typedef struct
{
    ES_FILE* hdis;
	__hdle hlayer;
	uint32_t * layer_buf[FB_CNT];    //一个图层使用2个FrameBuffer
    uint32_t width;
    uint32_t height;
    uint32_t layer_buf_len;
    uint32_t layer_pix;
	uint8_t fb_index;
    uint8_t color_byte;
    uint8_t test_color;
}display_ctrlstruct;

typedef union
{
    __disp_color_t color;
    uint32_t data;
    /* data */
}color_union;


static display_ctrlstruct g_display;
static kernel_ctrlstruct prv_kernel;


/**
 * 通过回调函数的方式取触摸屏消息
 */
static __s32 tp_msg_cb(void *msg)
{
	__event_t	*pmsg;
	__u8 error;

	__u32 i;
	__input_event_packet_t *pPacket;
	__input_event_t        *pEventFrame;
	__input_event_t        pEvent_type;
	__input_event_t        pEvent_x;
	__input_event_t        pEvent_y;
	__input_event_t        pEvent_speed_dir;
	__input_event_t        pEvent_speed_val;
	DBG("!");
	if (msg == NULL)
	{
		DBG("invalid argument for call back");
		return EPDK_FAIL;
	}

	/* dump packet events */
	pPacket = (__input_event_packet_t *)msg;
	if (pPacket->event_cnt <= 0 || pPacket->event_cnt > INPUT_MAX_EVENT_NR)
	{
		DBG("invalid event count number");
		return EPDK_FAIL;
	}
	//__inf("\n------------------------------------------------\n");
	for (i = 0; i < pPacket->event_cnt; i++)
	{
		pEventFrame = &(pPacket->events[i]);
		/*__inf("Event %d: type = %d, code = %d, value = %d\n", i + 1,
																 pEventFrame->type,
																 pEventFrame->code,
																 pEventFrame->value
																 );*/
		if(pEventFrame->type == EV_ABS)
		{
			if(pEventFrame->code == ABS_MISC)
			{
				eLIBs_memcpy(&pEvent_type, pEventFrame, sizeof(__input_event_t));
			}
			else if(pEventFrame->code == ABS_X)
			{
				eLIBs_memcpy(&pEvent_x, pEventFrame, sizeof(__input_event_t));
			}
			else if(pEventFrame->code == ABS_Y)
			{
				eLIBs_memcpy(&pEvent_y, pEventFrame, sizeof(__input_event_t));
			}
			else if(pEventFrame->code == ABS_RUDDER)
			{
				eLIBs_memcpy(&pEvent_speed_dir, pEventFrame, sizeof(__input_event_t));
			}
			else if(pEventFrame->code == ABS_BRAKE)
			{
				eLIBs_memcpy(&pEvent_speed_val, pEventFrame, sizeof(__input_event_t));
			}
		}
		else if(pEventFrame->type == EV_SYN)
		{
			break;
		}
	}
	//__inf("\n------------------------------------------------\n");
    if (prv_kernel.tp_event_pos >= TP_EVENT_CNT)
    {
        prv_kernel.tp_event_pos = 0;
    }
    pmsg = &prv_kernel.tp_event_buf[prv_kernel.tp_event_pos];
    if (pmsg->lock)
    {
        DBG("tp event overload");
		return EPDK_FAIL;
    }

	pmsg->param3 = pEvent_type.value;
    
	switch( pEvent_type.value)
	{
		case EV_TP_PRESS_START:
		{
			pmsg->event_id 	= GUI_MSG_TOUCH_DOWN;
			pmsg->param1 	= (pEvent_y.value<<16) + pEvent_x.value;
			pmsg->param2 = (pEvent_speed_dir.value<<16) + pEvent_speed_val.value;
			prv_kernel.last_touch_action = GUI_MSG_TOUCH_DOWN;
			break;
		}
		case EV_TP_PRESS_MOVE:
			pmsg->event_id 	= GUI_MSG_TOUCH_MOVE;
			pmsg->param1 	= (pEvent_y.value<<16) + pEvent_x.value;
			pmsg->param2 = (pEvent_speed_dir.value<<16) + pEvent_speed_val.value;
			prv_kernel.last_touch_action = GUI_MSG_TOUCH_MOVE;
			break;
		case EV_TP_PINCH_IN:
			pmsg->event_id 	= GUI_MSG_TOUCH_ZOOMIN;
			pmsg->param1 	= (pEvent_y.value<<16) + pEvent_x.value;
			pmsg->param2 = (pEvent_speed_dir.value<<16) + pEvent_speed_val.value;
			prv_kernel.last_touch_action = GUI_MSG_TOUCH_ZOOMIN;
			break;
		case EV_TP_PINCH_OUT:
			pmsg->event_id 	= GUI_MSG_TOUCH_ZOOMOUT;
			pmsg->param1 	= (pEvent_y.value<<16) + pEvent_x.value;
			pmsg->param2 = (pEvent_speed_dir.value<<16) + pEvent_speed_val.value;
			prv_kernel.last_touch_action = GUI_MSG_TOUCH_ZOOMOUT;
			break;
		case EV_TP_PRESS_HOLD:
			pmsg->event_id 	= prv_kernel.last_touch_action;
			pmsg->param1 	= (pEvent_y.value<<16) + pEvent_x.value;
			pmsg->param2 = (pEvent_speed_dir.value<<16) + pEvent_speed_val.value;
			break;

		case EV_TP_ACTION_NULL:
		case EV_TP_ACTION_CLICK:
		case EV_TP_ACTION_DOWN:
		case EV_TP_ACTION_UP:
		case EV_TP_ACTION_LEFT:
		case EV_TP_ACTION_RIGHT:
		case EV_TP_ACTION_ANTICLOCKWISE:
		case EV_TP_ACTION_CLOCKWISE:
		case EV_TP_ACTION_LD2RU:
		case EV_TP_ACTION_RU2LD:
		case EV_TP_ACTION_LU2RD:
		case EV_TP_ACTION_RD2LU:
			pmsg->event_id 	= GUI_MSG_TOUCH_UP;
			pmsg->param1 	= (pEvent_y.value<<16) + pEvent_x.value;
			pmsg->param2 = (pEvent_speed_dir.value<<16) + pEvent_speed_val.value;
			break;
		default:
			return EPDK_FALSE;
	}
    pmsg->lock = 1;
    prv_kernel.tp_event_pos++;
	esKRNL_QPost(prv_kernel.psys_msg_queue, pmsg);

	return EPDK_TRUE;
}

static __s32 key_msg_cb(void *msg)
{
	__event_t	*pmsg;
	__u8 error;

	__u32 i;
	__input_event_packet_t *pPacket;
	__input_event_t        *pEventFrame;
	DBG("!");
	if (msg == NULL)
	{
		DBG("invalid argument for call back");
		return EPDK_FAIL;
	}


	//dump packet events
	pPacket = (__input_event_packet_t *)msg;
	if (pPacket->event_cnt > INPUT_MAX_EVENT_NR)
	{
		DBG("invalid event count number");
		return EPDK_FAIL;
	}

	for (i = 0; i < pPacket->event_cnt; i++)
	{
		pEventFrame = &(pPacket->events[i]);
		__msg("Event %d: type = %d, code = %d, value = %d\n", i + 1,
																 pEventFrame->type,
																 pEventFrame->code,
																 pEventFrame->value
																 );
		if(pEventFrame->type == EV_KEY)
		{
            if (prv_kernel.key_event_pos >= KEY_EVENT_CNT)
            {
                prv_kernel.key_event_pos = 0;
            }
            pmsg = &prv_kernel.key_event_buf[prv_kernel.key_event_pos];
            if (pmsg->lock)
            {
                DBG("key event overload");
                return EPDK_FAIL;
            }
            pmsg->param3 = pEventFrame->code;
			switch(pEventFrame->code)
			{
				case KPAD_MENU:
				{
					pmsg->event_id 	= GUI_MSG_KEY;
					pmsg->param1 	= GUI_MSG_KEY_MENU;
					break;
				}
				case KPAD_UP:
				{
					pmsg->event_id 	= GUI_MSG_KEY;
					pmsg->param1 	= GUI_MSG_KEY_UP;
					break;
				}
				case KPAD_DOWN:
				{
					pmsg->event_id 	= GUI_MSG_KEY;
					pmsg->param1 	= GUI_MSG_KEY_DOWN;
					break;
				}
				case KPAD_LEFT:
				{
					pmsg->event_id 	= GUI_MSG_KEY;
					pmsg->param1 	= GUI_MSG_KEY_LEFT;
					break;
				}
				case KPAD_RIGHT:
				{
					pmsg->event_id 	= GUI_MSG_KEY;
					pmsg->param1 	= GUI_MSG_KEY_RIGHT;
					break;
				}
				case KPAD_VOICEUP:
				{
					pmsg->event_id 	= GUI_MSG_KEY;
					pmsg->param1 	= GUI_MSG_KEY_VADD;
					break;
				}
				case KPAD_VOICEDOWN:
				{
					pmsg->event_id 	= GUI_MSG_KEY;
					pmsg->param1 	= GUI_MSG_KEY_VDEC;
					break;
				}
				case KPAD_ENTER:
				{
					pmsg->event_id 	= GUI_MSG_KEY;
					pmsg->param1 	= GUI_MSG_KEY_ENTER;
					break;
				}
				case KPAD_RETURN:
				case KPAD_HOME:
				{
					pmsg->event_id 	= GUI_MSG_KEY;
					pmsg->param1 	= GUI_MSG_KEY_ESCAPE;
					break;
				}
				case KPAD_POWER:
				{
					pmsg->event_id 	= GUI_MSG_KEY;
					pmsg->param1 	= GUI_MSG_KEY_POWER;
					break;
				}
				case KPAD_POWEROFF:
				{
					pmsg->event_id 	= DSK_MSG_POWER_OFF;
					break;
				}
				default:
					break;
			}
			pmsg->param2	= pEventFrame->value;
			DBG("GUI_MSG_KEY_ val=%d, pmsg->type=%d, org msg %d", pmsg->event_id, pmsg->param1, pmsg->param3);
            pmsg->lock = 1;
            prv_kernel.key_event_pos++;
			esKRNL_QPost(prv_kernel.psys_msg_queue, pmsg);
		}
	}
	return EPDK_TRUE;
}

/**
 * 从系统消息队列取消息
 */
static void ksrv_msg_thread(void *arg)
{
	__u8  error;

	/* 清空按键消息队列 */
	while(1)
	{
		__u32           usrmsg;

		//usrmsg = esKSRV_GetLowMsg();
		usrmsg = esKSRV_GetMsg();
		if( usrmsg == 0 )
			break;
	}

	while(1)
	{
		__u32           usrmsg;
		__event_t	*pmsg;

		while(1)
		{
			if( esKRNL_TDelReq(OS_PRIO_SELF) == OS_TASK_DEL_REQ )
			{
				esKRNL_TDel(OS_PRIO_SELF);
			}

			usrmsg = esKSRV_GetMsg();				// 系统消息队列
			if(usrmsg)
				break;
			esKRNL_TimeDly(2);
		}
		DBG("!");
        if (prv_kernel.srv_event_pos >= SRV_EVENT_CNT)
        {
            prv_kernel.srv_event_pos = 0;
        }
        pmsg = &prv_kernel.srv_event_buf[prv_kernel.srv_event_pos];
        if (pmsg->lock)
        {
            DBG("srv event overload");
            continue;
        }
        pmsg->param3 = usrmsg;

		if( (usrmsg & 0xffff0000) == KMSG_USR_CLS_KEY) 	// key 按键消息
		{
			switch (usrmsg)
			{

			#if( EPDK_CASE == EPDK_LIVE_BOX )
				case KMSG_USR_KEY_POWER:				/* standby	*/
					 pmsg->event_id = DSK_MSG_STANDBY;
					 break;

				case KMSG_USR_KEY_REPEATE:				/* 切换到色差输出 */
					pmsg->event_id = DSK_MSG_SWITCH_YPBPR;
					break;

				case KMSG_USR_KEY_CLEAR:				/* 切换到cvbs输出 */
					pmsg->event_id = DSK_MSG_SWITCH_CVBS;
					break;

				case KMSG_USR_KEY_DISPLAY:				/* 切换到hdmi输出 */
					pmsg->event_id = DSK_MSG_SWITCH_HDMI;
					break;

				case KMSG_USR_KEY_SHIFT:
					 pmsg->event_id = GUI_MSG_KEY;
					 pmsg->param1	= GUI_MSG_KEY_SHIFT;
					break;

				case KMSG_USR_KEY_SEL:
					 pmsg->event_id = GUI_MSG_KEY;
					 pmsg->param1	= GUI_MSG_KEY_SEL;
					break;

				case KMSG_USR_KEY_NUM4:
					pmsg->event_id = DSK_MSG_SWITCH_AUDIO_IF;
					pmsg->param2 = AUDIO_DEV_IF_CODEC;
					break;

				case KMSG_USR_KEY_NUM5:
					pmsg->event_id = DSK_MSG_SWITCH_AUDIO_IF;
					pmsg->param2 = AUDIO_DEV_IF_IIS;
					break;

				case KMSG_USR_KEY_NUM6:
					pmsg->event_id = DSK_MSG_SWITCH_AUDIO_IF;
					pmsg->param2 = AUDIO_DEV_IF_SPDIF;
					break;

			#endif

			#if( EPDK_CASE == EPDK_LIVE_TOUCH )
				case KMSG_USR_KEY_NUM8:					/* hold 按键 */
					 pmsg->event_id = DSK_MSG_HOLD;
					 break;

				case KMSG_USR_KEY_NUM7:								// 禁音功能
					pmsg->event_id = DSK_MSG_BAN_VOLUME;
					pmsg->param2 = 0;
					break;

			#endif

				case KMSG_USR_KEY_GOTO:
					pmsg->event_id = DSK_MSG_APP_EXIT;		/* 一键回主界面 */
					break;

				case KMSG_USR_KEY_POWEROFF:				// 关机消息
					 pmsg->event_id = DSK_MSG_POWER_OFF;
					 break;

				case KMSG_USR_KEY_NUM9:
					 pmsg->event_id = GUI_MSG_KEY;
					 pmsg->param1	= GUI_MSG_KEY_ESCAPE;
					 break;

				case KMSG_USR_KEY_VOICE_UP:
					 pmsg->event_id = GUI_MSG_KEY;
					 pmsg->param1	= GUI_MSG_KEY_VADD;
					 break;

				case KMSG_USR_KEY_VOICE_DOWN:
					 pmsg->event_id    = GUI_MSG_KEY;
					 pmsg->param1	   = GUI_MSG_KEY_VDEC;
					 break;

				case KMSG_USR_KEY_UP:
					 pmsg->event_id    = GUI_MSG_KEY;
					 pmsg->param1	   = GUI_MSG_KEY_UP;
					 break;

				case KMSG_USR_KEY_DOWN  :
					 pmsg->event_id    = GUI_MSG_KEY;
					 pmsg->param1	   = GUI_MSG_KEY_DOWN;
					 break;

				case KMSG_USR_KEY_LEFT  :
					 pmsg->event_id    	= GUI_MSG_KEY;
					 pmsg->param1	    = GUI_MSG_KEY_LEFT;
					 break;

				case KMSG_USR_KEY_RIGHT :
					 pmsg->event_id    	= GUI_MSG_KEY;
					 pmsg->param1	    = GUI_MSG_KEY_RIGHT;
					 break;

				case KMSG_USR_KEY_ENTER:
					 pmsg->event_id    	= GUI_MSG_KEY;
					 pmsg->param1	    = GUI_MSG_KEY_ENTER;
					break;

				case KMSG_USR_KEY_RISE:
					pmsg->event_id    	= GUI_MSG_KEY;
					pmsg->param1	    = GUI_MSG_KEY_RISE;
					break;

				default:
					continue;
			}
		}
		else	/* system 消息 */
		{
			if( (usrmsg & 0x0000ffff) == KMSG_USR_SYSTEM_FS_PLUGIN )
			{
				pmsg->event_id = DSK_MSG_FS_PART_PLUGIN;
				pmsg->param2 = (usrmsg & KMSG_USR_SYSTEM_FS_PARA_MASK)>>16;
			}
			else if( (usrmsg & 0x0000ffff) == KMSG_USR_SYSTEM_FS_PLUGOUT )
			{
				pmsg->event_id = DSK_MSG_FS_PART_PLUGOUT;
				pmsg->param2 = (usrmsg & KMSG_USR_SYSTEM_FS_PARA_MASK)>>16;
			}
			else if((usrmsg & 0x0000ffff) == KMSG_USR_SYSTEM_WLAN_PLUGIN)
			{
				tp_ad("00DSK_MSG_WIFI_PART_PLUGIN\n");
				pmsg->event_id = DSK_MSG_WIFI_PART_PLUGIN;
			}
			else if((usrmsg & 0x0000ffff) == KMSG_USR_SYSTEM_WLAN_PLUGOUT)
			{
				tp_ad("00DSK_MSG_WIFI_PART_PLUGOUT\n");
				pmsg->event_id = DSK_MSG_WIFI_PART_PLUGOUT;
			}
			else
			{
				__msg("*************usrmsg = %d***************\n", usrmsg);
				switch (usrmsg)
				{
					case KMSG_USR_SYSTEM_USBD_PLUGIN:		// usb device plug in
						 __msg("case KMSG_USR_SYSTEM_USBD_PLUGIN\n");
						 pmsg->event_id = DSK_MSG_USBD_PLUG_IN;
						 break;

					case KMSG_USR_SYSTEM_USBD_PLUGOUT:    	// usb device plug out
						 pmsg->event_id = DSK_MSG_USBD_PLUG_OUT;
						 __msg("case KMSG_USR_SYSTEM_USBD_PLUGOUT\n");
						 break;

					case KMSG_USR_SYSTEM_SDMMC_PLUGOUT:
						 pmsg->event_id = DSK_MSG_APP_EXIT;
						 break;

					case KMSG_USR_SYSTEM_USBH_PLUGOUT:		// usb host 设备拔出
						 pmsg->event_id = DSK_MSG_APP_EXIT;
						 break;

					case KMSG_USR_SYSTEM_TVDAC_PLUGIN:
						__msg("**********KMSG_USR_SYSTEM_TVDAC_PLUGIN***********\n");
						 pmsg->event_id = DSK_MSG_TVDAC_PLUGIN;
						 break;

					case KMSG_USR_SYSTEM_TVDAC_PLUGOUT:
						__msg("***********KMSG_USR_SYSTEM_TVDAC_PLUGOUT***************\n");
						 pmsg->event_id = DSK_MSG_TVDAC_PLUGOUT;
						 break;

					case KMSG_USR_SYSTEM_HDMI_PLUGIN:
						__msg("**********KMSG_USR_SYSTEM_HDMI_PLUGIN***********\n");
						 pmsg->event_id = DSK_MSG_HDMI_PLUGIN;
						 break;

					case KMSG_USR_SYSTEM_HDMI_PLUGOUT:
						__msg("***********KMSG_USR_SYSTEM_HDMI_PLUGOUT***************\n");
						 pmsg->event_id = DSK_MSG_HDMI_PLUGOUT;
						 break;

					case KMSG_USR_SYSTEM_WEBCAM_PLUGIN:
						 eLIBs_printf("***********KMSG_USR_SYSTEM_WEBCAM_PLUGIN***************\n");
		    		     pmsg->event_id = DSK_MSG_UVC_DEVICE_PLUGIN;
		                 break;

					case KMSG_USR_SYSTEM_WEBCAM_PLUGOUT:
						 eLIBs_printf("***********KMSG_USR_SYSTEM_WEBCAM_PLUGOUT***************\n");
		    		     pmsg->event_id = DSK_MSG_UVC_DEVICE_PLUGOUT;
		                 break;
					#if( EPDK_CASE == EPDK_LIVE_TOUCH )
					case KMSG_USR_SYSTEM_WAKEUP:
						 __here__
						pmsg->event_id = DSK_MSG_STANDBY_WAKE_UP;
					 break;
					#endif

					default:
						continue;
				}
			}
		}
        pmsg->lock = 1;
        prv_kernel.srv_event_pos++;
		esKRNL_QPost(prv_kernel.psys_msg_queue, pmsg);
	}
}


static void app_init(void)
{
    ES_FILE 	*pHwsc;
    __s32  LdevID;
	__s32 ret;
    ret = esDEV_Plugin("\\drv\\audio.drv", 0, 0, 1);
	DBG("%d", ret);
    ret = esDEV_Plugin("\\drv\\matrixkey.drv", 0, 0, 1);
	DBG("%d", ret);
	ret = esDEV_Plugin("\\drv\\ir.drv", 0, 0, 1);
	DBG("%d", ret);
    pHwsc = eLIBs_fopen("b:\\HWSC\\hwsc", "rb+");
	DBG("%d", pHwsc);
    if(pHwsc)
    {
        eLIBs_fioctrl(pHwsc, DEV_IOC_USR_HWSC_ENABLE_MONITOR, 0, NULL);
        eLIBs_fclose(pHwsc);
    }
    else
    {
        __err("try to open b:\\HWSC\\hwsc failed!\n");
    }
    eLIBs_memset(&prv_kernel, 0, sizeof(prv_kernel));
    prv_kernel.psys_msg_queue  = esKRNL_QCreate(TP_EVENT_CNT + KEY_EVENT_CNT + SRV_EVENT_CNT);
    prv_kernel.h_tpGraber = esINPUT_LdevGrab(INPUT_LTS_DEV_NAME, (__pCBK_t)tp_msg_cb, 0, 0);
    prv_kernel.h_keyGraber = esINPUT_LdevGrab(INPUT_LKEYBOARD_DEV_NAME, (__pCBK_t)key_msg_cb, 0, 0);
	DBG("0x%x, 0x%x, 0x%x", prv_kernel.psys_msg_queue, prv_kernel.h_tpGraber, prv_kernel.h_keyGraber);
    LdevID = esINPUT_GetLdevID(prv_kernel.h_keyGraber);
	if (LdevID != -1)
	{
        if (esINPUT_LdevCtl(LdevID, INPUT_SET_REP_PERIOD, 200, NULL) != EPDK_OK)
        {
            DBG("key device ioctl failed\n");
        }
	}
	else
	{
		DBG("key device ioctl failed\n");
	}
    prv_kernel.ksrv_th_id = esKRNL_TCreate(ksrv_msg_thread, (void *)&prv_kernel, 0x400, KRNL_priolevel3);
}
//初始化显示
static void disp_lcd_init(void)
{	
	__disp_layer_info_t     layer_para;
    __u32 arg[3];
	g_display.hdis   = eLIBs_fopen("b:\\DISP\\DISPLAY", "r+");
    arg[0] = (uint32_t)lcd_common_rgb_gpio_list;
	arg[1] = (uint32_t)LCD_common_rbg_cfg_panel_info;
	arg[2] = (uint32_t)LCD_common_rbg_cfg_panel_info1;
	eLIBs_fioctrl(g_display.hdis, DISP_CMD_RESERVE0, 0, (void *)arg);    //加入这句才能开始用驱动，后续还要加入参数来动态选择LCD屏
    eLIBs_fioctrl(g_display.hdis, DISP_CMD_LCD_ON, 0, NULL);    //加入这句才能开始启动LCD
    g_display.width = eLIBs_fioctrl(g_display.hdis, DISP_CMD_SCN_GET_WIDTH, SEL_SCREEN,0); //modified by Derek,2010.12.07.15:05
	g_display.height = eLIBs_fioctrl(g_display.hdis, DISP_CMD_SCN_GET_HEIGHT, SEL_SCREEN,0); //modified by Derek,2010.12.07.15:05
    g_display.fb_index = 0;
    g_display.color_byte = 4;//ARGB8888
    g_display.layer_buf_len = g_display.width*g_display.height*g_display.color_byte;
    g_display.layer_pix = g_display.width*g_display.height;
    g_display.layer_buf[0] = esMEMS_Palloc(( g_display.layer_buf_len + 1023 ) / 1024, 0);
    g_display.layer_buf[1] = esMEMS_Palloc(( g_display.layer_buf_len + 1023 ) / 1024, 0);
    eLIBs_memset(g_display.layer_buf[0], 0, g_display.layer_buf_len);
    eLIBs_memset(g_display.layer_buf[1], 0, g_display.layer_buf_len);


	eLIBs_memset(&layer_para, 0, sizeof(__disp_layer_info_t));

    layer_para.fb.addr[0] = (__u32)g_display.layer_buf[0];
    layer_para.fb.size.width = g_display.width;
    layer_para.fb.size.height = g_display.height;
    layer_para.fb.mode = DISP_MOD_INTERLEAVED;
    layer_para.fb.format = DISP_FORMAT_ARGB8888;
    layer_para.fb.br_swap = 0;
    layer_para.fb.seq = DISP_SEQ_BGRA;
    layer_para.ck_enable = 0;
    layer_para.alpha_en = 0;
    layer_para.alpha_val = 0;
    layer_para.pipe = 0;
    layer_para.prio = 0;
    layer_para.src_win.x = 0;
    layer_para.src_win.y = 0;
    layer_para.src_win.width = g_display.width;
    layer_para.src_win.height = g_display.height;
    layer_para.scn_win.x = 0;
    layer_para.scn_win.y = 0;
    layer_para.scn_win.width = g_display.width;
    layer_para.scn_win.height = g_display.height;
    layer_para.mode = DISP_LAYER_WORK_MODE_NORMAL;

    
	arg[0] = DISP_LAYER_WORK_MODE_NORMAL;
	arg[1] = 0;
	arg[2] = 0;
	g_display.hlayer = eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_REQUEST, 0, (void *)arg);
    DBG("layer %x", g_display.hlayer);

	arg[0] = g_display.hlayer;
	arg[1] = (__u32)&layer_para;
	arg[2] = 0;
	eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_SET_PARA, 0, (void *)arg);

	arg[0] = g_display.hlayer;
	arg[1] = 0;
	arg[2] = 0;
	eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_TOP, 0, (void *)arg);

    arg[0] = g_display.hlayer;
    arg[1] = 0;
    arg[2] = 0;
    eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_OPEN, 0, (void*)arg);
}

static void disp_lcd_test(void)
{
    uint32_t i;
    uint32_t *buf;
    uint8_t next_buffer_index = (g_display.fb_index + 1) % FB_CNT;
    __disp_fb_t fb;  
	color_union u_color;
    __u32 arg[3];

    g_display.test_color = (g_display.test_color + 1) % 3;  //R,G,B轮转测试
    buf = g_display.layer_buf[next_buffer_index];
    i = 0;
    
	u_color.data = 0;
	u_color.color.alpha = 0xff;
	switch(g_display.test_color)
	{
	case 0:
		u_color.color.red = 255;
        DBG("test red");
		break;
	case 1:
		u_color.color.green = 255;
        DBG("test green");
		break;
	case 2:
		u_color.color.blue = 255;
        DBG("test blue");
		break;
	}
	for(i = 0; i < g_display.layer_buf_len / 4; i++)
	{
		buf[i] = u_color.data;
	}

    arg[0] = g_display.hlayer;
    arg[1] = (__u32)&fb;
    arg[2] = 0;
    eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_GET_FB, 0, arg);


    fb.addr[0] = (__u32)buf;
    eLIBs_fioctrl(g_display.hdis, DISP_CMD_LAYER_SET_FB, 0, arg);
    g_display.fb_index = next_buffer_index;
}

static void port_thread(void *arg)
{
    __event_t *tmp;
    __u8 error;
    app_init();
    disp_lcd_init();
    //disp_lcd_test();
    //luatos_main_entry();
    while(1)
    {
        tmp = (__event_t *)esKRNL_QPend( prv_kernel.psys_msg_queue, 0, &error);

        if( tmp!= NULL)
        {
            tmp->lock = 0;
            DBG("%d,%x,%x,%x", tmp->event_id, tmp->param1, tmp->param2, tmp->param3);
        }
    }
}

int port_entry(void)
{
    u8 id;
    esKSRV_CloseLogo();
    DBG("entry luatos app!");
    id = esKRNL_TCreate(port_thread, NULL, 0x10000, KRNL_priolevel1);
    DBG("thread id %d!", id);
}