## 一、功能模块介绍

### 1.1 核心主程序模块
1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - 硬件初始化模块，集中配置 SPI、LCD 和背光，供所有演示模块共用。

### 1.2 演示模块（三选一运行）
3. **hzfont_demo.lua**  - HZFont 内置矢量字库演示，展示不同字号、颜色、抗锯齿的矢量字体。
4. **image_demo.lua**   - 图片显示演示，从文件系统加载 JPG 图片并在屏幕上显示。
5. **draw_demo.lua**    - 基本图形绘制演示，展示点、线、矩形、圆和文字绘制功能。


## 二、演示硬件环境
参考：[硬件环境清单](https://docs.openluat.com/air1601/luatos/common/hwenv/)，准备以及组装好硬件环境。

显示屏接线
<table>
<tr>
<td>Air1601开发板 <br/></td><td>AirLCD_1010配件板<br/></td></tr>
<tr>
<td>GND<br/></td><td>GND<br/></td></tr>
<tr>
<td>VDD 3.3<br/></td><td>VCC<br/></td></tr>
<tr>
<td>SPI1_CLK<br/></td><td>SCLK/CLK<br/></td></tr>
<tr>
<td>SPI1_MOSI<br/></td><td>SDA/MOS<br/></td></tr>
<tr>
<td>gpio3(U1RX)<br/></td><td>RST<br/></td></tr>
<tr>
<td>gpio2(U1TX)<br/></td><td>DC/RS<br/></td></tr>
<tr>
<td>SPI1_CS<br/></td><td>CS<br/></td></tr>
<tr>
<td>GPIO54(U2TX)<br/></td><td>BLK<br/></td></tr>
<tr>
</table>


## 三、 **演示软件环境**

1.[Luatools 工具](https://docs.openluat.com/air780epm/common/Luatools/)；

2.内核固件文件（底层 core 固件文件）：[LuatOS-SoC_V1004_Air1601.soc](https://docs.openluat.com/air1601/luatos/firmware/) ；


## 四、演示核心步骤
1. 按照硬件接线表连接所有设备
2. 确保电源连接正确，通过TYPE-C USB口供电
3. 检查所有接线无误，避免短路
4. 在`main.lua`中选择加载对应的演示模块：

烧录成功后，代码会自动运行，查看打印日志，如果正常运行，会打印串口初始化和串口收发数据等相关信息。

**image_demo.lua：**
```lua
[2026-03-06 19:48:01.131][LTOS/N][000000000.651]:I/user.ui_main LCD初始化成功
[2026-03-06 19:48:01.137][LTOS/N][000000000.660]:D/heap skip ROM free 1470068b
[2026-03-06 19:48:01.137][LTOS/N][000000000.660]:D/heap skip ROM free 147008fd
[2026-03-06 19:48:01.142][LTOS/N][000000000.662]:I/user.image_demo 项目: LCD_demo 001.000.000
[2026-03-06 19:48:01.147][LTOS/N][000000000.663]:D/heap skip ROM free 1470007a
[2026-03-06 19:48:01.147][LTOS/N][000000000.663]:D/heap skip ROM free 14700491
[2026-03-06 19:48:01.239][LTOS/N][000000000.763]:I/user.image_drv 找到图片文件: /luadb/picture.jpg
```

**hzfont_demo.lua**:
```lua
[2026-03-06 19:50:30.667][LTOS/N][000000000.650]:I/user.ui_main LCD初始化成功
[2026-03-06 19:50:30.675][LTOS/N][000000000.660]:D/heap skip ROM free 147008aa
[2026-03-06 19:50:30.679][LTOS/N][000000000.660]:D/heap skip ROM free 14700b1c
[2026-03-06 19:50:30.684][LTOS/N][000000000.662]:W/hzfont hzfont event=init cache_size_invalid=0 use_default=256
[2026-03-06 19:50:30.689][LTOS/N][000000000.663]:I/hzfont font loaded units_per_em=1000 glyphs=7617
```

**draw_demo.lua**
```lua
[2026-03-06 19:52:49.613][LTOS/N][000000000.651]:I/user.ui_main LCD初始化成功
[2026-03-06 19:52:49.623][LTOS/N][000000000.660]:D/heap skip ROM free 14700648
[2026-03-06 19:52:49.623][LTOS/N][000000000.660]:D/heap skip ROM free 147008ba
[2026-03-06 19:52:49.628][LTOS/N][000000000.662]:I/user.draw_demo 项目: LCD_demo 001.000.000
[2026-03-06 19:52:49.633][LTOS/N][000000000.663]:D/heap skip ROM free 14700078
[2026-03-06 19:52:49.633][LTOS/N][000000000.663]:D/heap skip ROM free 1470044f
[2026-03-06 19:52:50.070][LTOS/N][000000001.131]:I/user.draw_drv 图形绘制完成
```