
#include "luat_base.h"
#include "u8g2.h"

typedef struct luat_u8g2_custom {
    size_t init_cmd_count;
    uint32_t *initcmd; // 实际命令长度与init_cmd_count相同
}luat_u8g2_custom_t;

typedef struct luat_u8g2_conf
{
    size_t w;
    size_t h;
    int lua_ref;
    char* cname; // 控制器名称, 例如SSD1306
    u8g2_cb_t* direction;//方向 
    u8g2_t u8g2;
    uint16_t sleepcmd;
    uint16_t wakecmd;
    uint8_t* buff_ptr;
    void* userdata;
} luat_u8g2_conf_t;

int luat_u8g2_setup(luat_u8g2_conf_t *conf);

int luat_u8g2_close(luat_u8g2_conf_t *conf);

