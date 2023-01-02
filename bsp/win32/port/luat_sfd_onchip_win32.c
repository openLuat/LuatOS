#include "luat_base.h"
#include "luat_sfd.h"

int sfd_onchip_init (void* userdata) {
    return -1;
}
int sfd_onchip_status (void* userdata) {
    return -1;
}
int sfd_onchip_read (void* userdata, char* buff, size_t offset, size_t len) {
    return -1;
}
int sfd_onchip_write (void* userdata, const char* buff, size_t offset, size_t len) {
    return -1;
}
int sfd_onchip_erase (void* userdata, size_t offset, size_t len) {
    return -1;
}
int sfd_onchip_ioctl (void* userdata, size_t cmd, void* buff) {
    return -1;
}
