#ifndef __SEGMENTLCD__H__
#define __SEGMENTLCD__H__

#include "luat_base.h"
#include "luat_gpio.h"

//定义HT1621的命令 
#define  ComMode    0x52  //4COM,1/3bias  1000    010 1001  0  
#define  RCosc      0x30  //内部RC振荡器(上电默认)1000 0011 0000 
#define  LCD_on     0x06  //打开LCD 偏压发生器1000     0000 0 11 0 
#define  LCD_off    0x04  //关闭LCD显示 
#define  Sys_en     0x02  //系统振荡器开 1000   0000 0010 
#define  CTRl_cmd   0x80  //写控制命令 
#define  Data_cmd   0xa0  //写数据命令 

//设置变量寄存器函数
// #define sbi(x, y)  (x |= (1 << y))   /*置位寄器x的第y位*/
// #define cbi(x, y)  (x &= ~(1 <<y ))  /*清零寄器x的第y位*/  

//IO端口定义
#define LCD_DATA 4
#define LCD_WR 5
#define LCD_CS 6

#ifndef HIGH
#define HIGH 1
#endif

#ifndef LOW
#define LOW 1
#endif

typedef struct luat_ht1621_conf {
    int pin_data;
    int pin_wr;
    int pin_cs;
}luat_ht1621_conf_t;

//定义端口HT1621数据端口 
#define LCD_DATA1    luat_gpio_set(LCD_DATA,HIGH) 
#define LCD_DATA0    luat_gpio_set(LCD_DATA,LOW) 
#define LCD_WR1      luat_gpio_set(LCD_WR,HIGH)  
#define LCD_WR0      luat_gpio_set(LCD_WR,LOW)   
#define LCD_CS1      luat_gpio_set(LCD_CS,HIGH)  
#define LCD_CS0      luat_gpio_set(LCD_CS,LOW)


void luat_ht1621_init(luat_ht1621_conf_t *conf);
void luat_ht1621_write_cmd(luat_ht1621_conf_t *conf, uint8_t cmd);
void luat_ht1621_write_data(luat_ht1621_conf_t *conf, uint8_t addr, uint8_t data);
void luat_ht1621_lcd(luat_ht1621_conf_t *conf, int onoff);


#endif