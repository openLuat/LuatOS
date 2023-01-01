
#include "luat_base.h"

#include "luat_sfd.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "sfd"
#include "luat_log.h"

int luat_sfd_status (sfd_drv_t* drv) {
    if (drv == NULL)
        return -1;
    return drv->opts->status(drv->userdata);
}

int luat_sfd_read (sfd_drv_t* drv, char* buff, size_t offset, size_t len) {
    if (drv == NULL)
        return -1;
    return drv->opts->read(drv->userdata, buff, offset, len);
}

int luat_sfd_write (sfd_drv_t* drv, const char* buff, size_t offset, size_t len) {
    if (drv == NULL)
        return -1;
    return drv->opts->write(drv->userdata, buff, offset, len);
}

int luat_sfd_erase (sfd_drv_t* drv, size_t offset, size_t len) {
    if (drv == NULL)
        return -1;
    return drv->opts->erase(drv->userdata, offset, len);
}

int luat_sfd_ioctl (sfd_drv_t* drv, size_t cmd, void* buff) {
    if (drv == NULL)
        return -1;
    return drv->opts->ioctl(drv->userdata, cmd, buff);
}
