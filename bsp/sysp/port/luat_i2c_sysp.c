#include "luat_base.h"
#include "luat_i2c.h"

int luat_i2c_exist(int id) {
    return 0;
}
int luat_i2c_setup(int id, int speed) {
    return 0;
}
int luat_i2c_close(int id) {
    return 0;
}
int luat_i2c_send(int id, int addr, void* buff, size_t len, uint8_t stop) {
    return 0;
}
int luat_i2c_recv(int id, int addr, void* buff, size_t len) {
    return 0;
}
