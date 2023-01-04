/*
 *创建时间：2020-03-27
 *创建人：	yang
**/
#ifndef _GT5SLCD2E_1A_H_
#define _GT5SLCD2E_1A_H_

/* 外部函数声明 */
extern unsigned long r_dat_bat(unsigned long address,unsigned long DataLen,unsigned char *pBuff);
extern unsigned char gt_read_data(unsigned char* sendbuf , unsigned char sendlen , unsigned char* receivebuf, unsigned int receivelen);

extern unsigned char CheckID(unsigned char CMD, unsigned long address,unsigned long byte_long,unsigned char *p_arr);
/* ----------------------------------------------------------- */
//字库初始化
int GT_Font_Init(void);

/********************* 矢量公用部分 *********************/
//中文
#define VEC_SONG_STY		1		//宋体

//ASCII码
#define VEC_FT_ASCII_STY 	5
#define VEC_DZ_ASCII_STY 	6
#define VEC_CH_ASCII_STY 	7
#define VEC_BX_ASCII_STY 	8
#define VEC_BZ_ASCII_STY 	9
#define VEC_FX_ASCII_STY 	10
#define VEC_GD_ASCII_STY 	11
#define VEC_HZ_ASCII_STY 	12
#define VEC_MS_ASCII_STY 	13
#define VEC_SX_ASCII_STY 	14
#define VEC_ZY_ASCII_STY 	15
#define VEC_TM_ASCII_STY 	16
//拉丁文
#define VEC_YJ_LATIN_STY	17

/******************* 两种调用模式配置 *******************/

/**
 * 方式一 VEC_ST_MODE : 通过使用声明VECFONT_ST结构体变量, 配置结构体信息,
 *   获取点阵数据到zk_buffer[]数组中.
 * 方式二 VEC_PARM_MODE : 通过指定参数进行调用, 获取点阵数据到pBits[]数组中.
 * ps: 两种方式可同时配置使用, 择一使用亦可.
*/
#define VEC_ST_MODE
#define VEC_PARM_MODE

/********************* 分割线 *********************/

#ifdef VEC_ST_MODE

    #define ZK_BUFFER_LEN   4608    //可修改大小, 约等于 字号*字号/8.

    typedef struct vecFont
    {
        unsigned long fontCode;		//字符编码中文:GB18030, ASCII/外文: unicode
        unsigned char type;			//字体	@矢量公用部分
        unsigned char size;			//文字大小
        unsigned char thick;		//文字粗细
        unsigned char zkBuffer[ZK_BUFFER_LEN];	//数据存储
    }VECFONT_ST;

    unsigned int get_font_st(VECFONT_ST * font_st);
#endif

#ifdef VEC_PARM_MODE
	/*
	 *函数名：	get_font()
	 *功能：		矢量文字读取函数
	 *参数：pBits		数据存储
	 *		sty			文字字体选择  @矢量公用部分
	 *		fontCode	字符编码中文:GB18030, ASCII/外文: unicode
	 *		width		文字宽度
	 *		height		文字高度
	 *		thick		文字粗细
	 *返回值：文字显示宽度
	**/
    unsigned int get_font(unsigned char *pBits,unsigned char sty,unsigned long fontCode,unsigned char width,unsigned char height, unsigned char thick);
#endif
/********************* 矢量区域结束 *********************/


/*
 *函数名：	get_Font_Gray()
 *功能		灰度矢量文字读取函数
 *参数：pBits		数据存储
 *		sty			文字字体选择  @矢量公用部分
 *		fontCode	字符编码中文:GB18030, ASCII/外文: unicode
 *		fontSize	文字大小
 *		thick		文字粗细
 *返回值：re_buff[0] 字符的显示宽度 , re_buff[1] 字符的灰度阶级[1阶/2阶/3阶/4阶]
**/
unsigned int* get_Font_Gray(unsigned char *pBits,unsigned char sty,unsigned long fontCode,unsigned char fontSize, unsigned char thick);

//Unicode转GBK
unsigned long  U2G(unsigned int  unicode);	
//BIG5转GBK
unsigned int BIG52GBK( unsigned char h,unsigned char l );

/*----------------------------------------------------------------------------------------
 * 灰度数据转换函数 2阶灰度/4阶灰度
 * 说明 : 将点阵数据转换为灰度数据 [eg:32点阵数据转2阶灰度数据则转为16点阵灰度数据]
 * 参数 ：
 *   OutPutData灰度数据;	 width 宽度; High 高度;	grade 灰度阶级[1阶/2阶/3阶/4阶]
 *------------------------------------------------------------------------------------------*/
void Gray_Process(unsigned char *OutPutData ,int width,int High,unsigned char Grade);

/*----------------------------------------------------------------------------------------
 * 灰度文字颜色设置
 * BmpDst 目标图片数据
 * BmpSrc 图标图片数据
 * WORD x, WORD y, 图标在目标图片的 X,Y位置。
 * WORD src_w, WORD src_h,  图标的宽度和高度
 * WORD dst_w, WORD dst_h   目标图片的宽度和高度
 * SrcGray 灰度文字数据
 * Grade	灰度阶级[2阶/4阶]
 *------------------------------------------------------------------------------------------*/
void AlphaBlend_whiteBC(unsigned char *BmpDst,unsigned char *BmpSrc, int x, int y,
	int src_w, int src_h, int dst_w, int dst_h,unsigned char *SrcGray,unsigned char Grade);

/*----------------------------------------------------------------------------------------
 * 灰度文字与背景混合
 * BmpDst 目标图片数据
 * BmpSrc 图标图片数据
 * WORD x, WORD y, 图标在目标图片的 X,Y位置。
 * WORD src_w, WORD src_h,  图标的宽度和高度
 * WORD dst_w, WORD dst_h   目标图片的宽度和高度
 * SrcGray 灰度文字数据
 * Grade	灰度阶级[2阶/4阶]
 *------------------------------------------------------------------------------------------*/
void AlphaBlend_blackBC(unsigned char *BmpDst,unsigned char *BmpSrc, int x, int y,
	int src_w, int src_h, int dst_w, int dst_h,unsigned char *SrcGray,unsigned char Grade);


#endif

/*--------------------------------------- end of file ---------------------------------------------*/
