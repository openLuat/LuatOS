#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"

static luat_netdrv_t* drvs[NW_ADAPTER_QTY];

luat_netdrv_t* luat_netdrv_setup(luat_netdrv_conf_t *conf) {
    if (conf->id < 0 || conf->id >= NW_ADAPTER_QTY) {
        return NULL;
    }
    if (drvs[conf->id] == NULL) {
        // 注册新的设备?
    }
    else {
        drvs[conf->id]->boot(NULL);
    }
    return NULL;
}

int luat_netdrv_dhcp(int32_t id, int32_t enable) {
    return -1;
}

int luat_netdrv_ready(int32_t id) {
    if (drvs[id] == NULL) {
        return -1;
    }
    return drvs[id]->ready(drvs[id]->userdata);
}

int luat_netdrv_register(int32_t id, luat_netdrv_t* drv) {
    if (drvs[id] != NULL) {
        return -1;
    }
    drvs[id] = drv;
    return 0;
}
