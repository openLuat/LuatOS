#include "port.h"
#include "stdint.h"
#include "lcd_cfg.h"
#define FB_CNT  2
#define DEV_EVENT_CNT	(128)
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

typedef struct _robin_msg_t
{
	__u32  id;
	__u32  data;
	__cedar_media_file_inf  file_info;
}robin_msg_t;

typedef struct
{
	__uart_para_t uart_param[3];
    __krnl_event_t  *psys_msg_queue;				// msg 消息队列
	__event_t uart_event_buf[DEV_EVENT_CNT];
    __event_t tp_event_buf[TP_EVENT_CNT];
	__event_t mou_event_buf[TP_EVENT_CNT];
    __event_t key_event_buf[KEY_EVENT_CNT];
    __event_t srv_event_buf[SRV_EVENT_CNT];
	__event_t cedar_event_buf[DEV_EVENT_CNT];
	volatile uint32_t uart_event_pos;
    volatile uint32_t tp_event_pos;
	volatile uint32_t mou_event_pos;
    volatile uint32_t key_event_pos;
    volatile uint32_t srv_event_pos;
	volatile uint32_t cedar_event_pos;
	uint32_t 		uart_br[3];
	__hdle  		h_tpGraber;
	__hdle  		h_keyGraber;
	__hdle  		h_mouseGraber;
	ES_FILE 		*pUart;
    __s32		    last_touch_action;

    uint8_t			msg_srv_tid;
    uint8_t 		ksrv_th_id;
	uint8_t			cedar_task_id;
}kernel_ctrlstruct;

typedef struct port
{
	volatile  __mp *robin_hced;
	volatile  ES_FILE *p_dac;
	__hdle          h_media_lay;
	volatile  __krnl_event_t *cedar_msgQ;
	volatile uint8_t mid_ced;
}media_ctrlstruct;

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
static media_ctrlstruct prv_media;
static void test_thread(void *arg);

const uint8_t ByteToAsciiTable[16] = {'0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'};


static void dump(uint8_t *Data, uint32_t Len)
{
	uint8_t *buf = esMEMS_Malloc(0, Len * 3 + 4);
	uint32_t i = 0;
	uint32_t j = 0;
	eLIBs_memset(buf, 0, Len * 3 + 4);
	while (i < Len)
	{
		buf[j++] = ByteToAsciiTable[(Data[i] & 0xf0) >> 4];
		buf[j++] = ByteToAsciiTable[Data[i++] & 0x0f];
		buf[j++] = ' ';
	}
	buf[j++] = '\r';
	buf[j++] = '\n';
	__log(buf);
	esMEMS_Mfree(0, buf);

}


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

/**
 * 通过回调函数的方式取鼠标消息
 */
static __s32 mouse_msg_cb(void *msg)
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
    if (prv_kernel.mou_event_pos >= TP_EVENT_CNT)
    {
        prv_kernel.mou_event_pos = 0;
    }
    pmsg = &prv_kernel.tp_event_buf[prv_kernel.mou_event_pos];
    if (pmsg->lock)
    {
        DBG("mouse event overload");
		return EPDK_FAIL;
    }
	pmsg->event_id 	= 0x10000;
	pmsg->param1 	= (pEvent_y.value<<16) + pEvent_x.value;
	pmsg->param2 = (pEvent_speed_dir.value<<16) + pEvent_speed_val.value;
	pmsg->param3 = pEvent_type.value;
    
    pmsg->lock = 1;
    prv_kernel.mou_event_pos++;
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
		DBG("0x%x", usrmsg);
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

static void cedar_msg_thread(void *arg)
{
	__event_t	*pmsg;
	__u8 error;
    __s32  msg;
           
	while(1)
	{
		msg = (__s32)esKRNL_QPend( prv_media.cedar_msgQ, 0, &error );
		if (msg != CEDAR_ERROR_NOP && msg != CEDAR_FEDBAK_NO_ERROR)
		{
			DBG("%d", msg);
		}
	}
}


static void app_uart_cb(uint32_t id, uint32_t event, uint32_t param)
{
	__event_t	*pmsg;
	if (prv_kernel.uart_event_pos >= DEV_EVENT_CNT)
    {
        prv_kernel.uart_event_pos = 0;
    }
    pmsg = &prv_kernel.uart_event_buf[prv_kernel.uart_event_pos];
    if (pmsg->lock)
    {
        DBG("uart event overload");
		return ;
    }
	pmsg->event_id = UART_MSG_INT_CALLBACK;
	pmsg->param1 = event;
	pmsg->param2 = param;
	pmsg->lock = 1;
	prv_kernel.srv_event_pos++;
	esKRNL_QPost(prv_kernel.psys_msg_queue, pmsg);
}

