#ifndef LUAT_WS2812_H
#define LUAT_WS2812_H

#define LUAT_WS2812_MODE_GPIO 1
#define LUAT_WS2812_MODE_PWM  2
#define LUAT_WS2812_MODE_SPI  3
#define LUAT_WS2812_MODE_RMT  4
#define LUAT_WS2812_MODE_HW   5

typedef struct luat_ws2812_color
{
    // 这里需要用GRB形式排列
    // 但API接口用RGB就可以了
    uint8_t G;
    uint8_t R;
    uint8_t B;
}luat_ws2812_color_t;


typedef struct luat_ws2812
{
    uint8_t mode;
    uint16_t count;
    uint8_t id;
    void* userdata;
    int args[8];
    luat_ws2812_color_t colors[1];
}luat_ws2812_t;

typedef int (*ws2812_send_opt_impl)(luat_ws2812_t* ctx);

typedef struct luat_ws2812_opt
{
    ws2812_send_opt_impl opt;
    uint8_t mode;
}luat_ws2812_opt_t;


int luat_ws2812_send(luat_ws2812_t* ctx);

int luat_ws2812_set_opt(uint8_t mode, ws2812_send_opt_impl opt);

#endif
