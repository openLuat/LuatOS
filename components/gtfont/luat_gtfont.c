
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_lcd.h"
#include "epdpaint.h"
#include "luat_mem.h"
#include "luat_gtfont.h"

#define LUAT_GT_DEBUG 0
#define LUAT_LOG_TAG "gt"
#include "luat_log.h"

#ifdef LUAT_USE_LCD
extern luat_color_t BACK_COLOR, FORE_COLOR;
#else
static luat_color_t BACK_COLOR = LCD_WHITE, FORE_COLOR = LCD_BLACK;
#endif

luat_spi_device_t* gt_spi_dev = NULL;

unsigned char r_dat_bat(unsigned long address,unsigned long DataLen,unsigned char *pBuff) {
    if (gt_spi_dev == NULL)
        return 0;
    char send_buf[4] = {
        0x03,
        (uint8_t)((address)>>16),
        (uint8_t)((address)>>8),
        (uint8_t)(address)
    };
    luat_spi_lock(gt_spi_dev->bus_id);
    luat_spi_device_transfer(gt_spi_dev, send_buf, 4, (char *)pBuff, DataLen);
    luat_spi_unlock(gt_spi_dev->bus_id);
    #if LUAT_GT_DEBUG
    LLOGD("r_dat_bat addr %08X len %d pBuff %X", address, DataLen,*pBuff);
    for(int i = 0; i < DataLen;i++){
        LLOGD("pBuff[%d]:0x%02X",i,pBuff[i]);
    }
    #endif
    return pBuff[0];
}

unsigned char CheckID(unsigned char CMD, unsigned long address,unsigned long byte_long,unsigned char *p_arr) {
    #if LUAT_GT_DEBUG
    LLOGD("CheckID CMD %02X addr %08X len %d p_arr %X", CMD, address, byte_long,*p_arr);
    #endif
    if (gt_spi_dev == NULL)
        return 0;
    char send_buf[4] = {
        CMD,
        (uint8_t)((address)>>16),
        (uint8_t)((address)>>8),
        (uint8_t)(address)
    };
    luat_spi_lock(gt_spi_dev->bus_id);
    luat_spi_device_transfer(gt_spi_dev, send_buf, 4, (char *)p_arr, byte_long);
    luat_spi_unlock(gt_spi_dev->bus_id);
    // return p_arr[0];
    return 1;
}

unsigned char gt_read_data(unsigned char* sendbuf , unsigned char sendlen , unsigned char* receivebuf, unsigned int receivelen)
{
    if (gt_spi_dev == NULL)
        return 0;
    luat_spi_lock(gt_spi_dev->bus_id);
    luat_spi_device_transfer(gt_spi_dev, (const char *)sendbuf, sendlen,(char *)receivebuf, receivelen);
    luat_spi_unlock(gt_spi_dev->bus_id);
    #if LUAT_GT_DEBUG
    LLOGD("gt_read_data sendlen:%d receivelen:%d",sendlen,receivelen);
    for(int i = 0; i < sendlen;i++){
        LLOGD("sendbuf[%d]:0x%02X",i,sendbuf[i]);
    }
    for(int i = 0; i < receivelen;i++){
        LLOGD("receivebuf[%d]:0x%02X",i,receivebuf[i]);
    }
    #endif
    return 1;
}

uint32_t gt_unicode2gb18030(uint32_t unicode){
    if (unicode<0x80){
        return unicode;
    }
    // #if LUAT_GT_DEBUG
    //     uint32_t gb18030 = U2G(unicode);
    //     LLOGD("U2G unicode:0x%X gb18030:0x%X",unicode,gb18030);
    // #endif
    return U2G(unicode);
}

//横置横排显示
unsigned int gtfont_draw_w(unsigned char *pBits,unsigned int x,unsigned int y,unsigned int size,unsigned int widt,unsigned int high,int(*point)(void*,uint16_t, uint16_t, uint32_t),void* userdata,int mode){
	unsigned int i=0,j=0,k=0,n=0,dw=0;
	unsigned char temp;
	int w = ((widt+7)>> 3);
	for( i = 0;i < high; i++){
		for( j = 0;j < w;j++){
			temp = pBits[n++];
			for(k = 0;k < 8;k++){
				if (widt < size){
					if (j==(w-1) && k==widt%8){
						break;
					}
				}
				if(((temp << k)& 0x80) == 0 ){//背景色
					// /* 显示一个像素点 */
					// if (mode == 0)point((luat_lcd_conf_t *)userdata, x+k+(j*8), y+i, lcd_str_bg_color);
					// else if (mode == 1)point((Paint *)userdata, x+k+(j*8), y+i, 0xFFFF);
				}else{
					/* 显示一个像素点 */
					if (dw<k+(j*8)) dw = k+(j*8);
					if (mode == 0)point((luat_lcd_conf_t *)userdata, x+k+(j*8), y+i, FORE_COLOR);
					else if (mode == 1)point((Paint *)userdata, x+k+(j*8), y+i, 0x0000);
					else if (mode == 2)point((u8g2_t *)userdata, x+k+(j*8), y+i, 0x0000);
				}
			}
		}
		if (widt < size){
			n += (size-widt)>>3;
		}
	}
	return ++dw;
}

