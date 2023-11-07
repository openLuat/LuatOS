#include "luat_base.h"
#include "luat_mobile.h"


int luat_mobile_get_isp_from_plmn(uint16_t mcc, uint8_t mnc)
{
	uint8_t cmcc[] = {0, 2, 4, 7, 8, 13};
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
