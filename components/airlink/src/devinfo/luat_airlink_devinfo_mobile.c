#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_rtos.h"

#if defined(LUAT_USE_AIRLINK_EXEC_MOBILE)
#include "luat_mobile.h"
#endif

#define LUAT_LOG_TAG "airlink.mobile"
#include "luat_log.h"

extern luat_airlink_dev_info_t g_airlink_self_dev_info;

static AIRLINK_DEV_INFO_UPDATE_CB send_devinfo_update_evt = NULL;

#if defined(LUAT_USE_AIRLINK_EXEC_MOBILE)
extern luat_airlink_mobile_evt_cb g_airlink_mobile_evt_cb;

static int mobile_evt_handler(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status, void* ptr) {
    // luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)basic_info;
    luat_airlink_dev_info_t *devinfo = &g_airlink_self_dev_info;
	// LLOGD("mobile_evt_handler event:%d, index:%d, status:%d", event, index, status);
	switch(event)
	{
	case LUAT_MOBILE_EVENT_CFUN:
		break;
	case LUAT_MOBILE_EVENT_SIM:
        LLOGD("SIM_IND -> status %d", status);
        devinfo->cat1.sim_state = status;
        switch (status)
        {
        case LUAT_MOBILE_SIM_READY:
            luat_mobile_get_iccid(0, (char*)devinfo->cat1.iccid, 20);
            luat_mobile_get_imsi(0, (char*)devinfo->cat1.imsi, 16);
            LLOGD("SIM_READY -> ICCID %s", devinfo->cat1.iccid);
            LLOGD("SIM_READY -> IMSI %s", devinfo->cat1.imsi);
            send_devinfo_update_evt();
            // TODO 发送SIM_STATE消息
            break;
        case LUAT_MOBILE_NO_SIM:
            memset(devinfo->cat1.iccid, 0, 20);
            memset(devinfo->cat1.imsi, 0, 16);
            send_devinfo_update_evt();
            // TODO 发送SIM_STATE消息
            break;
        case LUAT_MOBILE_SIM_NEED_PIN:
            break;
        case LUAT_MOBILE_SIM_NUMBER:
            break;
        case LUAT_MOBILE_SIM_WC:
            break;
        default:
            break;
        }
		break;
	case LUAT_MOBILE_EVENT_REGISTER_STATUS:
		break;
	case LUAT_MOBILE_EVENT_CELL_INFO:
        switch (status)
        {
        case LUAT_MOBILE_CELL_INFO_UPDATE:
		    break;
        case LUAT_MOBILE_SERVICE_CELL_UPDATE:
        default:
            break;
        }
		break;
	case LUAT_MOBILE_EVENT_PDP:
		LLOGD("cid%d, state%d", index, status);
		break;
	case LUAT_MOBILE_EVENT_NETIF:
		switch (status)
		{
		case LUAT_MOBILE_NETIF_LINK_ON: {
            devinfo->cat1.cat_state = 1;
            send_devinfo_update_evt();
            LLOGD("NETIF_LINK_ON -> IP_READY cat1.cat_state %d ipv4 %d.%d.%d.%d", devinfo->cat1.cat_state, devinfo->cat1.ipv4[0], devinfo->cat1.ipv4[1], devinfo->cat1.ipv4[2], devinfo->cat1.ipv4[3]);
			break;
        }
        case LUAT_MOBILE_NETIF_LINK_OFF:
            devinfo->cat1.cat_state = 0;
            send_devinfo_update_evt();
            LLOGD("NETIF_LINK_OFF -> IP_LOSE cat1.cat_state %d", devinfo->cat1.cat_state); 
            break;
		default:
			break;
		}
		break;
	case LUAT_MOBILE_EVENT_TIME_SYNC:
		break;
	case LUAT_MOBILE_EVENT_CSCON:
		break;
	case LUAT_MOBILE_EVENT_BEARER:
		LLOGD("bearer act %d, result %d",status, index);
		break;
	case LUAT_MOBILE_EVENT_SMS:
		switch(status)
		{
		case LUAT_MOBILE_SMS_READY:
			LLOGI("sim%d sms ready", index);
			break;
		case LUAT_MOBILE_NEW_SMS:
			break;
		case LUAT_MOBILE_SMS_SEND_DONE:
			break;
		case LUAT_MOBILE_SMS_ACK:
			break;
		}
		break;
	case LUAT_MOBILE_EVENT_IMS_REGISTER_STATUS:
        LLOGD("ims reg state %d", status);
		break;
    case LUAT_MOBILE_EVENT_CC:
        LLOGD("LUAT_MOBILE_EVENT_CC status %d",status);
        switch(status){
        case LUAT_MOBILE_CC_READY:
            LLOGD("LUAT_MOBILE_CC_READY");
            break;
        case LUAT_MOBILE_CC_INCOMINGCALL:
            break;
        case LUAT_MOBILE_CC_CALL_NUMBER:
            // lua_pushstring(L, "CC_IND");
            // lua_pushstring(L, "CALL_NUMBER");
            // lua_call(L, 2, 0);
            break;
        case LUAT_MOBILE_CC_CONNECTED_NUMBER:
            // lua_pushstring(L, "CC_IND");
            // lua_pushstring(L, "CONNECTED_NUMBER");
            // lua_call(L, 2, 0);
            break;
        case LUAT_MOBILE_CC_CONNECTED:
            break;
        case LUAT_MOBILE_CC_DISCONNECTED:
            break;
        case LUAT_MOBILE_CC_SPEECH_START:
            break;
        case LUAT_MOBILE_CC_MAKE_CALL_OK:
            break;
        case LUAT_MOBILE_CC_MAKE_CALL_FAILED:
            break;
        case LUAT_MOBILE_CC_ANSWER_CALL_DONE:
            break;
        case LUAT_MOBILE_CC_HANGUP_CALL_DONE:
            break;
        case LUAT_MOBILE_CC_LIST_CALL_RESULT:
            break;
        case LUAT_MOBILE_CC_PLAY:// 最先
            break;
        }
        break;
	default:
		break;
	}
    send_devinfo_update_evt();
    return 0;
}

void luat_airlink_devinfo_init(AIRLINK_DEV_INFO_UPDATE_CB cb) 
{
    send_devinfo_update_evt = cb;
    g_airlink_self_dev_info.tp = 0x02;
    uint32_t fw_version = 3;
    memcpy(g_airlink_self_dev_info.cat1.version, &fw_version, sizeof(uint32_t));   // 版本
    luat_mobile_get_imei(0, g_airlink_self_dev_info.cat1.imei, 16);                // IMEI
    g_airlink_mobile_evt_cb = mobile_evt_handler;
}
#endif
