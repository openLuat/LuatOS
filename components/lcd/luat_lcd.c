#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "lcd"
#include "luat_log.h"

luat_color_t BACK_COLOR = WHITE, FORE_COLOR = BLACK;

#define LUAT_LCD_CONF_COUNT (1)
static luat_lcd_conf_t* confs[LUAT_LCD_CONF_COUNT] = {0};

luat_color_t color_swap(luat_color_t color) {
    luat_color_t tmp = (color >> 8) + ((color & 0xFF) << 8);
    return tmp;
}

void luat_lcd_execute_cmds(luat_lcd_conf_t* conf, uint32_t* cmds, uint32_t count) {
    uint32_t cmd = 0;
    for (size_t i = 0; i < count; i++)
    {
        cmd = cmds[i];
        switch(((cmd >> 16) & 0xFFFF)) {
            case 0x0000 :
                lcd_write_cmd(conf, (const uint8_t)(cmd & 0xFF));
                break;
            case 0x0001 :
                luat_timer_mdelay(cmd & 0xFF);
                break;
            case 0x0002 :
                lcd_write_cmd(conf, (const uint8_t)(cmd & 0xFF));
                break;
            case 0x0003 :
                lcd_write_data(conf, (const uint8_t)(cmd & 0xFF));
                break;
            default:
                break;
        }
    }
}


int lcd_write_cmd(luat_lcd_conf_t* conf, const uint8_t cmd){
    size_t len;
    luat_gpio_set(conf->pin_dc, Luat_GPIO_LOW);
#ifdef LUAT_LCD_CMD_DELAY_US
    if (conf->dc_delay_us){
    	luat_timer_us_delay(conf->dc_delay_us);
    }
#endif
    if (conf->port == LUAT_LCD_SPI_DEVICE){
        len = luat_spi_device_send((luat_spi_device_t*)(conf->lcd_spi_device),  (const char*)&cmd, 1);
    }else{
        len = luat_spi_send(conf->port, (const char*)&cmd, 1);
    }
    luat_gpio_set(conf->pin_dc, Luat_GPIO_HIGH);
    if (len != 1){
        LLOGI("lcd_write_cmd error. %d", len);
        return -1;
    }else{
        #ifdef LUAT_LCD_CMD_DELAY_US
        if (conf->dc_delay_us){
        	luat_timer_us_delay(conf->dc_delay_us);
        }
        #endif
        return 0;
    }
}

int lcd_write_data(luat_lcd_conf_t* conf, const uint8_t data){
    size_t len;
    if (conf->port == LUAT_LCD_SPI_DEVICE){
        len = luat_spi_device_send((luat_spi_device_t*)(conf->lcd_spi_device),  (const char*)&data, 1);
    }else{
        len = luat_spi_send(conf->port,  (const char*)&data, 1);
    }
    if (len != 1){
        LLOGI("lcd_write_data error. %d", len);
        return -1;
    }else{
        return 0;
    }
}

luat_lcd_conf_t* luat_lcd_get_default(void) {
    for (size_t i = 0; i < LUAT_LCD_CONF_COUNT; i++){
        if (confs[i] != NULL) {
            return confs[i];
        }
    }
    return NULL;
}

const char* luat_lcd_name(luat_lcd_conf_t* conf) {
    return conf->opts->name;
}

int luat_lcd_init(luat_lcd_conf_t* conf) {
	conf->is_init_done = 0;
    int ret = conf->opts->init(conf);
    if (ret == 0) {
    	conf->is_init_done = 1;
        for (size_t i = 0; i < LUAT_LCD_CONF_COUNT; i++)
        {
            if (confs[i] == NULL) {
                confs[i] = conf;
                break;
            }
        }
    }
    return ret;
}

int luat_lcd_close(luat_lcd_conf_t* conf) {
    if (conf->pin_pwr != 255)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    return 0;
}

int luat_lcd_display_off(luat_lcd_conf_t* conf) {
    if (conf->pin_pwr != 255)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    lcd_write_cmd(conf,0x28);
    return 0;
}

int luat_lcd_display_on(luat_lcd_conf_t* conf) {
    if (conf->pin_pwr != 255)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    lcd_write_cmd(conf,0x29);
    return 0;
}

int luat_lcd_sleep(luat_lcd_conf_t* conf) {
    if (conf->pin_pwr != 255)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_timer_mdelay(5);
    lcd_write_cmd(conf,0x10);
    return 0;
}

int luat_lcd_wakeup(luat_lcd_conf_t* conf) {
    if (conf->pin_pwr != 255)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    luat_timer_mdelay(5);
    lcd_write_cmd(conf,0x11);
    return 0;
}

