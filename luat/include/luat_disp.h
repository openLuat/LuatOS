
#include "luat_base.h"

typedef struct luat_disp_conf
{
    uint32_t pinType; // I2C_SW = 1, I2C_HW = 2, SPI_SW_3PIN = 3, SPI_HW_4PIN = 4, P8080 = 5
    void* ptr;
    size_t w;
    size_t h;
    char* cname; // 控制器名称, 例如SSD1306
    uint8_t pin0;
    uint8_t pin1;
    uint8_t pin2;
    uint8_t pin3;
    uint8_t pin4;
    uint8_t pin5;
    uint8_t pin6;
    uint8_t pin7;
} luat_disp_conf_t;

int luat_disp_setup(luat_disp_conf_t *conf);

int luat_disp_close(luat_disp_conf_t *conf);
