#include "luat_base.h"
#include "luat_spi.h"
#include "luat_lcd.h"

#include "GT5SLCD2E_1A.h"
#define LUAT_LOG_TAG "gt"
#include "luat_log.h"

extern luat_spi_device_t* gt_spi_dev;
static luat_lcd_conf_t* lcd_conf;

/*横置横排打点函数 -----------------------------------------------------------------*/
void WriteData( uint16_t Xpos, uint16_t Ypos, uint8_t data, uint16_t charColor, uint16_t bkColor,uint8_t sizeType)
{
		uint16_t j,i;
		unsigned char count=0;
		for( j=0; j<8; j++ )
		{
				if( ((data >> (7-j))&0x01)== 0x01 ){
						for(count=0;count<sizeType;count++){
							for(i=0;i<sizeType;i++){
								// LCD_SetPoint( Xpos + sizeType*j+count, Ypos+i, charColor );	//修改此函数
                                luat_lcd_draw_point(lcd_conf, Xpos + sizeType*j+count, Ypos+i, charColor);
							}
						}
				}
				else{
						for(count=0;count<sizeType;count++){
							for(i=0;i<sizeType;i++){
								// LCD_SetPoint( Xpos + sizeType*j+count, Ypos+i, bkColor );	//修改此函数
                                // luat_lcd_draw_point(lcd_conf, Xpos + sizeType*j+count, Ypos+i, bkColor);
							}
						}    
				}
		}
}

/********º横置横排显示函数************/
void DisZK_DZ_W(uint16_t Xpos, uint16_t Ypos, uint16_t W,uint16_t H, uint16_t charColor, uint16_t bkColor,uint8_t*DZ_Data,uint8_t sizeType)
{
	static uint16_t Vertical,Horizontal;
	uint32_t bit=0;
	Vertical=Ypos;
    Horizontal=Xpos; 
	for(bit=0;bit<((W+7)/8*H);bit++) //data sizeof (byte)
	{
				if((bit%((W+7)/8)==0)&&(bit>0))//W/8 sizeof
				{
						Vertical+=sizeType;
						Horizontal=Xpos;
				}
				else if(bit>0)
					Horizontal+=sizeType*8; 
				
				WriteData(Horizontal,Vertical,DZ_Data[bit],charColor,bkColor,sizeType);
	}
}

unsigned char pBits[512];

void show_char(unsigned char *text,unsigned int x,unsigned int y)
{
	while(*text!='\0')//判断是否是结尾
	{
		if(*text<0x80){  //ASCII 码 *text是ASCII码
			// ASCII_GetData(*text, ASCII_8X16_A, pBits);	//示例, 按实际函数名进行修改
			DisZK_DZ_W(x,y,8,16, BLACK, WHITE,pBits,1);  //显示8X16点ASCII函数
			x=x+8;
		}else{  //汉字编码*text是汉字编码的高位，*(text+1)是汉字编码的低位
			// gt_16_GetData(*text, *(text+1),pBits);	//示例, 按实际函数名进行修改
            get_font(pBits, 1, *text, 32, 32, 32);
			DisZK_DZ_W(x,y,16,16, BLACK, WHITE,pBits,1);  //显示汉字
			x=x+16;
			text++;
		}
		text++;
	}
}

static int l_gtfont_init(lua_State* L) {
    if (gt_spi_dev == NULL) {
        gt_spi_dev = lua_touserdata(L, 1);
    }
    lcd_conf = luat_lcd_get_default();
    return 0;
}

static VECFONT_ST fst;
unsigned char jtwb[128]="收款退款交易查询终端管理";	//每个中文字符实际由两个字节组成, 对应GBK等编码

static int l_gtfont_test(lua_State* L) {
    size_t len;
    unsigned char *fontCode = luaL_checklstring(L, 1,&len);
    unsigned char size = luaL_checkinteger(L, 2);
    unsigned char thick = luaL_checkinteger(L, 3);
    LLOGD("fontCode %04x size %d thick %d", *fontCode, size, thick);
    unsigned char buf[128];
    int ret = get_font(buf, 1, 0xb0a1, size, size, thick);
    LLOGD("get_font_st ret %d", ret);
    // unsigned char zk_buff[256]; //自定义点阵数据空间大小
	// gt_16_GetData(0xb0, 0xa1, zk_buff);	//获取点阵数据
	DisZK_DZ_W(0, 0, 32, 32, BLACK, WHITE, buf, 1);	//显示函数
    // TODO 按位显示出来
    // show_char(jtwb,0,0);
    return 0;
}



#include "rotable.h"
static const rotable_Reg reg_gtfont[] =
{
    { "init" ,          l_gtfont_init , 0},
    { "test" ,          l_gtfont_test , 0},
	{ NULL,             NULL ,        0}
};

LUAMOD_API int luaopen_gtfont( lua_State *L ) {
    luat_newlib(L, reg_gtfont);
    return 1;
}