int luat_lcd_inv_off(luat_lcd_conf_t* conf) {
    lcd_write_cmd(conf,0x20);
    return 0;
}

int luat_lcd_inv_on(luat_lcd_conf_t* conf) {
    lcd_write_cmd(conf,0x21);
    return 0;
}

int luat_lcd_set_address(luat_lcd_conf_t* conf,uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2) {
    lcd_write_cmd(conf,0x2a);
    lcd_write_data(conf,(x1+conf->xoffset)>>8);
    lcd_write_data(conf,x1+conf->xoffset);
    lcd_write_data(conf,(x2+conf->xoffset)>>8);
    lcd_write_data(conf,x2+conf->xoffset);
    lcd_write_cmd(conf,0x2b);
    lcd_write_data(conf,(y1+conf->yoffset)>>8);
    lcd_write_data(conf,y1+conf->yoffset);
    lcd_write_data(conf,(y2+conf->yoffset)>>8);
    lcd_write_data(conf,y2+conf->yoffset);
    lcd_write_cmd(conf,0x2C);
    return 0;
}

int luat_lcd_set_color(luat_color_t back, luat_color_t fore){
    BACK_COLOR = back;
    FORE_COLOR = fore;
    return 0;
}

#ifndef LUAT_USE_LCD_CUSTOM_DRAW
int luat_lcd_flush(luat_lcd_conf_t* conf) {
    if (conf->buff == NULL) {
        return 0;
    }
    //LLOGD("luat_lcd_flush range %d %d", conf->flush_y_min, conf->flush_y_max);
    if (conf->flush_y_max < conf->flush_y_min) {
        // 没有需要刷新的内容,直接跳过
        //LLOGD("luat_lcd_flush no need");
        return 0;
    }
    uint32_t size = conf->w * (conf->flush_y_max - conf->flush_y_min + 1) * 2;
    luat_lcd_set_address(conf, 0, conf->flush_y_min, conf->w - 1, conf->flush_y_max);
    const char* tmp = (const char*)(conf->buff + conf->flush_y_min * conf->w);
	if (conf->port == LUAT_LCD_SPI_DEVICE){
		luat_spi_device_send((luat_spi_device_t*)(conf->lcd_spi_device), tmp, size);
	}else{
		luat_spi_send(conf->port, tmp, size);
	}

    // 重置为不需要刷新的状态
    conf->flush_y_max = 0;
    conf->flush_y_min = conf->h;
    
    return 0;
}

int luat_lcd_draw(luat_lcd_conf_t* conf, uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, luat_color_t* color) {
    // 直接刷屏模式
    if (conf->buff == NULL) {
        uint32_t size = (x2 - x1 + 1) * (y2 - y1 + 1) * 2;
        luat_lcd_set_address(conf, x1, y1, x2, y2);
	    if (conf->port == LUAT_LCD_SPI_DEVICE){
		    luat_spi_device_send((luat_spi_device_t*)(conf->lcd_spi_device), (const char*)color, size);
	    }else{
		    luat_spi_send(conf->port, (const char*)color, size);
	    }
        return 0;
    }
    // buff模式
    if (x1 > conf->w || y1 > conf->h) {
        LLOGE("out of lcd range");
        return -1;
    }
    uint16_t x_end = x2 > conf->w?conf->w:x2;
    uint16_t y_end = y2 > conf->h?conf->h:y2;
    luat_color_t* dst = (conf->buff + x1 + conf->w * y1);
    luat_color_t* src = (color);
    size_t lsize = (x_end - x1 + 1);
    for (size_t i = y1; i <= y_end; i++) {
        memcpy(dst, src, lsize * sizeof(luat_color_t));
        dst += conf->w;  // 移动到下一行
        src += lsize;    // 移动数据
        if (x2 > conf->w){
            src+=x2 - conf->w;
        }
    }
    // 存储需要刷新的区域
    if (y1 < conf->flush_y_min)
        conf->flush_y_min = y1;
    if (y_end > conf->flush_y_max)
        conf->flush_y_max = y_end;
    return 0;
}
#endif

int luat_lcd_draw_point(luat_lcd_conf_t* conf, uint16_t x, uint16_t y, luat_color_t color) {
    // 注意, 这里需要把颜色swap了
    luat_color_t tmp = color_swap(color);
    return luat_lcd_draw(conf, x, y, x, y, &tmp);
}

