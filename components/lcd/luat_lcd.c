#include "luat_base.h"
#include "luat_lcd.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_mem.h"
#include "luat_rtos.h"

#define LUAT_LOG_TAG "lcd"
#include "luat_log.h"

luat_color_t BACK_COLOR = LCD_WHITE, FORE_COLOR = LCD_BLACK;

static luat_lcd_conf_t* lcd_confs[LUAT_LCD_CONF_COUNT] = {0};

void luat_lcd_execute_cmds(luat_lcd_conf_t* conf) {
    uint16_t cmd = 0,cmd_len = 0;
    uint8_t cmd_send = 0;
    uint8_t cmds[32]={0};
    for (size_t i = 0; i < conf->opts->init_cmds_len; i++){
        cmd = conf->opts->init_cmds[i];
        switch(((cmd >> 8) & 0xFF)) {
            case 0x0000:
            case 0x0002:
                if (i!=0){
                    if (cmd_len){
                        lcd_write_cmd_data(conf,cmd_send, cmds, cmd_len);
                    }else{
                        lcd_write_cmd_data(conf,cmd_send, NULL, 0);
                    }
                }
                cmd_send = (uint8_t)(cmd & 0xFF);
                cmd_len = 0;
                break;
            case 0x0001:
                luat_rtos_task_sleep(cmd & 0xFF);
                break;
            case 0x0003:
                cmds[cmd_len]= (uint8_t)(cmd & 0xFF);
                cmd_len++;
                break;
            default:
                break;
        }
        if (i==conf->opts->init_cmds_len-1){
            if (cmd_len){
                lcd_write_cmd_data(conf,cmd_send, cmds, cmd_len);
            }else{
                lcd_write_cmd_data(conf,cmd_send, NULL, 0);
            }
        }
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

int lcd_write_cmd_data(luat_lcd_conf_t* conf,const uint8_t cmd, const uint8_t *data, uint8_t data_len){
    if (conf->opts->write_cmd_data){
        return conf->opts->write_cmd_data(conf,cmd,data,data_len);
    }
    size_t len;
    if (conf->interface_mode==LUAT_LCD_IM_4_WIRE_8_BIT_INTERFACE_I || conf->interface_mode==LUAT_LCD_IM_4_WIRE_8_BIT_INTERFACE_II){
        luat_gpio_set(conf->pin_dc, Luat_GPIO_LOW);
    }
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
    if (conf->interface_mode==LUAT_LCD_IM_4_WIRE_8_BIT_INTERFACE_I || conf->interface_mode==LUAT_LCD_IM_4_WIRE_8_BIT_INTERFACE_II){
        luat_gpio_set(conf->pin_dc, Luat_GPIO_HIGH);
    }
    if (len != 1){
        LLOGI("lcd_write_cmd error. %d", len);
        return -1;
    }else{
        #ifdef LUAT_LCD_CMD_DELAY_US
        if (conf->dc_delay_us){
        	luat_timer_us_delay(conf->dc_delay_us);
        }
        #endif
    }
    if (data_len){
        if (conf->port == LUAT_LCD_SPI_DEVICE){
            len = luat_spi_device_send((luat_spi_device_t*)(conf->lcd_spi_device),  (const char*)data, data_len);
        }else{
            len = luat_spi_send(conf->port,  (const char*)data, data_len);
        }
        if (len != data_len){
            LLOGI("lcd_write_data error. %d", len);
            return -1;
        }
    }
    return 0;
}

luat_lcd_conf_t* luat_lcd_get_default(void) {
    for (size_t i = 0; i < LUAT_LCD_CONF_COUNT; i++){
        if (lcd_confs[i] != NULL) {
            return lcd_confs[i];
        }
    }
    return NULL;
}

int luat_lcd_conf_add(luat_lcd_conf_t* conf) {
    for (size_t i = 0; i < LUAT_LCD_CONF_COUNT; i++){
        if (lcd_confs[i] == NULL) {
            lcd_confs[i] = conf;
            return i;
        }
    }
    return -1;
}

const char* luat_lcd_name(luat_lcd_conf_t* conf) {
    return conf->opts->name;
}

int luat_lcd_init_default(luat_lcd_conf_t* conf) {
	conf->is_init_done = 0;

    if (conf->w == 0)
        conf->w = LCD_W;
    if (conf->h == 0)
        conf->h = LCD_H;
    if (conf->pin_pwr != LUAT_GPIO_NONE)
        luat_gpio_mode(conf->pin_pwr, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW); // POWER
    if (conf->interface_mode==LUAT_LCD_IM_4_WIRE_8_BIT_INTERFACE_I || conf->interface_mode==LUAT_LCD_IM_4_WIRE_8_BIT_INTERFACE_II){
        if (conf->pin_dc != LUAT_GPIO_NONE) {
            luat_gpio_mode(conf->pin_dc, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH); // DC
        }
    }
    luat_gpio_mode(conf->pin_rst, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_LOW); // RST

    if (conf->pin_pwr != LUAT_GPIO_NONE) {
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    }
    if (conf->opts->user_ctrl_init) {
        int res = conf->opts->user_ctrl_init(conf);
        if (res > 0) {
            goto INIT_NOT_DONE;
        }
        goto INIT_DONE;
    }
    luat_lcd_set_reset_pin_level(conf, Luat_GPIO_LOW);
//    luat_gpio_set(conf->pin_rst, Luat_GPIO_LOW);
    luat_rtos_task_sleep(100);
    luat_lcd_set_reset_pin_level(conf, Luat_GPIO_HIGH);
//    luat_gpio_set(conf->pin_rst, Luat_GPIO_HIGH);
    luat_rtos_task_sleep(120);
    luat_lcd_wakeup(conf);
    luat_rtos_task_sleep(120);

    // 发送初始化命令
    if (conf->opts->init){
        conf->opts->init(conf);
        // 在SDL2仿真模式下，不再继续发送硬件命令，直接完成初始化
        if (conf->opts && conf->opts->name && strcmp(conf->opts->name, "sdl2") == 0) {
            goto INIT_DONE;
        }
    }else{
        luat_lcd_execute_cmds(conf);
        if(strcmp(conf->opts->name,"custom") == 0){
            luat_heap_free(conf->opts->init_cmds);
        }
        luat_lcd_set_direction(conf,conf->direction);
    }

    luat_lcd_wakeup(conf);
    /* wait for power stability */
    luat_rtos_task_sleep(100);
    luat_lcd_clear(conf,LCD_BLACK);
    /* display on */
    luat_lcd_display_on(conf);
INIT_DONE:
    conf->is_init_done = 1;
INIT_NOT_DONE:
    for (size_t i = 0; i < LUAT_LCD_CONF_COUNT; i++){
        if (lcd_confs[i] == NULL) {
            lcd_confs[i] = conf;
            return 0;
        }
    }
    return -1;
}

int luat_lcd_setup_buff_default(luat_lcd_conf_t* conf){
    if (conf->buff) {
        LLOGE("lcd buff已经分配过了");
        return 0;
    }
    conf->buff = luat_heap_opt_malloc(LUAT_HEAP_PSRAM, sizeof(luat_color_t) * conf->w * conf->h);
    if (conf->buff == NULL) {
        LLOGW("psram 分配 lcd buff失败, 尝试在sram分配");
        conf->buff = luat_heap_opt_malloc(LUAT_HEAP_SRAM, sizeof(luat_color_t) * conf->w * conf->h);
    }
    if (conf->buff == NULL) {
        LLOGE("分配 lcd buff失败");
        return -1;
    }
    conf->buff_ex = luat_heap_opt_malloc(LUAT_HEAP_PSRAM, sizeof(luat_color_t) * conf->w * conf->h);
    if (conf->buff_ex == NULL) {
        LLOGW("psram 分配 lcd buff_ex失败, 尝试在sram分配");
        conf->buff_ex = luat_heap_opt_malloc(LUAT_HEAP_SRAM, sizeof(luat_color_t) * conf->w * conf->h);
    }
    if (conf->buff_ex == NULL) {
        LLOGE("分配 lcd buff_ex失败");
        return -1;
    }

    return 0;
}

LUAT_WEAK int luat_lcd_setup_buff(luat_lcd_conf_t* conf) {
    return luat_lcd_setup_buff_default(conf);
}

LUAT_WEAK int luat_lcd_init(luat_lcd_conf_t* conf) {
    return luat_lcd_init_default(conf);
}

int luat_lcd_close(luat_lcd_conf_t* conf) {
    if (conf->pin_pwr != LUAT_GPIO_NONE)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    return 0;
}

int luat_lcd_display_off(luat_lcd_conf_t* conf) {
    if (conf && conf->opts && conf->opts->name && strcmp(conf->opts->name, "sdl2") == 0) {
        return 0;
    }
    if (conf->pin_pwr != LUAT_GPIO_NONE) {
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    }
    if (conf->port != LUAT_LCD_PORT_RGB) {
        lcd_write_cmd_data(conf,0x28, NULL, 0);
    }
    return 0;
}

int luat_lcd_display_on(luat_lcd_conf_t* conf) {
    if (conf && conf->opts && conf->opts->name && strcmp(conf->opts->name, "sdl2") == 0) {
        return 0;
    }
    if (conf->pin_pwr != LUAT_GPIO_NONE) {
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    }
    if (conf->port != LUAT_LCD_PORT_RGB) {
        lcd_write_cmd_data(conf,0x29, NULL, 0);
    }
    return 0;
}

int luat_lcd_sleep(luat_lcd_conf_t* conf) {
    if (conf->pin_pwr != LUAT_GPIO_NONE)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_LOW);
    luat_rtos_task_sleep(5);
    if (conf->opts->sleep_ctrl) {
    	conf->opts->sleep_ctrl(conf, 1);
    } else {
    	lcd_write_cmd_data(conf,conf->opts->sleep_cmd?conf->opts->sleep_cmd:LUAT_LCD_DEFAULT_SLEEP, NULL, 0);
    }
    return 0;
}

int luat_lcd_wakeup(luat_lcd_conf_t* conf) {
    if (conf && conf->opts && conf->opts->name && strcmp(conf->opts->name, "sdl2") == 0) {
        return 0;
    }
    if (conf->pin_pwr != LUAT_GPIO_NONE)
        luat_gpio_set(conf->pin_pwr, Luat_GPIO_HIGH);
    luat_rtos_task_sleep(5);
    if (conf->opts->sleep_ctrl) {
    	conf->opts->sleep_ctrl(conf, 0);
    } else {
    	lcd_write_cmd_data(conf,conf->opts->wakeup_cmd?conf->opts->wakeup_cmd:LUAT_LCD_DEFAULT_WAKEUP, NULL, 0);
    }
    return 0;
}

int luat_lcd_inv_off(luat_lcd_conf_t* conf) {
    lcd_write_cmd_data(conf,0x20, NULL, 0);
    return 0;
}

int luat_lcd_inv_on(luat_lcd_conf_t* conf) {
    lcd_write_cmd_data(conf,0x21, NULL, 0);
    return 0;
}

int luat_lcd_set_address(luat_lcd_conf_t* conf,int16_t x1, int16_t y1, int16_t x2, int16_t y2) {
    uint8_t data_x[] = {(x1+conf->xoffset)>>8,x1+conf->xoffset,(x2+conf->xoffset)>>8,x2+conf->xoffset};
    lcd_write_cmd_data(conf,0x2a, data_x, 4);
    uint8_t data_y[] = {(y1+conf->yoffset)>>8,y1+conf->yoffset,(y2+conf->yoffset)>>8,y2+conf->yoffset};
    lcd_write_cmd_data(conf,0x2b, data_y, 4);
    lcd_write_cmd_data(conf,0x2c, NULL, 0);
    return 0;
}

int luat_lcd_set_color(luat_color_t back, luat_color_t fore){
    BACK_COLOR = back;
    FORE_COLOR = fore;
    return 0;
}

int luat_lcd_set_direction(luat_lcd_conf_t* conf, uint8_t direction){
    uint8_t direction_date = 0;
    if(direction==0) direction_date = conf->opts->direction0;
    else if(direction==1) direction_date = conf->opts->direction90;
    else if(direction==2) direction_date = conf->opts->direction180;
    else direction_date = conf->opts->direction270;
    lcd_write_cmd_data(conf,0x36, &direction_date, 1);
    return 0;
}

#ifndef LUAT_USE_LCD_CUSTOM_DRAW
int luat_lcd_flush_default(luat_lcd_conf_t* conf) {
    if (conf->buff == NULL) {
        return 0;
    }
    //LLOGD("luat_lcd_flush range %d %d", conf->flush_y_min, conf->flush_y_max);
    if (conf->flush_y_max < conf->flush_y_min) {
        // 没有需要刷新的内容,直接跳过
        //LLOGD("luat_lcd_flush no need");
        return 0;
    }
    if ((conf->port != LUAT_LCD_SPI_DEVICE) && conf->opts->lcd_draw) {
    	//LLOGD("luat_lcd_flush user flush");
    	if (conf->opts->no_ram_mode)
    	{
    		conf->opts->lcd_draw(conf, 0, 0, 0, 0, conf->buff);
    	}
    	else
    	{
    		conf->opts->lcd_draw(conf, 0, conf->flush_y_min, conf->w - 1, conf->flush_y_max, &conf->buff[conf->flush_y_min * conf->w]);
    	}
    } else {
        uint32_t size = conf->w * (conf->flush_y_max - conf->flush_y_min + 1) * 2;
        luat_lcd_set_address(conf, 0, conf->flush_y_min, conf->w - 1, conf->flush_y_max);
        const char* tmp = (const char*)(conf->buff + conf->flush_y_min * conf->w);
    	if (conf->port == LUAT_LCD_SPI_DEVICE){
    		luat_spi_device_send((luat_spi_device_t*)(conf->lcd_spi_device), tmp, size);
    	}else{
    		luat_spi_send(conf->port, tmp, size);
    	}
    }
    // 重置为不需要刷新的状态
    conf->flush_y_max = 0;
    conf->flush_y_min = conf->h;
    
    return 0;
}

LUAT_WEAK int luat_lcd_flush(luat_lcd_conf_t* conf) {
    return luat_lcd_flush_default(conf);
}

int luat_lcd_draw_default(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t* color) {
    if (x1 >= conf->w || y1 >= conf->h || x2 < 0 || y2 < 0 || x2 < x1 || y2 < y1) {
        // LLOGE("out of lcd buff range %d %d %d %d", x1, y1, x2, y2);
        // LLOGE("out of lcd buff range %d %d %d %d %d", x1 >= conf->w, y1 >= conf->h, y2 < 0, x2 < x1, y2 < y1);
        return 0;
    }
    if (y2 >= conf->h) {
        y2 = conf->h - 1;
    }

    // 直接刷屏模式
    if (conf->buff == NULL) {
        // 常规数据, 整体传输
        if (x1 >= 0 && y1 >= 0 && x2 <= conf->w && y2 <= conf->h) {
            if ((conf->port != LUAT_LCD_SPI_DEVICE) && conf->opts->lcd_draw) {
            	conf->opts->lcd_draw(conf, x1, y1, x2, y2, color);
            } else {
				uint32_t size = (x2 - x1 + 1) * (y2 - y1 + 1);
				// LLOGD("draw %dx%d %dx%d %d", x1, y1, x2, y2, size);
				luat_lcd_set_address(conf, x1, y1, x2, y2);
				if (conf->port == LUAT_LCD_SPI_DEVICE){
					luat_spi_device_send((luat_spi_device_t*)(conf->lcd_spi_device), (const char*)color, size* sizeof(luat_color_t));
				}else{
					luat_spi_send(conf->port, (const char*)color, size * sizeof(luat_color_t));
				}
            }
        }
        // 超出边界的数据, 按行传输
        else {
            int line_size = (x2 - x1 + 1);
            // LLOGD("want draw %dx%d %dx%d %d", x1, y1, x2, y2, line_size);
            luat_color_t* ptr = (luat_color_t*)color;
            for (int i = y1; i <= y2; i++)
            {
                if (i < 0) {
                    ptr += line_size;
                    continue;
                }
                luat_color_t* line = ptr;
                int lsize = line_size;
                int tmp_x1 = x1;
                int tmp_x2 = x2;
                if (x1 < 0) {
                    line += ( - x1);
                    lsize += (x1);
                    tmp_x1 = 0;
                }
                if (x2 > conf->w) {
                    lsize -= (x2 - conf->w);
                    tmp_x2 = conf->w;
                }
                if ((conf->port != LUAT_LCD_SPI_DEVICE) && conf->opts->lcd_draw) {
                    conf->opts->lcd_draw(conf, tmp_x1, i, tmp_x2, i, line);
                } else {
                // LLOGD("action draw %dx%d %dx%d %d", tmp_x1, i, tmp_x2, i, lsize);
                	luat_lcd_set_address(conf, tmp_x1, i, tmp_x2, i);
					if (conf->port == LUAT_LCD_SPI_DEVICE){
						luat_spi_device_send((luat_spi_device_t*)(conf->lcd_spi_device), (const char*)line, lsize * sizeof(luat_color_t));
					}else{
						luat_spi_send(conf->port, (const char*)line, lsize * sizeof(luat_color_t));
					}
                }
                ptr += line_size;
            }
            
            // TODO
            // LLOGD("超出边界,特殊处理");
        }
        return 0;
    }
    // buff模式
#if 0
    int16_t x_end = x2 >= conf->w?  (conf->w - 1):x2;
    luat_color_t* dst = (conf->buff);
    size_t lsize = (x2 - x1 + 1);
    for (int16_t x = x1; x <= x2; x++)
    {
        if (x < 0 || x >= conf->w)
            continue;
        for (int16_t y = y1; y <= y2; y++)
        {
            if (y < 0 || y >= conf->h)
                continue;
            memcpy((char*)(dst + (conf->w * y + x)), (char*)(color + (lsize * (y-y1) + (x-x1))), sizeof(luat_color_t));
        }
    }
    // 存储需要刷新的区域
    if (y1 < conf->flush_y_min) {
        if (y1 >= 0)
            conf->flush_y_min = y1;
        else
            conf->flush_y_min = 0;
    }
    if (y2 > conf->flush_y_max) {
        conf->flush_y_max = y2;
    }
#endif
    //LLOGI("X1 %d Y1 %d X2 %d Y2 %d", x1, y1, x2, y2);
    int16_t x_end = (x2 >= conf->w)?(conf->w - 1):x2;
    int16_t y_end = (y2 >= conf->h)?(conf->h - 1):y2;
    luat_color_t* dst = (conf->buff);
    size_t fromlsize = (x2 - x1 + 1);
    size_t tolsize = (x_end - x1 + 1);
    for (int16_t y = y1; y <= y_end; y++)
    {
        if (y < 0) continue;
        //LLOGI("H%d L %d <- %d X2 %d Y2 %d", y, conf->w * y + x1, fromlsize * (y - y1));
    	memcpy(&dst[(conf->w * y + x1)], &color[fromlsize * (y - y1)], tolsize * sizeof(luat_color_t));
    }
    // 存储需要刷新的区域
    if (y1 < conf->flush_y_min) {
        if (y1 >= 0)
            conf->flush_y_min = y1;
        else
            conf->flush_y_min = 0;
    }
    if (y_end > conf->flush_y_max) {
        conf->flush_y_max = y_end;
    }
    return 0;
}

LUAT_WEAK int luat_lcd_draw(luat_lcd_conf_t* conf, int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t* color) {
    return luat_lcd_draw_default(conf, x1, y1, x2, y2, color);
}
#endif

int luat_lcd_draw_point(luat_lcd_conf_t* conf, int16_t x, int16_t y, luat_color_t color) {
    luat_color_t tmp = color;
    if (conf->endianness_swap)
        tmp = color_swap(color);// 注意, 这里需要把颜色swap了
    return luat_lcd_draw(conf, x, y, x, y, &tmp);
}

int luat_lcd_clear(luat_lcd_conf_t* conf, luat_color_t color){
    luat_lcd_draw_fill(conf, 0, 0, conf->w - 1, conf->h, color);
    return 0;
}

int luat_lcd_set_reset_pin_level(luat_lcd_conf_t* conf, uint8_t level){
	if (conf->opts->reset_ctrl)
	{
		return conf->opts->reset_ctrl(conf, level);
	}
	else
	{
	    if (conf->pin_rst != LUAT_GPIO_NONE) {
	        luat_gpio_set(conf->pin_rst, level);
	    }

	}
    return 0;
}

int luat_lcd_draw_fill(luat_lcd_conf_t* conf,int16_t x1,int16_t y1,int16_t x2,int16_t y2, luat_color_t color) {          
	int16_t i;
	if ((conf->port != LUAT_LCD_SPI_DEVICE) && !conf->buff && conf->opts->lcd_fill)
	{
		return conf->opts->lcd_fill(conf, x1, y1, x2, y2 - 1, color);
	}
	for(i=y1;i<y2;i++)
	{
		luat_lcd_draw_line(conf, x1, i, x2, i, color);
	}
    return 0;			  	    
}

int luat_lcd_draw_vline(luat_lcd_conf_t* conf, int16_t x, int16_t y,int16_t h, luat_color_t color) {
    if (h<=0) return 0;
    return luat_lcd_draw_line(conf, x, y, x, y + h - 1, color);
}

int luat_lcd_draw_hline(luat_lcd_conf_t* conf, int16_t x, int16_t y,int16_t w, luat_color_t color) {
    if (w<=0) return 0;
    return luat_lcd_draw_line(conf, x, y, x + w - 1, y, color);
}

int luat_lcd_draw_line(luat_lcd_conf_t* conf,int16_t x1, int16_t y1, int16_t x2, int16_t y2,luat_color_t color) {
    luat_color_t tmp = color;
    int16_t t;
    uint32_t i = 0;
    int xerr = 0, yerr = 0, delta_x, delta_y, distance;
    int incx, incy, row, col;
    if (x1 == x2 || y1 == y2) // 直线
    {
        size_t dots = (x2 - x1 + 1) * (y2 - y1 + 1);//点数量
        luat_color_t* line_buf = (luat_color_t*) luat_heap_malloc(dots * sizeof(luat_color_t));
        if (conf->endianness_swap)
            tmp = color_swap(color);// 颜色swap
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

int luat_lcd_draw_rectangle(luat_lcd_conf_t* conf,int16_t x1, int16_t y1, int16_t x2, int16_t y2, luat_color_t color){
    luat_lcd_draw_line(conf,x1, y1, x2, y1, color);
    luat_lcd_draw_line(conf,x1, y1, x1, y2, color);
    luat_lcd_draw_line(conf,x1, y2, x2, y2, color);
    luat_lcd_draw_line(conf,x2, y1, x2, y2, color);
    return 0;
}

int luat_lcd_draw_circle(luat_lcd_conf_t* conf,int16_t x0, int16_t y0, uint8_t r, luat_color_t color){
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

#ifndef LUAT_COMPILER_NOWEAK

LUAT_WEAK int luat_lcd_qspi_config(luat_lcd_conf_t* conf, luat_lcd_qspi_conf_t *qspi_config) {
    return -1;
};

LUAT_WEAK int luat_lcd_qspi_auto_flush_on_off(luat_lcd_conf_t* conf, uint8_t on_off) {
    return -1;
}

LUAT_WEAK uint8_t luat_lcd_qspi_is_no_ram(luat_lcd_conf_t* conf) {
    return 0;
}
LUAT_WEAK int luat_lcd_run_api_in_service(luat_lcd_api api, void *param, uint32_t param_len) {
    return -1;
};
#endif

