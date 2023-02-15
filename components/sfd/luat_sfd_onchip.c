
#include "luat_base.h"

#include "luat_sfd.h"
#include "luat_malloc.h"

const sdf_opts_t sfd_onchip_opts = {
    .initialize = sfd_onchip_init,
    .status = sfd_onchip_status,
    .read = sfd_onchip_read,
    .write = sfd_onchip_write,
    .erase = sfd_onchip_erase,
    .ioctl = sfd_onchip_ioctl,
};

sfd_drv_t* sfd_onchip;

int luat_sfd_onchip_init(void) {
    if (sfd_onchip != NULL) {
        return 0;
    }
    sfd_onchip = luat_heap_malloc(sizeof(sfd_drv_t));
    if (sfd_onchip == NULL) {
        return -1;
    }
    sfd_onchip_t * onchip = luat_heap_malloc(sizeof(sfd_onchip_t));
    if (onchip == NULL) {
        luat_heap_free(sfd_onchip);
        sfd_onchip = NULL;
        return -2;
    }
    memset(sfd_onchip, 0, sizeof(sfd_drv_t));
    sfd_onchip->opts = &sfd_onchip_opts;
    sfd_onchip->type = 2;
    sfd_onchip->userdata = onchip;
    int ret = sfd_onchip_init(onchip);
    if (ret != 0) {
        luat_heap_free(onchip);
        luat_heap_free(sfd_onchip);
        sfd_onchip = NULL;
        return -3;
    }
    return ret;
}