static void app_init(void)
{
    ES_FILE 	*pHwsc;
    __s32  LdevID;
	__s32 ret;
    ret = esDEV_Plugin("\\drv\\audio.drv", 0, 0, 1);
    ret = esDEV_Plugin("\\drv\\matrixkey.drv", 0, 0, 1);
	ret = esDEV_Plugin("\\drv\\ir.drv", 0, 0, 1);
	ret = esDEV_Plugin("\\drv\\uart.drv", 2, 0, 1);
    pHwsc = eLIBs_fopen("b:\\HWSC\\hwsc", "rb+");
	prv_media.p_dac = eLIBs_fopen("b:\\AUDIO\\CTRL", "r+");
	prv_media.mid_ced = esMODS_MInstall( "d:\\mod\\cedar.mod", 0 );
	prv_media.robin_hced = esMODS_MOpen(prv_media.mid_ced, 0);
	prv_media.cedar_msgQ = (__krnl_event_t *)esMODS_MIoctrl( prv_media.robin_hced, CEDAR_CMD_GET_MESSAGE_CHN, 0, NULL );
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
	prv_kernel.pUart = eLIBs_fopen("b:\\BUS\\UART2", "rb+");
	prv_kernel.uart_param[2].nDataLen = (8 - 5);
	prv_kernel.uart_param[2].nStopBit = (1 - 1);
	prv_kernel.uart_param[2].nParityEnable = 0;
	prv_kernel.uart_param[2].nEvenParity = 0;
	eLIBs_fioctrl(prv_kernel.pUart, UART_CMD_SET_PARA, 0, &prv_kernel.uart_param[2]);
	prv_kernel.uart_br[2] = 921600;
	eLIBs_fioctrl(prv_kernel.pUart, UART_CMD_SET_BAUDRATE, 0, &prv_kernel.uart_br[2]);
	eLIBs_fioctrl(prv_kernel.pUart, UART_CMD_SET_CB, 0, (void *)app_uart_cb);
	eLIBs_fwrite("hello world!\r\n", 15, 1, prv_kernel.pUart);
    prv_kernel.psys_msg_queue  = esKRNL_QCreate(TP_EVENT_CNT + KEY_EVENT_CNT + SRV_EVENT_CNT);
    prv_kernel.h_tpGraber = esINPUT_LdevGrab(INPUT_LTS_DEV_NAME, (__pCBK_t)tp_msg_cb, 0, 0);
    prv_kernel.h_keyGraber = esINPUT_LdevGrab(INPUT_LKEYBOARD_DEV_NAME, (__pCBK_t)key_msg_cb, 0, 0);
	prv_kernel.h_mouseGraber = esINPUT_LdevGrab(INPUT_LMOUSE_DEV_NAME, (__pCBK_t)mouse_msg_cb, 0, 0);
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
	prv_kernel.cedar_task_id = esKRNL_TCreate(cedar_msg_thread, (void *)&prv_kernel, 0x2000, (EPOS_curid << 8) | KRNL_priolevel3);
	DBG("%d", esKRNL_TCreate(test_thread, NULL, 0x4000, KRNL_priolevel2));
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

static void media_lcd_init(const RECT *rect_p, uint32_t pipe, uint32_t prio)
{
	__disp_layer_info_t     image_layer_info = {0};
	__disp_fb_t             image_fb_para = {0};
	RECT                    image_win;

	__u32 arg[3];

	if( rect_p == NULL )
		return ;

	image_fb_para.size.height      	= 0;                   // DONT'T CARE
	image_fb_para.size.width       	= 0;                   // DONT'T CARE
	image_fb_para.addr[0]          	= NULL;
	image_fb_para.format         	= DISP_FORMAT_RGB565;         // DONT'T CARE
	image_fb_para.seq     			= DISP_SEQ_ARGB;  	  // DONT'T CARE
	image_fb_para.mode      		= 0;                   // DONT'T CARE
	image_fb_para.br_swap       	= 0;                // DONT'T CARE
	image_fb_para.cs_mode 			= NULL;

	image_layer_info.mode			= DISP_LAYER_WORK_MODE_NORMAL;
    image_layer_info.pipe			= pipe;
    image_layer_info.prio			= prio;
    image_layer_info.alpha_en		= 0;
    image_layer_info.alpha_val		= 255;
    image_layer_info.ck_enable		= 0;
    image_layer_info.src_win.x      = 0;
	image_layer_info.src_win.y      = 0;
	image_layer_info.src_win.width  = rect_p->width ;
	image_layer_info.src_win.height = rect_p->height;
    image_layer_info.scn_win.x      = rect_p->x     ;
	image_layer_info.scn_win.y      = rect_p->y     ;
	image_layer_info.scn_win.width  = rect_p->width ;
	image_layer_info.scn_win.height = rect_p->height;
    image_layer_info.fb				= image_fb_para;

	arg[0] = DISP_LAYER_WORK_MODE_NORMAL;
	arg[1] = 0;
	arg[2] = 0;
	prv_media.h_media_lay = eLIBs_fioctrl( g_display.hdis, DISP_CMD_LAYER_REQUEST, 0, (void *)arg );

	if( prv_media.h_media_lay == NULL )
	{
		DBG("Error in applying for the video layer");
		goto error;
	}

	arg[0] = prv_media.h_media_lay;
	arg[1] = (__u32)&image_layer_info;
	arg[2] = 0;
	eLIBs_fioctrl( g_display.hdis, DISP_CMD_LAYER_SET_PARA, 0, (void *)arg );

	image_win.x      = rect_p->x;
    image_win.y      = rect_p->y;
    image_win.width  = rect_p->width ;
    image_win.height = rect_p->height;

	if(esMODS_MIoctrl(prv_media.robin_hced, CEDAR_CMD_SET_VID_LAYERHDL, 0, (void *)prv_media.h_media_lay) != EPDK_OK)
    {
        DBG("Fail in setting video layer handle to cedar!");
        goto error;
    }
    //set video window information to cedar
    if(esMODS_MIoctrl(prv_media.robin_hced, CEDAR_CMD_SET_VID_WINDOW, 0, &image_win) != EPDK_OK)
    {
        DBG("Fail in setting video window information to cedar!");
        goto error;
    }
	if(esMODS_MIoctrl(prv_media.robin_hced, CEDAR_CMD_SET_RESERVED_MEM_SIZE, 512 * 1024, NULL ) != EPDK_OK)
    {
		DBG("Error in set reserved memory !");
        goto error;
	}
	return ;

error:
	if( prv_media.h_media_lay != NULL )
	{
		arg[0] = prv_media.h_media_lay;
		arg[1] = 0;
		arg[2] = 0;
		eLIBs_fioctrl( g_display.hdis, DISP_CMD_LAYER_RELEASE, 0, (void *)arg );
		prv_media.h_media_lay = NULL;
	}
	return ;
}

static void media_test(char* path)
{
	__s32 ret;
	__cedar_media_file_inf*  file_info;

	file_info = (__cedar_media_file_inf*)esMEMS_Malloc(0, sizeof(__cedar_media_file_inf));

	eLIBs_strcpy(file_info->file_path, path);
	file_info->tag_inf_validflag = 0;

	/* set new media file to be played */
	ret = esMODS_MIoctrl( prv_media.robin_hced, CEDAR_CMD_SET_MEDIAFILE, 0, file_info );
	DBG("CEDAR_CMD_SET_MEDIAFILE:%d", ret);

	/* send play command */
	ret = esMODS_MIoctrl( prv_media.robin_hced, CEDAR_CMD_PLAY, 0, NULL );
	if( ret != EPDK_OK )
	{
		DBG("Fail in setting play cmd.%d", ret);
		return ;
	}
	else
	{
		DBG("play ok.%d", ret);
	}

	return;
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

static void test_thread(void *arg)
{
	ES_FILE *h_file;
	uint8_t head[32];
	esKRNL_TimeDly(500);
	h_file = eLIBs_fopen("D:\\test.mp4", "rb") ;
	if(h_file == 0)
	{
		DBG("test file cannot open");
	}
	else
	{
		eLIBs_fread(head, 1, sizeof(head), h_file) ;
		eLIBs_fclose(h_file);
		DBG("file head info:");
		dump(head, sizeof(head));
		media_test("D:\\test.mp4");
	}
	while(1)
	{
		esKRNL_TimeDly(500);
	}
}

static void port_thread(void *arg)
{
    __event_t *tmp;
    __u8 error;
	RECT rect;
	u8 *temp_data;
	int32_t rx_len;
	app_init();
    disp_lcd_init();
	rect.x      = 0;
	rect.y      = 0;
	rect.width  = g_display.width;
	rect.height = g_display.height;
	media_lcd_init(&rect, 1, 0xff);

    //disp_lcd_test();
    while(1)
    {
        tmp = (__event_t *)esKRNL_QPend( prv_kernel.psys_msg_queue, 0, &error);

        if( tmp!= NULL)
        {
            tmp->lock = 0;
            DBG("%d,%x,%x,%x", tmp->event_id, tmp->param1, tmp->param2, tmp->param3);
			if (tmp->event_id >= USER_MSG_ID_START)
			{
				if (tmp->event_id >= UART_MSG_ID_START)
				{
					switch (tmp->event_id)
					{
					case UART_MSG_INT_CALLBACK:
						temp_data = eLIBs_malloc(1024);
						do 
						{
							rx_len = eLIBs_fread(temp_data, 1024, 1, prv_kernel.pUart);
							if (rx_len > 0)
							{
								eLIBs_fwrite(temp_data, rx_len, 1, prv_kernel.pUart);
							}
						}
						while(rx_len > 0);
						eLIBs_free(temp_data);
						break;
					}
				}
			}
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