
#include "luat_base.h"
#include "u8g2.h"

typedef struct luat_u8g2_conf
{
    size_t w;
    size_t h;
    char* cname; // 控制器名称, 例如SSD1306
    void* ptr;
    const u8g2_cb_t* direction;//方向 
} luat_u8g2_conf_t;

int luat_u8g2_setup(luat_u8g2_conf_t *conf);

int luat_u8g2_close(luat_u8g2_conf_t *conf);

