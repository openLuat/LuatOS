#include "luat_display.h"
#include "luat_display_surface.h"

/* 当前绘制目标平面，由调用方选择，luat_draw_surface_rect 绘制到其上 */
static SURFACE g_targetsurface = {0};



/***********************************************
*函数名称：check_clipwindow
*功    能：检查剪裁区域是否超出平面边界
*入口参数：dsrf：目标平面指针
*          dx：绘制x坐标
*          dy：绘制y坐标
*          sx：源x坐标
*          sy：源y坐标
*          w：宽度
*          h：高度
*返 回 值：1：超出超出平面边界
*         0：未超出平面边界
*备    注：
************************************************/
static int check_clipwindow(SURFACE* dsrf,int* dx, int* dy,int* sx,int* sy,int* w,int* h)
{
    int diff;
    
    if(*dx < dsrf->clip.x1){
        diff = dsrf->clip.x1 - *dx;
        *dx = dsrf->clip.x1;
        *sx += diff;
        *w -= diff;
        if(*w <= 0){
            return 1;
        }
    }

    if(*dy < dsrf->clip.y1){
        diff = dsrf->clip.y1 - *dy;
        *dy = dsrf->clip.y1;
        *sy += diff;
        *h -= diff;
        if(*h <= 0){
            return 1;
        }
    }

    if((*dx + *w)>dsrf->clip.x2){
        diff = (*dx + *w) - dsrf->clip.x2;
        *w -= diff;
        if(*w <= 0){
            return 1;
        }
    }

    if((*dy + *h)>dsrf->clip.y2){
        diff = (*dy + *h) - dsrf->clip.y2 ;
        *h -= diff;
        if(*h <= 0){
            return 1;
        }
    }

    return 0;
}


#ifdef LUAT_BSP_PC

/***********************************************
*函数名称：blit_copy
*功    能：图形块拷贝
*入口参数：dest：目标内存指针
*          src：源内存指针
*          destpitch：目标内存间距
*          srcpitch：源内存间距
*          bytewidth：每个像素字节数
*          h：高度
*返 回 值：0：成功
*         -1：失败
*备    注：
************************************************/
int blit_copy(void* dest,void* src,uint32_t destpitch,uint32_t srcpitch,uint32_t bytewidth,uint32_t h)
{
    uint32_t srcoffset;
    uint32_t destoffset;

    srcoffset   = srcpitch - bytewidth;
    destoffset  = destpitch - bytewidth;
    srcoffset  += bytewidth;
    destoffset += bytewidth;
  
    while(h--){
        memcpy( dest, src, bytewidth);
        dest += destoffset;
        src  += srcoffset;
    }
    
    return 0;
}

#endif


/***********************************************
*函数名称：luat_draw_set_display_target
*功    能：设置绘制目标平面为指定显示设备的绘制缓冲区，用于绘制到显示设备
*入口参数：display_id：显示设备ID
*返 回 值：0：成功
*         -1：失败
*备    注：
************************************************/
int luat_draw_set_display_target( struct luat_display* disp )
{
    SURFACE* dsrf = &g_targetsurface;

    if(disp == NULL){
        return -1;
    }
    if(disp->fb_info == NULL || disp->fb_info->draw_buf.buffer == NULL){
        return -1;
    }

    dsrf->pixels = disp->fb_info->draw_buf.buffer;
    dsrf->pitch = disp->fb_info->draw_buf.stride;
    dsrf->w = disp->fb_info->draw_buf.width;
    dsrf->h = disp->fb_info->draw_buf.height;
    dsrf->bpp = disp->fb_info->bits_per_pixel;
    dsrf->fmt = disp->fb_info->format;

    dsrf->clip.x1 = 0;
    dsrf->clip.y1 = 0;
    dsrf->clip.x2 = dsrf->w;
    dsrf->clip.y2 = dsrf->h;

    return 0;
}
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
int luat_draw_surface_rect( SURFACE* ssrf, int dx, int dy, int sx, int sy, int w, int h )
{
    uint8_t* src;
    uint8_t* dest;
    SURFACE* dsrf = &g_targetsurface;

    if( dy >= dsrf->h ){
        return -1;
    }
    if( dx >= dsrf->w ){
        return -1;
    }
    if( ( dsrf->w - dx ) < w ){
        w = dsrf->w - dx;
    }
    if( ( dsrf->h - dy ) < h ){
        h = dsrf->h - dy;
    }

    if( !(( dsrf->bpp == 16 ) || ( dsrf->bpp == 32 )) ){
        return -1;
    }

    if( check_clipwindow( dsrf, &dx, &dy, &sx, &sy, &w, &h ) ){
        return -1;
    }

    src  = (uint8_t*)((uint32_t)ssrf->pixels) + (ssrf->pitch * sy) + (sx * (ssrf->bpp / 8));
    dest = (uint8_t*)((uint32_t)dsrf->pixels) + (dsrf->pitch * dy) + (dx * (dsrf->bpp / 8));
    
    if( ( dsrf->bpp == ssrf->bpp ) && ( dsrf->fmt == ssrf->fmt ) ){
       return blit_copy( dest, src, dsrf->pitch, ssrf->pitch, w * ( dsrf->bpp / 8 ), h );
    }else{	
        if( dsrf->bpp == 16 )
        {
            if( ssrf->bpp == 32 )
            {
                return 0;//blit32to16( dest, dsrf, src, ssrf, w, h ); //待实现
            }//ssrf->bpp==32
            else if( ssrf->bpp == 8 )
            {
                return 0;//blit8to16( dest, dsrf, src, ssrf, w, h ); //待实现
            } // end ssrf->bpp==8
        }
        else if( dsrf->bpp == 32 )
        {
          if(dsrf->fmt == LUAT_DISPLAY_FORMAT_RGB888 )
          {				
            return 0;//blit32to32( dest, dsrf, src, ssrf, w, h ); //待实现
          }
          else if(ssrf->bpp == 8)
          {			
            return 0;//blit8to32( dest, dsrf, src, ssrf, w, h ); //待实现
          }
        }
    }
    
    return 0;
}

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
int luat_draw_surface( SURFACE* src_surf, int dx, int dy )
{
    return luat_draw_surface_rect( src_surf, dx, dy, 0, 0, src_surf->w, src_surf->h );
}


