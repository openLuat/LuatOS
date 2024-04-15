
#include "luat_base.h"
#include "luat_ht1621.h"
#include "luat_gpio.h"
#include "luat_timer.h"

static void luat_ht1621_SendBit(luat_ht1621_conf_t *conf, unsigned char sdat,unsigned char cnt) //data 的高cnt 位写入HT1621，高位在前 
{ 
	unsigned char i;
	int pin_wr = conf->pin_wr;
	int pin_data = conf->pin_data;
	for(i=0;i<cnt;i++) 
	{ 
		luat_gpio_set(pin_wr, 0);
		luat_timer_us_delay(20); 
		if(sdat&0x80)
		{
			luat_gpio_set(pin_data, 1);
		}
		else
		{
			luat_gpio_set(pin_data, 0);
		}
		luat_timer_us_delay(20);
		luat_gpio_set(pin_wr, 1);
		luat_timer_us_delay(20);
		sdat<<=1;
	} 
	luat_timer_us_delay(20);  
}


void luat_ht1621_init(luat_ht1621_conf_t *conf) {
	luat_gpio_mode(conf->pin_cs, LUAT_GPIO_OUTPUT, LUAT_GPIO_PULLUP, 0);
	luat_gpio_mode(conf->pin_data, LUAT_GPIO_OUTPUT, LUAT_GPIO_PULLUP, 0);
	luat_gpio_mode(conf->pin_wr, LUAT_GPIO_OUTPUT, LUAT_GPIO_PULLUP, 1);
	luat_ht1621_lcd(conf, 0);
	luat_ht1621_write_cmd(conf, Sys_en);
	luat_ht1621_write_cmd(conf, RCosc);
	luat_ht1621_write_cmd(conf, ComMode);
	luat_ht1621_lcd(conf, 1);
}

void luat_ht1621_write_cmd(luat_ht1621_conf_t *conf, uint8_t cmd) {
	luat_gpio_set(conf->pin_cs, 0);
	luat_ht1621_SendBit(conf, 0x80,4);    		//写入标志码“100”和9 位command 命令，由于 
	luat_ht1621_SendBit(conf, cmd,8); 		    //没有使有到更改时钟输出等命令，为了编程方便 
	luat_gpio_set(conf->pin_cs, 1); //直接将command 的最高位写“0” 
}

void luat_ht1621_write_data(luat_ht1621_conf_t *conf, uint8_t addr, uint8_t sdat) {
	addr<<=2; 
	luat_gpio_set(conf->pin_cs, 0);
	luat_ht1621_SendBit(conf, 0xa0,3);     //写入标志码“101” 
	luat_ht1621_SendBit(conf, addr,6);     //写入addr 的高6位 
	luat_ht1621_SendBit(conf, sdat,8);    //写入data 的8位 
	luat_gpio_set(conf->pin_cs, 1);
}

void luat_ht1621_lcd(luat_ht1621_conf_t *conf, int onoff) {
	luat_ht1621_write_cmd(conf, onoff ? LCD_on : LCD_off);
}
