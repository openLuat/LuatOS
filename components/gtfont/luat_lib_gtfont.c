#include "luat_base.h"
#include "luat_spi.h"
#include "luat_lcd.h"
#include "luat_malloc.h"

#include "GT5SLCD2E_1A.h"
#define LUAT_LOG_TAG "gt"
#include "luat_log.h"

extern luat_spi_device_t* gt_spi_dev;
static luat_lcd_conf_t* lcd_conf;

//横置横排显示
void Display_W(unsigned char *pBits,unsigned int x,unsigned int y,unsigned int widt,unsigned int high){
	unsigned int i,j,k,n;
	unsigned char temp;
	n = 0;
	for( i = 0;i < high; i++){
		for( j = 0;j < ((widt+7)>> 3);j++){
			temp = pBits[n++];
			for(k = 0;k < 8;k++){
				if(((temp << k)& 0x80) == 0 ){
					/* 显示一个像素点 */
					luat_lcd_draw_point(lcd_conf, x+k+(j*8), y+i, 0xFFFF);
				}else{
					/* 显示一个像素点 */
					luat_lcd_draw_point(lcd_conf, x+k+(j*8), y+i, 0x0000);
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
void Gray_Display_hz(unsigned char *data,unsigned short x,unsigned short y,
	unsigned short w ,unsigned short h,unsigned char grade, unsigned char HB_par)
{
	unsigned int temp=0,gray,x_temp=x;
	unsigned int i=0,j=0,k=0,t;
	unsigned char c,c2,*p;
	unsigned long color8bit,color4bit,color3bit[8],color2bit,color;
	t=(w+7)/8*grade;//
	p=data;
	#if DISMODE
	LCD_Set_Window(x,y,(((w+7)/8)*8),h);	//设置窗口
	LCD_WriteRAM_Prepare();		//开始写入GRAM
	#endif
	if(grade==2)	//2bits
	{
		for(i=0;i<t*h;i++)
		{
			c=*p++;
			for(j=0;j<4;j++)
			{
				color2bit=(c>>6);//获取像素点的2bit颜色值
				if(HB_par==1)
					color2bit= (3-color2bit)*250/3;//白底黑字
				else
					color2bit= color2bit*250/3;//黑底白字
				gray=color2bit/8;
				color=(0x001f&gray)<<11;							//r-5
				color=color|(((0x003f)&(gray*2))<<5);	//g-6
				color=color|(0x001f&gray);						//b-5
				temp=color;
				temp=temp;
				c<<=2;
				#if DISMODE
				//写16位数据
				LCD_WriteRAM(temp);
				#else
				//打点
				if(x<(x_temp+w))
				{
					// Gui_DrawPoint(x,y,temp);
					luat_lcd_draw_point(lcd_conf, x,y,temp);
				}
				x++;
				if(x>=x_temp+(w+7)/8*8) {x=x_temp; y++;}
				#endif
			}
		}
	}
	else if(grade==3)//3bits
	{
		for(i=0;i<t*h;i+=3)
		{
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
			for(j=0;j<8;j++)
			{
				if(HB_par==1)
				color3bit[j]= (7-color3bit[j])*255/7;//白底黑字
				else
				color3bit[j]=color3bit[j]*255/7;//黑底白字
				gray =color3bit[j]/8;
				color=(0x001f&gray)<<11;							//r-5
				color=color|(((0x003f)&(gray*2))<<5);	//g-6
				color=color|(0x001f&gray);						//b-5
				temp =color;
				#if DISMODE
				//写16位数据
				LCD_WriteRAM(temp);
				#else
				//打点
				if(x<(x_temp+w))
				{
					// Gui_DrawPoint(x,y,temp);
					luat_lcd_draw_point(lcd_conf, x,y,temp);
				}
				x++;
				if(x>=x_temp+(w+7)/8*8) {x=x_temp; y++;}
				#endif
			}
		}
	}
	else if(grade==4)	//4bits
	{
		for(i=0;i<t*h;i++)
		{
			c=*p++;
			for(j=0;j<2;j++)
			{
				color4bit=(c>>4);
				if(HB_par==1)
					color4bit= (15-color4bit)*255/15;//白底黑字
				else
					color4bit= color4bit*255/15;//黑底白字
				gray=color4bit/8;
				color=(0x001f&gray)<<11;				//r-5
				color=color|(((0x003f)&(gray*2))<<5);	//g-6
				color=color|(0x001f&gray);				//b-5
				temp=color;
				c<<=4;
				#if DISMODE
				//写16位数据
				LCD_WriteRAM(temp);
				#else
				//打点
				if(x<(x_temp+w)){
					// Gui_DrawPoint(x,y,temp);
					luat_lcd_draw_point(lcd_conf, x,y,temp);
				}
				x++;
				if(x>=x_temp+(w+7)/8*8) {x=x_temp; y++;}
				#endif
			}
		}
	}
	else	//1bits
	{
		for(i=0;i<t*h;i++)
		{
			c=*p++;
			for(j=0;j<8;j++)
			{
				if(c&0x80) color=0x0000;
				else color=0xffff;
				c<<=1;

				#if DISMODE
				//写16位数据
				LCD_WriteRAM(color);
				#else
				//打点
				if(x<(x_temp+w))
				{
					if(color == 0x0000 && HB_par == 1)
					{
						// Gui_DrawPoint(x,y,color);	//打点
						luat_lcd_draw_point(lcd_conf, x,y,color);
					}
					else if(HB_par == 0 && color == 0x0000)
					{
						// Gui_DrawPoint(x,y,~color);	//打点
						luat_lcd_draw_point(lcd_conf, x,y,~color);
					}
				}
				x++;
				if(x>=x_temp+(w+7)/8*8) {x=x_temp; y++;}
				#endif
			}
		}
	}
}

static int l_gtfont_init(lua_State* L) {
    if (gt_spi_dev == NULL) {
        gt_spi_dev = lua_touserdata(L, 1);
    }

	luat_spi_device_send(gt_spi_dev, 0xff, 1);
    lcd_conf = luat_lcd_get_default();
    return 0;
}


static uint8_t utf8_state;
static uint16_t encoding;
static uint16_t utf8_next(uint8_t b)
{
  if ( b == 0 )  /* '\n' terminates the string to support the string list procedures */
    return 0x0ffff; /* end of string detected, pending UTF8 is discarded */
  if ( utf8_state == 0 )
  {
    if ( b >= 0xfc )  /* 6 byte sequence */
    {
      utf8_state = 5;
      b &= 1;
    }
    else if ( b >= 0xf8 )
    {
      utf8_state = 4;
      b &= 3;
    }
    else if ( b >= 0xf0 )
    {
      utf8_state = 3;
      b &= 7;      
    }
    else if ( b >= 0xe0 )
    {
      utf8_state = 2;
      b &= 15;
    }
    else if ( b >= 0xc0 )
    {
      utf8_state = 1;
      b &= 0x01f;
    }
    else
    {
      /* do nothing, just use the value as encoding */
      return b;
    }
    encoding = b;
    return 0x0fffe;
  }
  else
  {
    utf8_state--;
    /* The case b < 0x080 (an illegal UTF8 encoding) is not checked here. */
    encoding<<=6;
    b &= 0x03f;
    encoding |= b;
    if ( utf8_state != 0 )
      return 0x0fffe; /* nothing to do yet */
  }
  return encoding;
}
extern unsigned short unicodetogb2312 ( unsigned short	chr);

static int l_gtfont_gb2312_display(lua_State* L) {
	unsigned char buf[128];
	int len;
	int i = 0;
	uint8_t strhigh,strlow ;
	uint16_t str;
    const char *fontCode = luaL_checklstring(L, 1,&len);
    unsigned char size = luaL_checkinteger(L, 2);
	int x = luaL_checkinteger(L, 3);
	int y = luaL_checkinteger(L, 4);
	while ( i < len){
		strhigh = *fontCode;
		fontCode++;
		strlow = *fontCode;
		str = (strhigh<<8)|strlow;
		fontCode++;
		get_font(buf, 1, str, size, size, size);
		Display_W(buf , x ,y , size , 32);
		x+=size;
		i+=2;
	}
    return 0;
}

static int l_gtfont_gb2312_display_gray(lua_State* L) {
	unsigned char buf[2048];
	int len;
	int i = 0;
	uint8_t strhigh,strlow ;
	uint16_t str;
    const char *fontCode = luaL_checklstring(L, 1,&len);
    unsigned char size = luaL_checkinteger(L, 2);
	unsigned char font_g = luaL_checkinteger(L, 3);
	int x = luaL_checkinteger(L, 4);
	int y = luaL_checkinteger(L, 5);
	while ( i < len){
		strhigh = *fontCode;
		fontCode++;
		strlow = *fontCode;
		str = (strhigh<<8)|strlow;
		fontCode++;
		get_font(buf, 1, str, size*font_g, size*font_g, size*font_g);
		Gray_Process(buf,size,size,font_g);
		Gray_Display_hz(buf, x, y, size , size, font_g,  1);
		x+=size;
		i+=2;
	}
    return 0;
}

static int l_gtfont_utf8_display(lua_State* L) {
	unsigned char buf[128];
	int len;
	int i = 0;
	uint8_t strhigh,strlow ;
	uint16_t e,str;
    const char *fontCode = luaL_checklstring(L, 1,&len);
    unsigned char size = luaL_checkinteger(L, 2);
	int x = luaL_checkinteger(L, 3);
	int y = luaL_checkinteger(L, 4);
	for(;;){
        e = utf8_next((uint8_t)*fontCode);
        if ( e == 0x0ffff )
        break;
        fontCode++;
        if ( e != 0x0fffe ){
			uint16_t str = unicodetogb2312(e);
			get_font(buf, 1, str, size, size, size);
			Display_W(buf , x ,y , size , 32);
        	x+=size;    
        }
    }
    return 0;
}

static int l_gtfont_utf8_display_gray(lua_State* L) {
	unsigned char buf[2048];
	int len;
	int i = 0;
	uint8_t strhigh,strlow ;
	uint16_t e,str;
    const char *fontCode = luaL_checklstring(L, 1,&len);
    unsigned char size = luaL_checkinteger(L, 2);
	unsigned char font_g = luaL_checkinteger(L, 3);
	int x = luaL_checkinteger(L, 4);
	int y = luaL_checkinteger(L, 5);
	for(;;){
        e = utf8_next((uint8_t)*fontCode);
        if ( e == 0x0ffff )
        break;
        fontCode++;
        if ( e != 0x0fffe ){
			uint16_t str = unicodetogb2312(e);
			get_font(buf, 1, str, size*font_g, size*font_g, size*font_g);
			Gray_Process(buf,size,size,font_g);
			Gray_Display_hz(buf, x, y, size , size, font_g,  1);
        	x+=size;    
        }
    }
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_gtfont[] =
{
    { "init" ,          l_gtfont_init , 0},
	{ "gb2312_display" ,          l_gtfont_gb2312_display , 0},
	{ "gb2312_display_gray" ,          l_gtfont_gb2312_display_gray , 0},
	{ "utf8_display" ,          l_gtfont_utf8_display , 0},
	{ "utf8_display_gray" ,          l_gtfont_utf8_display_gray , 0},
	{ NULL,             NULL ,        0}
};

LUAMOD_API int luaopen_gtfont( lua_State *L ) {
    luat_newlib(L, reg_gtfont);
    return 1;
}
