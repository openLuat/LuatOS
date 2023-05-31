/*
@module  gtfont
@summary gtfont高通字库模块
@version 1.0
@date    2021.11.11
@tag LUAT_USE_GTFONT
*/

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_lcd.h"
#include "luat_malloc.h"

#include "epdpaint.h"

#include "GT5SLCD2E_1A.h"
#define LUAT_LOG_TAG "gt"
#include "luat_log.h"

#ifdef LUAT_USE_LCD
extern luat_color_t lcd_str_fg_color,lcd_str_bg_color;
#else
static luat_color_t lcd_str_fg_color  = WHITE ,lcd_str_bg_color  = BLACK ;
#endif

extern luat_spi_device_t* gt_spi_dev;

//横置横排显示
void gtfont_draw_w(unsigned char *pBits,unsigned int x,unsigned int y,unsigned int widt,unsigned int high,int(*point)(void*,uint16_t, uint16_t, uint32_t),void* userdata,int mode){
	unsigned int i,j,k,n;
	unsigned char temp;
	n = 0;

	for( i = 0;i < high; i++){
		for( j = 0;j < ((widt+7)>> 3);j++){
			temp = pBits[n++];
			for(k = 0;k < 8;k++){
				if(((temp << k)& 0x80) == 0 ){
					/* 显示一个像素点 */
					if (mode == 0)point((luat_lcd_conf_t *)userdata, x+k+(j*8), y+i, lcd_str_bg_color);
					else if (mode == 1)point((Paint *)userdata, x+k+(j*8), y+i, 0xFFFF);
				}else{
					/* 显示一个像素点 */
					if (mode == 0)point((luat_lcd_conf_t *)userdata, x+k+(j*8), y+i, lcd_str_fg_color);
					else if (mode == 1)point((Paint *)userdata, x+k+(j*8), y+i, 0x0000);
					else if (mode == 2)point((u8g2_t *)userdata, x+k+(j*8), y+i, 0x0000);
				}
			}
		}
	}
}

/*----------------------------------------------------------------------------------------
 * 灰度数据显示函数 1阶灰度/2阶灰度/4阶灰度
 * 参数 ：
 * data灰度数据;  x,y=显示起始坐标 ; w 宽度, h 高度,grade 灰度阶级[1阶/2阶/4阶]
 * HB_par	1 白底黑字	0 黑底白字
 *------------------------------------------------------------------------------------------*/
