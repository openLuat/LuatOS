
#include "luat_base.h"
#include "luat_sys.h"
#include "rtthread.h"


// fix for 
#ifdef RT_USING_HWCRYPTO
#include <hwcrypto.h>
RT_WEAK struct rt_hwcrypto_device *rt_hwcrypto_dev_dufault(void) {
    return rt_hwcrypto_dev_default();
}
#endif

RT_WEAK void luat_fs_init() {}
