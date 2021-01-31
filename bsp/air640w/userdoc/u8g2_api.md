***u8g2显示屏初始化***

*@api u8g2.begin("ssd1306")*

*@string 配置信息*

*@return int 正常初始化1,已经初始化过2,内存不够3,初始化失败返回4*

*@usage*

*-- 初始化i2c1的ssd1306*

*u8g2.begin("ssd1306")*



***关闭显示屏***

*@api u8g2.close()* 

*@usage*

*-- 关闭disp,再次使用disp相关API的话,需要重新初始化*

*u8g2.close()*



**清屏**

*@api u8g2.ClearBuffer() 清除内存帧缓冲区中的所有像素。*

*@usage*

*u8g2.ClearBuffer()*



**数据更新到屏幕**

*@api u8g2.SendBuffer() 将存储器帧缓冲区的内容发送到显示器。*

*@usage*

*u8g2.SendBuffer()*



**在显示屏上画一段文字**

*@api u8g2.DrawUTF8(str, x, y)* *在显示屏上画一段文字,要调用u8g2.SendBuffer()才会更新到屏幕*

*@string 文件内容*

*@int 横坐标*

*@int 竖坐标*

*@usage*

*u8g2.DrawUTF8("wifi is ready", 10, 20)*



***设置字体模式***

*@api u8g2.SetFontMode(mode)*

*@int mode字体模式，启用（1）或禁用（0）透明模式*

*@usage*

*u8g2.SetFontMode(1)*



***设置字体***

*@api u8g2.SetFont(font)*

*@string font, "u8g2_font_ncenB08_tr"为纯英文8x8字节,"u8g2_font_wqy12_t_gb2312"为12x12全中文,"u8g2_font_unifont_t_symbols"为符号.*

*@usage*

*-- 设置为中文字体,对之后的drawStr有效,使用中文字体需在luat_base.h开启#define USE_U8G2_WQY12_T_GB2312*

*u8g2.setFont("u8g2_font_wqy12_t_gb2312")*



***获取显示屏高度***

*@api u8g2.GetDisplayHeight()*

*@return int 显示屏高度*

*@usage*

u8g2.GetDisplayHeight()



***获取显示屏宽度***

*@api u8g2.GetDisplayWidth()*

*@return int 显示屏宽度*

*@usage*

u8g2.GetDisplayWidth()



***在两点之间画一条线.***

*@api u8g2.DrawLine(x0,y0,x1,y1)*

*@int 第一个点的X位置.*

*@int 第一个点的Y位置.*

*@int 第二个点的X位置.*

*@int 第二个点的Y位置.*

*@usage*

*u8g2.DrawLine(20, 5, 5, 32)*



***在x,y位置画一个半径为rad的空心圆.***

*@api u8g2.DrawCircle(x0,y0,rad,opt)*

*@int 圆心位置*

*@int 圆心位置*

*@int 圆半径.*

*@int 选择圆的部分或全部.*

*右上： 0x01*

*左上： 0x02*

*左下： 0x04*

*右下： 0x08*

*完整圆： (0x01|0x02|0x04|0x08)*

*@usage*

*u8g2.DrawCircle(60,30,8,15)*



***在x,y位置画一个半径为rad的实心圆.***

*@api u8g2.DrawDisc(x0,y0,rad,opt)*

*@int 圆心位置*

*@int 圆心位置*

*@int 圆半径.*

*@int 选择圆的部分或全部.*

*右上： 0x01*

*左上： 0x02*

*左下： 0x04*

*右下： 0x08*

*完整圆： (0x01|0x02|0x04|0x08)*

*@usage*

*u8g2.DrawDisc(60,30,8,15)*



***在x,y位置画一个半径为rad的空心椭圆.***

*@api u8g2.DrawEllipse(x0,y0,rx,ry,opt)*

*@int 圆心位置*

*@int 圆心位置*

*@int 椭圆大小*

*@int 椭圆大小*

*@int 选择圆的部分或全部.*

*右上： 0x01*

*左上： 0x02*

*左下： 0x04*

*右下： 0x08*

*完整圆： (0x01|0x02|0x04|0x08)*

*@usage*

*u8g2.DrawEllipse(60,30,8,15)*



***在x,y位置画一个半径为rad的实心椭圆.***

*@api u8g2.DrawFilledEllipse(x0,y0,rx,ry,opt)*

*@int 圆心位置*

*@int 圆心位置*

*@int 椭圆大小*

*@int 椭圆大小*

*@int 选择圆的部分或全部.*

*右上： 0x01*

*左上： 0x02*

*左下： 0x04*

*右下： 0x08*

*完整圆： (0x01|0x02|0x04|0x08)*

*@usage*

*u8g2.DrawFilledEllipse(60,30,8,15)*



***从x / y位置（左上边缘）开始绘制一个框（填充的框）.***

*@api u8g2.DrawBox(x,y,w,h)*

*@int 左上边缘的X位置*

*@int 左上边缘的Y位置*

*@int 盒子的宽度*

*@int 盒子的高度*

*@usage*

*u8g2.DrawBox(3,7,25,15)*



***从x / y位置（左上边缘）开始绘制一个框（空框）.***

*@api u8g2.DrawFrame(x,y,w,h)*

*@int 左上边缘的X位置*

*@int 左上边缘的Y位置*

*@int 盒子的宽度*

*@int 盒子的高度*

*@usage*

*u8g2.DrawFrame(3,7,25,15)*



***绘制一个从x / y位置（左上边缘）开始具有圆形边缘的填充框/框架.***

*@api u8g2.DrawRBox(x,y,w,h,r)*

*@int 左上边缘的X位置*

*@int 左上边缘的Y位置*

*@int 盒子的宽度*

*@int 盒子的高度*

*@int 四个边缘的半径*

*@usage*

*u8g2.DrawRBox(3,7,25,15)*



***绘制一个从x / y位置（左上边缘）开始具有圆形边缘的空框/框架.***

*@api u8g2.DrawRFrame(x,y,w,h,r)*

*@int 左上边缘的X位置*

*@int 左上边缘的Y位置*

*@int 盒子的宽度*

*@int 盒子的高度*

*@int 四个边缘的半径*

*@usage*

*u8g2.DrawRFrame(3,7,25,15)*



***绘制一个图形字符。字符放置在指定的像素位置x和y.***

*@api u8g2.DrawGlyph(x,y,encoding)*

*@int 字符在显示屏上的位置*

*@int 字符在显示屏上的位置*

*@int 字符的Unicode值*

*@usage*

*u8g2.SetFont(u8g2_font_unifont_t_symbols)*

*u8g2.DrawGlyph(5, 20, 0x2603)  -- dec 9731/hex 2603 Snowman* 



***绘制一个三角形（实心多边形）.***

*@api u8g2.DrawTriangle(x0,y0,x1,y1,x2,y2)*

*@int 点0X位置*

*@int 点0Y位置*

*@int 点1X位置*

*@int 点1Y位置*

*@int 点2X位置*

*@int 点2Y位置*

*@usage*

*u8g2.DrawTriangle(20,5, 27,50, 5,32)*



***定义位图函数是否将写入背景色***

*@api u8g2.SetBitmapMode(mode)*

*@int mode字体模式，启用（1）或禁用（0）透明模式*

*@usage*

*u8g2.SetBitmapMode(1)*

