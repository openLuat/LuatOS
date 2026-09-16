#ifndef __LUAT_DISPLAY_SURFACE_H__
#define __LUAT_DISPLAY_SURFACE_H__


#include "luat_display.h"



typedef unsigned int SURF_COLOR;

#define MAKE_COLORREF(r,g,b)        (0xff << 24 | (SURF_COLOR)((((r << 8) | g) << 8) | b))//ARGB
#define MAKE_RGB888(r,g,b)          ((SURF_COLOR)((((r << 8) | g) << 8) | b))//RGB
#define MAKE_RGB565(r,g,b)          ((uint16_t)((((uint16_t)r&0xf8)<<8)|(((uint16_t)g&0xfc)<<3)|(((uint16_t)b&0xf8)>>3)))  ///< make RGB565 from r,g,b

/*平面的属性*/
typedef struct {
    int	w;          // surface width
    int	h;          // surface height
    int bpp;        // surface bpp
    void* pixels;   // 像素数据
    int pitch;      // 行间距
    enum disp_format fmt; // 颜色深度
    struct luat_display_area clip; // 剪裁区域
    void* reserv;   //用于扩展，保留字段

} SURFACE;


/***********************************************
*函数名称：blit_copy
*功    能：图形块拷贝
*入口参数：dest：目标内存指针
*         src：源内存指针
*         destpitch：目标内存间距
*         srcpitch：源内存间距
*         bytewidth：每个像素字节数
*         h：高度
*返 回 值：0：成功
*         -1：失败
*备    注：
************************************************/
int blit_copy(void* dest,void* src,uint32_t destpitch,uint32_t srcpitch,uint32_t bytewidth,uint32_t h);
/***********************************************
*函数名称：blit32to16
*功    能：32位颜色转换为16位颜色并绘制
*入口参数：dest：目标内存指针
*          dsrf：目标平面指针
*          src：源内存指针
*          ssrf：源平面指针
*          w：宽度
*          h：高度
*返 回 值：0：成功
*         -1：失败
*备    注：
************************************************/
int blit32to16( uint8_t* dest, SURFACE* dsrf, uint8_t* src, SURFACE* ssrf, int w, int h );
/***********************************************
*函数名称：luat_draw_set_display_target
*功    能：设置绘制目标平面为指定显示设备的绘制缓冲区，用于绘制到显示设备
*入口参数：display_id：显示设备ID
*返 回 值：0：成功
*         -1：失败
*备    注：
************************************************/
int luat_draw_set_display_target( struct luat_display* disp );
/***********************************************
*函数名称：draw_surface_rect
*功    能：绘制平面矩形区域
*入口参数：ssrf：源平面指针
*          dx：绘制x坐标
*          dy：绘制y坐标
*          sx：源x坐标
*          sy：源y坐标
*          w：宽度
*          h：高度
*返 回 值：0：成功
*         -1：失败
*备    注：
************************************************/
int luat_draw_surface_rect( SURFACE* ssrf, int dx, int dy, int sx, int sy, int w, int h );
/***********************************************
*函数名称：luat_draw_surface
*功    能：绘制平面
*入口参数：src_surf：源平面指针
*          dx：绘制x坐标
*          dy：绘制y坐标
*返 回 值：0：成功
*        -1：失败
*备    注：
************************************************/
int luat_draw_surface( SURFACE* src_surf, int dx, int dy );

#endif /*__LUAT_DISPLAY_SURFACE_H__*/
