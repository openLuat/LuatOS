--[[ 
说明：
customer_font_drv是用户外部自定义外部点阵字体驱动功能模块,因为不需要进行初始化，所以本文件没有任何实质代码，只在此处描述在项目中如何使用。
自定义字体制作说明可以参考lcd核心库自定义字体制作说明：https://docs.openluat.com/osapi/core/lcd/#_6
1、通过链接 https://gitee.com/Dozingfiretruck/u8g2_font_tool 下载字体文件制作工具
2、制作字体
   - 将.ttf和.otf格式字体加载到制作工具内
   - 选择自定义，输入需要生成的字体内容，调用自定义文字显示接口只能显示所输入的内容，其他内容需要切换支持的字体
   - 选择其他，则会按苏哦选编码格式生成对应的字体
   - 设置字体大小，生成合宙lcd核心库可加载的.bin格式的字体文件
3、使用lcd.setFontFile(font)接口设置
   - 其中font为字体文件路径
   - 若将生成的字体文件命名为customer_font_24.bin 并通过luatools工具同代码一起烧录到脚本分区，则设置接口为lcd.setFontFile("/luadb/customer_font_24.bin")
   - 若将生成的字体文件命名为customer_font_24.bin 并通过luatools工具同固件和代码一起烧录到文件系统，则设置接口为lcd.setFontFile("/customer_font_24.bin")
4、使用lcd.drawStr(x,y,str,fg_color)接口显示具体内容
]]