int luat_lcd_clear(luat_lcd_conf_t* conf, luat_color_t color){
    luat_lcd_draw_fill(conf, 0, 0, conf->w, conf->h, color);
    return 0;
}

int luat_lcd_draw_fill(luat_lcd_conf_t* conf,uint16_t x1,uint16_t y1,uint16_t x2,uint16_t y2, luat_color_t color) {          
	uint16_t i;
	for(i=y1;i<=y2;i++)
	{
		luat_lcd_draw_line(conf, x1, i, x2, i, color);
	}
    return 0;			  	    
}

int luat_lcd_draw_vline(luat_lcd_conf_t* conf, uint16_t x, uint16_t y,uint16_t h, luat_color_t color) {
    if (h==0) return 0;
    return luat_lcd_draw_line(conf, x, y, x, y + h - 1, color);
}

int luat_lcd_draw_hline(luat_lcd_conf_t* conf, uint16_t x, uint16_t y,uint16_t w, luat_color_t color) {
    if (w==0) return 0;
    return luat_lcd_draw_line(conf, x, y, x + w - 1, y, color);
}

int luat_lcd_draw_line(luat_lcd_conf_t* conf,uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2,luat_color_t color) {
    uint16_t t;
    uint32_t i = 0;
    int xerr = 0, yerr = 0, delta_x, delta_y, distance;
    int incx, incy, row, col;
    if (x1 == x2 || y1 == y2) // 直线
    {
        size_t dots = (x2 - x1 + 1) * (y2 - y1 + 1);//点数量
        luat_color_t* line_buf = (luat_color_t*) luat_heap_malloc(dots * sizeof(luat_color_t));
        // 颜色swap
        luat_color_t tmp = color_swap(color);
        if (line_buf) {
            for (i = 0; i < dots; i++)
            {
                line_buf[i] = tmp;
            }
            luat_lcd_draw(conf, x1, y1, x2, y2, line_buf);
            luat_heap_free(line_buf);
            return 0;
        }
    }

    delta_x = x2 - x1;
    delta_y = y2 - y1;
    row = x1;
    col = y1;
    if (delta_x > 0)incx = 1;
    else if (delta_x == 0)incx = 0;
    else
    {
        incx = -1;
        delta_x = -delta_x;
    }
    if (delta_y > 0)incy = 1;
    else if (delta_y == 0)incy = 0;
    else
    {
        incy = -1;
        delta_y = -delta_y;
    }
    if (delta_x > delta_y)distance = delta_x;
    else distance = delta_y;
    for (t = 0; t <= distance + 1; t++)
    {
        luat_lcd_draw_point(conf,row, col,color);
        xerr += delta_x ;
        yerr += delta_y ;
        if (xerr > distance)
        {
            xerr -= distance;
            row += incx;
        }
        if (yerr > distance)
        {
            yerr -= distance;
            col += incy;
        }
    }
    return 0;
}

int luat_lcd_draw_rectangle(luat_lcd_conf_t* conf,uint16_t x1, uint16_t y1, uint16_t x2, uint16_t y2, luat_color_t color){
    luat_lcd_draw_line(conf,x1, y1, x2, y1, color);
    luat_lcd_draw_line(conf,x1, y1, x1, y2, color);
    luat_lcd_draw_line(conf,x1, y2, x2, y2, color);
    luat_lcd_draw_line(conf,x2, y1, x2, y2, color);
    return 0;
}

int luat_lcd_draw_circle(luat_lcd_conf_t* conf,uint16_t x0, uint16_t y0, uint8_t r, luat_color_t color){
    int a, b;
    int di;
    a = 0;
    b = r;
    di = 3 - (r << 1);
    while (a <= b)
    {
        luat_lcd_draw_point(conf,x0 - b, y0 - a,color);
        luat_lcd_draw_point(conf,x0 + b, y0 - a,color);
        luat_lcd_draw_point(conf,x0 - a, y0 + b,color);
        luat_lcd_draw_point(conf,x0 - b, y0 - a,color);
        luat_lcd_draw_point(conf,x0 - a, y0 - b,color);
        luat_lcd_draw_point(conf,x0 + b, y0 + a,color);
        luat_lcd_draw_point(conf,x0 + a, y0 - b,color);
        luat_lcd_draw_point(conf,x0 + a, y0 + b,color);
        luat_lcd_draw_point(conf,x0 - b, y0 + a,color);
        a++;
        //Bresenham
        if (di < 0)di += 4 * a + 6;
        else
        {
            di += 10 + 4 * (a - b);
            b--;
        }
        luat_lcd_draw_point(conf,x0 + a, y0 + b,color);
    }
    return 0;
}