void gtfont_draw_gray_hz (unsigned char *data,unsigned short x,unsigned short y,unsigned short w ,unsigned short h,unsigned char grade, unsigned char HB_par,int(*point)(void*,uint16_t, uint16_t, uint32_t),void* userdata,int mode){
	unsigned int temp=0,gray,x_temp=x;
	unsigned int i=0,j=0,k=0,t;
	unsigned char c,c2,*p;
	unsigned long color8bit,color4bit,color3bit[8],color2bit,color;
	t=(w+7)/8*grade;//
	p=data;
	if(grade==2){
		for(i=0;i<t*h;i++){
			c=*p++;
			for(j=0;j<4;j++){
				color2bit=(c>>6);//获取像素点的2bit颜色值
				if(HB_par==1)color2bit= (3-color2bit)*250/3;//白底黑字
				else color2bit= color2bit*250/3;//黑底白字
				gray=color2bit/8;
				color=(0x001f&gray)<<11;							//r-5
				color=color|(((0x003f)&(gray*2))<<5);	//g-6
				color=color|(0x001f&gray);						//b-5
				temp=color;
				temp=temp;
				c<<=2;
				if(x<(x_temp+w)){
					if (mode == 0)point((luat_lcd_conf_t *)userdata,x,y,temp);
					else if (mode == 1)point((Paint *)userdata, x,y,temp);
				}
				x++;
				if(x>=x_temp+(w+7)/8*8) {x=x_temp; y++;}
			}
		}
	}
	else if(grade==3){
		for(i=0;i<t*h;i+=3){
			c=*p; c2=*(p+1);
			color3bit[0]=(c>>5)&0x07;
			color3bit[1]=(c>>2)&0x07;
			color3bit[2]=((c<<1)|(c2>>7))&0x07;
			p++;
			c=*p; c2=*(p+1);
			color3bit[3]=(c>>4)&0x07;
			color3bit[4]=(c>>1)&0x07;
			color3bit[5]=((c<<2)|(c2>>6))&0x07;
			p++;
			c=*p;
			color3bit[6]=(c>>3)&0x07;
			color3bit[7]=(c>>0)&0x07;
			p++;
			for(j=0;j<8;j++){
				if(HB_par==1)color3bit[j]= (7-color3bit[j])*255/7;//白底黑字
				else color3bit[j]=color3bit[j]*255/7;//黑底白字
				gray =color3bit[j]/8;
				color=(0x001f&gray)<<11;							//r-5
				color=color|(((0x003f)&(gray*2))<<5);	//g-6
				color=color|(0x001f&gray);						//b-5
				temp =color;
				if(x<(x_temp+w)){
					if (mode == 0)point((luat_lcd_conf_t *)userdata,x,y,temp);
					else if (mode == 1)point((Paint *)userdata, x,y,temp);
				}
				x++;
				if(x>=x_temp+(w+7)/8*8) {x=x_temp; y++;}
			}
		}
	}
	else if(grade==4){
		for(i=0;i<t*h;i++){
			c=*p++;
			for(j=0;j<2;j++){
				color4bit=(c>>4);
				if(HB_par==1)color4bit= (15-color4bit)*255/15;//白底黑字
				else color4bit= color4bit*255/15;//黑底白字
				gray=color4bit/8;
				color=(0x001f&gray)<<11;				//r-5
				color=color|(((0x003f)&(gray*2))<<5);	//g-6
				color=color|(0x001f&gray);				//b-5
				temp=color;
				c<<=4;
				if(x<(x_temp+w)){
					if (mode == 0)point((luat_lcd_conf_t *)userdata,x,y,temp);
					else if (mode == 1)point((Paint *)userdata, x,y,temp);
				}
				x++;
				if(x>=x_temp+(w+7)/8*8) {x=x_temp; y++;}
			}
		}
	}
	else{
		for(i=0;i<t*h;i++){
			c=*p++;
			for(j=0;j<8;j++){
				if(c&0x80) color=0x0000;
				else color=0xffff;
				c<<=1;
				if(x<(x_temp+w)){
					if(color == 0x0000 && HB_par == 1){
						if (mode == 0)point((luat_lcd_conf_t *)userdata,x,y,color);
						else if (mode == 1)point((Paint *)userdata, x,y,color);
					}else if(HB_par == 0 && color == 0x0000){
						if (mode == 0)point((luat_lcd_conf_t *)userdata,x,y,~color);
						else if (mode == 1)point((Paint *)userdata, x,y,~color);
					}
				}
				x++;
				if(x>=x_temp+(w+7)/8*8) {x=x_temp; y++;}
			}
		}
	}
}

#ifndef LUAT_COMPILER_NOWEAK
LUAT_WEAK int GT_Font_Init(void) {
    return 1;
}
#endif

/**
初始化高通字体芯片
@api gtfont.init(spi_device)
@userdata 仅支持spi device 生成的指针数据
@return boolean 成功返回true,否则返回false
@usage
-- 特别提醒: 使用本库的任何代码, 都需要 额外 的 高通字体芯片 !!
-- 没有额外芯片是跑不了的!!
gtfont.init(spi_device)
*/
static int l_gtfont_init(lua_State* L) {
    if (gt_spi_dev == NULL) {
        gt_spi_dev = lua_touserdata(L, 1);
    }
	const char data = 0xff;
	luat_spi_device_send(gt_spi_dev, &data, 1);
	int font_init = GT_Font_Init();
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_gtfont[] =
{
    { "init" ,          ROREG_FUNC(l_gtfont_init)},
	{ NULL,             {}}
};

LUAMOD_API int luaopen_gtfont( lua_State *L ) {
    luat_newlib2(L, reg_gtfont);
    return 1;
}