/*----------------------------------------------------------------------------------------
 * 灰度数据显示函数 1阶灰度/2阶灰度/4阶灰度
 * 参数 ：
 * data灰度数据;  x,y=显示起始坐标 ; w 宽度, h 高度,grade 灰度阶级[1阶/2阶/4阶]
 *------------------------------------------------------------------------------------------*/
unsigned int gtfont_draw_gray_hz (unsigned char *data,unsigned short x,unsigned short y,
                unsigned short w ,unsigned short h,unsigned char grade,
                int(*point)(void*,uint16_t, uint16_t, uint32_t),void* userdata,int mode){
	unsigned int temp=0,gray,x_temp=x,dw=0;
	unsigned int i=0,j=0,t;
	unsigned char c,*p;
	unsigned long color4bit,color2bit,color;
	t=(w+7)/8*grade;//
	p=data;
	if(grade==2){
		for(i=0;i<t*h;i++){
			c=*p++;
			for(j=0;j<4;j++){
				color2bit=(c>>6);//获取像素点的2bit颜色值
                if (color2bit!=0){
                    if (FORE_COLOR == LCD_BLACK){
                        color2bit=(3-color2bit)*255/3;//白底黑字
                        gray=color2bit/8;
                        color=(0x001f&gray)<<11;							//r-5
                        color=color|(((0x003f)&(gray*2))<<5);	//g-6
                        color=color|(0x001f&gray);						//b-5
                        temp=color;   
                    }else{
                        temp=FORE_COLOR;
                    }
                    if(x<(x_temp+w)){
                        if (mode == 0)point((luat_lcd_conf_t *)userdata,x,y,temp);
                        else if (mode == 1)point((Paint *)userdata, x,y,temp);
                        // LLOGD("x_temp:%d,x:%d,dw:%d,temp:0x%x",x_temp,x,dw,temp);
                        if (dw < x){
                            dw = x;
                        }
                    }
                }
                c<<=2;
				x++;
				if(x>=x_temp+(w+7)/8*8) {x=x_temp; y++;}
			}
		}
	}else if(grade==4){
		for(i=0;i<t*h;i++){
			c=*p++;
			for(j=0;j<2;j++){
				color4bit=(c>>4);
                if (color4bit!=0){
                    uint8_t disp = 0;
                    if (FORE_COLOR == LCD_BLACK){
                        color4bit= (15-color4bit)*255/15;//白底黑字
                        gray=color4bit/8;

                        color=((0x001f&gray))<<11;				//r-5
                        color=color|(((0x003f&(gray*2)))<<5);	//g-6
                        color=color|((0x001f&gray));				//b-5
                        temp=color;
                        disp = 1;
                    }else if(color4bit>=7){
                        temp=FORE_COLOR;
                        disp = 1;
                    }
                    if(x<(x_temp+w)){
                        if (disp){
                            if (mode == 0)point((luat_lcd_conf_t *)userdata,x,y,temp);
                            else if (mode == 1)point((Paint *)userdata, x,y,temp);
                        }
                        // LLOGD("x_temp:%d,x:%d,dw:%d,temp:0x%x",x_temp,x,dw,temp);
                        if (dw < x){
                            // LLOGD("x_temp:%d,x:%d,dw:%d",x_temp,x,dw);
                            dw = x;
                        }
                    }
                }
                c<<=4;
				x++;
				if(x>=x_temp+(w+7)/8*8) {x=x_temp; y++;}
			}
		}
	}else{   //1bits
		for(i=0;i<t*h;i++){
			c=*p++;
			for(j=0;j<8;j++){
				if(c&0x80) {
                    if(x<(x_temp+w)){
                        if (mode == 0)point((luat_lcd_conf_t *)userdata,x,y,FORE_COLOR);
                        else if (mode == 1)point((Paint *)userdata, x,y,FORE_COLOR);
                        if (dw < x){
                            dw = x;
                        }
                    }
                }
				c<<=1;
				x++;
				if(x>=x_temp+(w+7)/8*8) {x=x_temp; y++;}
			}
		}
	}
    if (dw>x_temp){
        return dw-x_temp+1;
    }else{
        return w/2+1;
    }
}

unsigned int gtfont_get_width(unsigned char *p,unsigned int zfwidth,unsigned int zfhigh ){
    unsigned char *q;
    unsigned int i,j,tem,tem1,witdh1=0,witdh2=0;
    q=p;
    for (i=0;i<zfwidth/16;i++){
        tem=0;
        tem1=0;
        for (j=0;j<zfhigh;j++){
            tem=(*(q+j*(zfwidth/8)+i*2)|(*(q+1+j*(zfwidth/8)+i*2))<<8);
            tem1=tem1|tem;
        }
        witdh1=0;
        for (j=0;j<16;j++){
            if (((tem1<<j)&0x8000)==0x8000){
            witdh1=j;
            }
        }
        witdh2+=witdh1;
    }
    return witdh2;
}

#ifndef LUAT_COMPILER_NOWEAK
LUAT_WEAK int GT_Font_Init(void) {
    return 1;
}
#endif

