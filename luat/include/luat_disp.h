
#include "luat_base.h"

typedef struct luat_disp_conf
{
    void* ptr;
    uint8_t swOrHw;
    size_t w;
    size_t h;
    char* cname; // 控制器名称, 例如SSD1306
} luat_disp_conf_t;

int luat_disp_setup(luat_disp_conf_t *conf);

int luat_disp_close(luat_disp_conf_t *conf);
