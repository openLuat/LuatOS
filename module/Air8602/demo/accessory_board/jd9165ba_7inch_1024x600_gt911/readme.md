# Air8602 7寸 JD9165BA 显示+GT911 触摸测试

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责项目初始化、版本定义和任务调度
2. **display_test.lua** - 显示+触摸测试模块，包含供电、显示初始化、界面绘制、触摸初始化、背光点亮、触摸画点的完整测试流程

### 1.2 扩展库模块

1. **exd_jd9165ba_rgb** - JD9165BA 显示IC初始化扩展库，提供复位、RGB 时序配置、帧缓冲初始化 API

## 二、演示流程介绍

本 demo 按顺序执行完整测试流程：供电 → 显示初始化 → 界面绘制 → 触摸初始化 → 背光点亮 → 触摸画点

### 2.1 测试步骤说明

1. **供电与引脚配置** - I2C1 引脚复用（GPIO33/GPIO32），LCD_DISP（GPIO15）输出高电平使能显示
2. **显示初始化** - exd_jd9165ba_rgb.setup()，仅做显示 IC 初始化（复位 + RGB 时序 + 帧缓冲）
3. **界面绘制** - 深色背景 + 型号标题 + 测试提示文字
4. **触摸初始化** - i2c.setup + tp.init("gt911") + airui 绑定
5. **背光点亮** - PWM3 @1kHz 100% 亮度，界面就绪后点亮避免花屏
6. **触摸画点** - 按下处画绿色点，日志打印触摸坐标

### 2.2 重要说明：以下三项由 demo 自行控制，与显示IC初始化扩展库无关

- **供电**：I2C1 引脚复用（33/32）+ LCD_DISP（GPIO15）由 demo 自行控制
- **背光**：PWM3 @1kHz 由 demo 点亮
- **触摸**：GT911 触摸初始化（i2c.setup + tp.init + airui 绑定）由 demo 自行完成

扩展库只负责显示 IC 初始化（复位 + RGB 时序 + 帧缓冲），不操作供电引脚 pin_pwr、
背光引脚 pin_bl，显示初始化完成也不会自动开背光。

JD9165BA 为免初始化 IC：无 SPI 引脚、无寄存器序列，扩展库只做复位 + RGB 时序配置。
屏幕参数（7寸 1024x600 / 时序 140/20/160/20/3/12 / 50MHz，实测正常值）全默认，`pin_rst` 必传，本板传 GPIO15（LCD_DISP 兼复位脚）。
注意：规格书 5.2 参考时序（20/20/20/10/4/4 @51.2MHz）实测仅部分显示，勿用。

## 三、显示效果

上电后屏幕显示深色背景与型号标题 "Air8602 7寸 JD9165BA 显示+触摸测试"，触摸屏幕任意位置出现绿色点并打印坐标。

## 四、演示硬件环境

### 4.1 硬件清单

