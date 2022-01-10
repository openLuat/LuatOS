
#include "luat_base.h"
#include "luat_camera.h"
#include "luat_i2c.h"



int luat_camera_init(luat_camera_conf* conf) {
    if (!strcmp("gc032a", conf->type_name)) {
        
    }
}

int luat_camera_close(int id) {
    return 0; // 不支持关闭
}
