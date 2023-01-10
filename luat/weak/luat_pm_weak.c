#include "luat_base.h"
#include "luat_pm.h"
LUAT_WEAK int luat_pm_power_ctrl(int id, uint8_t onoff)
{
	return -1;
}

LUAT_WEAK int luat_pm_get_poweron_reason(void)
{
	return 4;
}