- Air8602 引擎主机 × 1（可通过[合宙引擎主机购买链接](https://item.taobao.com/item.htm?abbucket=0&id=1074653347178&mi_id=0000b1xKYCQ6FqNBvA6WFGn404uBMgGrEw_u5DrbOrfg8Ic&ns=1&skuId=6300230487015&spm=a21xtw.29978516.smart_flow.9.7e0a11700R2QoP&xxc=taobaoSearch) 进行购买
- 7寸 JD9165BA 1024x600 显示触摸模组（GT911 触摸） × 1
  demo所演示的7寸屏模组[购买链接](https://item.taobao.com/item.htm?app=chrome&bxsign=scd__hYeUd-jazHRi-rmwnoG_zCxk3dqXuz9N6O9K1nACEwYsJTPcJklP0k10cTLcGfzVtYBBmIql_xavelhUo3qDQ7ZNZxmotg2mDeEeb1-HxCX7OdUP_cuoFzgLFGlP3D&cpp=1&h5_spm=a-tb-item.b-tb-item&id=737749970460&share_crt_v=1&shareurl=true&short_name=h.8ycKtrfLpmQyms8&sp_tk=c3RNOFRvNnpvTEk%3D&spm=a2159r.13376460.0.0&tbSocialPopKey=shareItem&tk=stM8To6zoLI&un=09fb5e1342de04133dd3af49e2902fce&un_site=0&ut_sk=1.YiMl5CIMWcUDAOqt7t7%2FT74j_21646297_1790891217122.TaoPassword-WeiXin.1&wxsign=tbwCmE-JxpwI0ieXA-Ic_Xk6VFMhNzwcInrLBoiNM7GleXtrdtV9QRjdwwibWf1IWRFyip5msrxtp0SHwTxVIIsKPivVvtmtr6XwOjhoCiNrsp3ExTrUhx1GM7siBXQZHmo&x-ssr=true&skuId=5467613933583)
- TYPE-C 数据线 × 1

### 4.2 接线配置

#### 4.2.1 板级关键引脚

<table>
<tr>
<td>信号<br/></td><td>Air8602 引脚<br/></td><td>说明<br/></td></tr>
<tr>
<td>LCD_DISP<br/></td><td>GPIO15<br/></td><td>显示使能，兼 LCD 复位脚<br/></td></tr>
<tr>
<td>I2C1_CLK<br/></td><td>GPIO33<br/></td><td>触摸 I2C 时钟<br/></td></tr>
<tr>
<td>I2C1_SDA<br/></td><td>GPIO32<br/></td><td>触摸 I2C 数据<br/></td></tr>
<tr>
<td>TP_RESET<br/></td><td>GPIO72<br/></td><td>触摸复位<br/></td></tr>
<tr>
<td>TP_INT<br/></td><td>GPIO51<br/></td><td>触摸中断<br/></td></tr>
<tr>
<td>背光<br/></td><td>PWM3<br/></td><td>背光调光，1kHz<br/></td></tr>
</table>

> 说明：以上为板级固定接线，由 Engine_Air8602 底板完成，模组插入即可，无需杜邦线。

## 五、演示软件环境

### 5.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air1601/luatos/common/download/) - 固件烧录和代码调试

### 5.2 内核固件

- [Air1602固件版本](https://docs.openluat.com/air1601/luatos/firmware/1602_version/)，demo 所使用的是 LuatOS-SoC_V1028_Air1602_102.soc

### 5.3 脚本文件

1. **main.lua** - 主程序入口
2. **display_test.lua** - 显示+触摸测试模块
3. **exd_jd9165ba_rgb.lua** - JD9165BA 显示IC初始化扩展库

## 六、演示核心步骤

### 6.1 硬件准备

1. 将 7 寸显示触摸模组接到 Air8602 底板的屏幕接口
2. 通过 TYPE-C USB 口供电
3. 检查模组排线连接无误，避免接触不良

### 6.2 软件配置

在 `main.lua` 中加载对应的测试模块：

```lua
-- 加载 display_test.lua 显示+触摸测试模块
require "display_test"

```

### 6.3 软件烧录

1. 使用 Luatools 选择上述内核固件（LuatOS-SoC_V1028_Air1602_102.soc）
2. 下载本项目所有脚本文件
3. 将固件和脚本一起烧录到设备
4. 烧录成功后设备自动重启后开始运行

### 6.4 功能测试

#### 6.4.1 显示测试

1. 设备上电后自动执行供电、显示初始化、界面绘制、背光点亮
2. 观察屏幕显示深色背景 + "Air8602 7寸 JD9165BA 显示+触摸测试" 标题
3. 检查显示是否完整，有无花屏、显示不全

#### 6.4.2 触摸画点测试

1. 触摸屏幕任意位置
2. 观察按下处出现绿色点
3. 查看日志输出触摸坐标

### 6.5 预期效果

- **显示**：屏幕点亮，深色背景 + 型号标题显示完整
- **触摸**：触摸画点正常，绿色点跟随手指位置出现，日志打印坐标
- **日志如下（关键输出）：**
```lua
I/user.main Engine_Air8602_7inch_1024x600_010_V000 001.000.001
I/user.display_test 显示初始化完成 display 1024 600
I/user.display_test 背光已点亮
I/user.display_test 测试就绪，请触摸屏幕
I/user.display_test 触摸按下 512 300
```

### 6.6 故障排除

1. **屏幕不亮**：

   - 检查 LCD_DISP（GPIO15）是否输出高电平
   - 确认模组排线连接可靠
   - 确认背光已点亮（PWM3）

2. **显示不全或花屏**：

   - 确认使用实测时序 140/20/160/20/3/12 @50MHz（规格书 5.2 参考时序实测仅部分显示，勿用）

3. **触摸无响应**：

   - 检查 I2C1 引脚复用（GPIO33/GPIO32）与 TP_RESET（GPIO72）、TP_INT（GPIO51）
   - 确认 tp.init("gt911") 返回成功，查看日志"触摸初始化失败"报错

4. **背光不亮**：

   - 确认 PWM 通道与原理图一致（本板 PWM3）
