#include "luat_base.h"
#include "luat_mobile.h"
#include "luat_rtos.h"
#include "luat_fs.h"
#if defined(LUAT_EC7XX_CSDK) || defined(CHIP_EC618) || defined(__AIR105_BSP__)
#include "bsp_common.h"
#endif
#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif

#define LUAT_LOG_TAG "mobile"
#include "luat_log.h"

typedef struct
{
	llist_head node;
	PV_Union plmn;
	uint8_t ip_type;
	uint8_t protocol;
	uint8_t name_len;
	uint8_t user_len;
	uint8_t password_len;
	uint8_t unused[3];
	char data[0];
}apn_node_t;


typedef struct
{
	llist_head dynamic_list;
}auto_apn_ctrl_t;

static auto_apn_ctrl_t luat_auto_apn;

void luat_mobile_init_auto_apn_by_plmn(void)
{
	luat_mobile_init_auto_apn();
	INIT_LLIST_HEAD(&luat_auto_apn.dynamic_list);
}

static int luat_mobile_find_apn(void *node, void *param)
{
	apn_node_t *apn = (apn_node_t *)node;
	if (apn->plmn.p == param)
	{
		return LIST_FIND;
	}
	return LIST_PASS;
}

void luat_mobile_add_auto_apn_item(uint16_t mcc, uint16_t mnc, uint8_t ip_type, uint8_t protocol, char *name, uint8_t name_len, char *user, uint8_t user_len, char *password, uint8_t password_len, uint8_t task_safe)
{
	apn_node_t *apn;
	if (task_safe)
	{
		luat_rtos_task_suspend_all();
	}
	if (!luat_auto_apn.dynamic_list.next)
	{
		luat_mobile_init_auto_apn_by_plmn();
	}
	PV_Union plmn;
	plmn.u16[1] = mcc;
	plmn.u16[0] = mnc;
	apn = llist_traversal(&luat_auto_apn.dynamic_list, luat_mobile_find_apn, plmn.p);
	if (apn)
	{
		llist_del(&apn->node);
		free(apn);
	}
	apn = calloc(1, sizeof(apn_node_t) + name_len + user_len + password_len);
	apn->plmn.u16[1] = mcc;
	apn->plmn.u16[0] = mnc;
	apn->ip_type = ip_type;
	apn->protocol = protocol;
	apn->name_len = name_len;
	apn->user_len = user_len;
	apn->password_len = password_len;
	memcpy(apn->data, name, name_len);
	if (user && user_len)
	{
		memcpy(apn->data + name_len, user, user_len);
	}
	if (password && password_len)
	{
		memcpy(apn->data + name_len + user_len, password, password_len);
	}
	llist_add_tail(&apn->node, &luat_auto_apn.dynamic_list);
	if (task_safe)
	{
		luat_rtos_task_resume_all();
	}
}

int luat_mobile_find_apn_by_mcc_mnc(uint16_t mcc, uint16_t mnc, apn_info_t *info)
{
	if (!luat_auto_apn.dynamic_list.next)
	{
		LLOGE("no apn table");
		return -1;
	}
	apn_node_t *apn;
	PV_Union plmn;
	plmn.u16[1] = mcc;
	plmn.u16[0] = mnc;
	int result;
	luat_rtos_task_suspend_all();
	apn = llist_traversal(&luat_auto_apn.dynamic_list, luat_mobile_find_apn, plmn.p);

	if (apn)
	{
		info->data = apn->data;
		info->ip_type = apn->ip_type;
		info->protocol = apn->protocol;
		info->name_len = apn->name_len;
		info->user_len = apn->user_len;
		info->password_len = apn->password_len;
		result = 0;
	}
	else
	{
		result = -1;
	}
	luat_rtos_task_resume_all();
	return result;
}

LUAT_WEAK int get_apn_info_by_static(uint16_t mcc, uint16_t mnc, apn_info_t *info)
{
	return -1;
}

void luat_mobile_print_apn_by_mcc_mnc(uint16_t mcc, uint16_t mnc)
{
	apn_info_t info;
	if(luat_mobile_find_apn_by_mcc_mnc(mcc, mnc, &info))
	{
		if (get_apn_info_by_static(mcc, mnc, &info))
		{
			LLOGD("mcc 0x%x, mnc 0x%x not find");
			return;
		}
		if (!info.data)
		{
			LLOGD("mcc 0x%x, mnc 0x%x no need apn");
			return;
		}
	}

	LLOGD("mcc 0x%x, mnc 0x%x, ip_type %d, auth_type %d, apn %dbyte %.*s, user %dbyte %.*s, password %dbyte %.*s",
			mcc, mnc, info.ip_type, info.protocol, info.name_len, info.name_len, info.data,
			info.user_len, info.user_len, info.user_len?(info.data + info.name_len):NULL,
			info.password_len, info.password_len, info.password_len?(info.data + info.name_len + info.user_len):NULL);

}

int luat_mobile_get_isp_from_plmn(uint16_t mcc, uint8_t mnc)
{
	uint8_t cmcc[] = {0, 2, 4, 7, 8, 13, 23, 24};
	uint8_t cucc[] = {1, 6, 9, 10};
	uint8_t ctcc[] = {3, 5, 11, 12};
	if (mcc != 460) return -1;
	uint8_t i;
	for(i = 0; i < sizeof(cmcc); i++)
	{
		if (mnc == cmcc[i])
		{
			return LUAT_MOBILE_ISP_CMCC;
		}
	}
	for(i = 0; i < sizeof(ctcc); i++)
	{
		if (mnc == ctcc[i])
		{
			return LUAT_MOBILE_ISP_CTCC;
		}
	}
	for(i = 0; i < sizeof(cucc); i++)
	{
		if (mnc == cucc[i])
		{
			return LUAT_MOBILE_ISP_CUCC;
		}
	}
	if (mnc == 15) return LUAT_MOBILE_ISP_CRCC;
	return LUAT_MOBILE_ISP_UNKNOW;
}

int luat_mobile_get_plmn_from_imsi(char *imsi, uint16_t *mcc, uint8_t *mnc)
{
	if (!imsi) return -1;
	uint16_t temp = imsi[0] - '0';
	temp = (temp  * 10) + imsi[1] - '0';
	temp = (temp  * 10) + imsi[2] - '0';
	*mcc = temp;
	temp = imsi[3] - '0';
	temp = (temp  * 10) + imsi[4] - '0';
	*mnc = temp;
	return 0;
}
