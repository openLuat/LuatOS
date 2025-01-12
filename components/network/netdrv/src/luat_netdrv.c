#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_ch390h.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

static luat_netdrv_t* drvs[NW_ADAPTER_QTY];

luat_netdrv_t* luat_netdrv_setup(luat_netdrv_conf_t *conf) {
    if (conf->id < 0 || conf->id >= NW_ADAPTER_QTY) {
        return NULL;
    }
    if (drvs[conf->id] == NULL) {
        // 注册新的设备?
        if (conf->impl == 1) { // CH390H
            drvs[conf->id] = luat_netdrv_ch390h_setup(conf);
            return drvs[conf->id];
        }
    }
    else {
        if (drvs[conf->id]->boot) {
            drvs[conf->id]->boot(NULL);
        }
    }
    return NULL;
}

int luat_netdrv_dhcp(int32_t id, int32_t enable) {
    if (id < 0 || id >= NW_ADAPTER_QTY) {
        return -1;
    }
    if (drvs[id] == NULL) {
        return -1;
    }
    if (drvs[id]->dhcp == NULL) {
        LLOGW("该netdrv不支持设置dhcp开关");
        return -1;
    }
    return drvs[id]->dhcp(drvs[id]->userdata, enable);
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

int luat_netdrv_mac(int32_t id, const char* new, char* old) {
    if (id < 0 || id >= NW_ADAPTER_QTY) {
        return -1;
    }
    if (drvs[id] == NULL || drvs[id]->netif == NULL) {
        return -1;
    }
    memcpy(old, drvs[id]->netif->hwaddr, 6);
    memcpy(drvs[id]->netif->hwaddr, new, 6);
    return 0;
}
