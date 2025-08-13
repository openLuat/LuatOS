#include "luat_base.h"
#include "luat_airlink.h"

#if defined(LUAT_USE_AIRLINK_EXEC_WLAN )
#include "luat_wlan.h"
#endif

// TODO 把wifi侧的实现, 也搬过来

extern luat_airlink_dev_info_t g_airlink_self_dev_info;

static AIRLINK_DEV_INFO_UPDATE_CB send_devinfo_update_evt = NULL;

#if defined(LUAT_USE_AIRLINK_EXEC_WLAN)
#if 0
void luat_airlink_devinfo_init(AIRLINK_DEV_INFO_UPDATE_CB cb) 
{
    
}
#endif
#endif
