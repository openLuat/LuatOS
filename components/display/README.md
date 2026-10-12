# LuatOS Display - 新一代显示抽象层

> 本文档介绍 `display` 库的技术背景：说明旧 `lcd` 库存在的问题，以及新 `display` 库解决了哪些问题。

## 1. 背景

LuatOS 早期通过 `lcd` 模块（`components/lcd`）驱动各类屏幕，积累了丰富的驱动型号（ST7789、ILI9341、NV3052C 等）与绘图 API（画点、画线、画圆、字体、二维码、图片显示等）。但随着产品从 SPI 小屏扩展到 RGB 大屏、MIPI-DSI、LVDS 等更高规格的显示链路，`lcd` 库在设计上暴露出一些结构性限制，难以满足多屏、直接渲染（DIRECT Rendering）和硬件加速显示控制器的需求。为此引入了新一代 `display` 显示抽象层（`components/display`），从架构层面解决这些问题。

## 2. LCD 库存在的问题

**① 面板驱动与物理接口耦合**
每个屏幕型号的驱动（如 `st7789`、`ili9341`）与所用物理接口（SPI/QSPI）强绑定，接口细节硬编码在驱动内部。同一个屏幕 IC 若要换一种接口接法，往往需要重写或复制驱动，扩展成本高、代码重复。

**② 单一全局实例，不支持多屏**
`lcd` 依赖单个全局显示配置（`lcd_dft_conf`），同一时间基本只能管理一块屏。双屏、拼接屏等场景没有原生支持。

**③ 面向 SPI 小屏，缺乏硬件控制器模型**
`lcd` 以 SPI/QSPI 时序为设计基准，没有面向 RGB 接口的完整时序参数（前/后廊、同步脉宽、像素时钟、极性等），也没有图层（Layer）、垂直同步（VSync）、缓冲交换（Pan Display）这类显示控制器（LTDC/DSI/LCDC）必需的能力。

**④ 无统一帧缓冲管理**
显存分配、双缓冲、格式、行步长等各自为政，无法向上层（如 AirUI/LVGL）提供统一的显存句柄和直接渲染入口，性能受制于"画到缓冲再整体拷贝"的模式。

**⑤ 平台适配不灵活**
`lcd` 缺乏统一的 BSP 可覆盖机制，移植到新芯片时常常需要改动公共代码。

## 3. Display 库解决了哪些问题

**① Panel / Interface 解耦**
`display` 将屏幕驱动拆分为两层：`panel`（面板 IC 驱动：初始化命令、电源控制）与 `interface`（物理接口：spi/rgb/dsi/lvds/sdl）。同一个面板 IC 可以复用在不同接口上（如 ST7701S 同时支持 RGB 与 DSI），新增屏幕只写 panel、新增接口只写 interface，互不影响。

**② 原生多屏支持**
通过注册表管理最多 5 个显示组件，Lua API 支持可选 `[id]` 参数定位指定屏幕，天然支持双屏/拼接屏。

**③ 面向显示控制器的完整模型**
内置 RGB/DSI/LVDS 时序与极性参数、图层（Layer）、垂直同步（VSync）、缓冲交换（Pan Display）等能力，可直接驱动 LTDC 等硬件显示控制器，为高分辨率大屏提供基础。

**④ 统一帧缓冲管理 + 直接渲染**
统一管理 `fb_start`（LCDC 显存）、`draw_buf`（绘制区）、多缓冲 `fb_count`、格式与步长，并提供 `getFbInfo()` 将显存地址直接交给上层，支撑 AirUI/LVGL 的 DIRECT 渲染模式，减少中间拷贝、降低带宽开销。

**⑤ 平台适配更灵活**
核心流程采用 `LUAT_WEAK` + `_default` 双函数模式，BSP 可强覆盖默认实现；接口驱动可由各平台提供真机实现替换 stub，迁移成本低。

**⑥ 生命周期与资源管理标准化**
统一了"引脚 → 面板初始化 → 帧缓冲探测 → 接口初始化 → 图层配置 → 上电"的标准流程，并提供完整的资源释放路径，避免泄漏。

## 4. 现状与规划

`display` 定位为显示"底层抽象"，当前已提供 `init/on/off/sleep/wakeup/flush/fill/setRotation/getSize/getFbInfo` 等核心接口；基础几何绘图（点/线/矩形/圆）正在补齐，复杂绘图与字体渲染仍由 AirUI/LVGL 或 `lcd` 库承担。两者目前是互补关系，`display` 逐步承担显示链路的主干，`lcd` 保留在纯绘图与兼容场景使用。

## 相关文档

- `AGENTS.md` — Display 组件开发约定与构建说明
- `src/interface/README.md` — 物理接口驱动说明
- `src/panel/README.md` — 面板 IC 驱动说明



列一下当前LCD库有哪些功能？
19:50

当前 LCD 库位于 luat_lib_lcd.c，功能按类别整理如下（以 reg_lcd 注册表为准）：

1. 初始化 / 控制
API	说明
init	初始化屏幕（支持 SPI/QSPI/RGB 等接口）
close	关闭/反初始化
on / off	开/关显示
sleep / wakeup	休眠 / 唤醒
invon / invoff	反色显示 开/关
cmd / data	写命令 / 写数据（寄存器操作）
setColor	设置前景/背景色
flush	刷新显示（把缓冲区推到屏幕）
setupBuff	设置显存缓冲区
autoFlush	自动刷新开关
setDefault / getDefault	设置/获取默认 LCD 实例
getSize	获取屏幕分辨率
qspi	QSPI 接口配置
user_done	用户自定义驱动初始化完成标记
setAcchw	设置硬件加速
2. 图形绘制
API	说明
clear	清屏
fill	填充矩形
drawPoint	画点
drawLine	画线
drawRectangle	画矩形
drawCircle	画圆
drawQrcode	绘制二维码
drawStr	绘制字符串
drawXbm	绘制 XBM 位图
draw	绘制 RGB565 数据（如从 zbuff）
rgb565	RGB888 ↔ RGB565 转换
image2raw / showImage	图片解码后显示（需 JPG/WebP 支持，宏开关）
3. 字体相关
API	说明
setFont	设置字体
setFontFile	设置字体文件（TTF 等）
getStrWidth	获取字符串像素宽度
drawGtfontGb2312/Gbk（+Gray）	国泰字体 GBK 渲染（需 LUAT_USE_GTFONT）
drawGtfontUtf8（+Gray）	国泰字体 UTF8 渲染（需 LUAT_USE_GTFONT_UTF8）
drawHzfontUtf8 / getHzFontStrWidth	汉仪字体渲染/测宽（需 LUAT_USE_HZFONT）
内置字体常量：font_opposansm12~32、font_opposansm*_chinese（12~32 号中文）、font_sarasa_* 等，按宏开关编译。

4. 支持的屏幕驱动型号（lcd_regs）
通用：custom（自定）、user（用户控制）
ST 系：st7735/v/s、st7789、st7796、st7701s/sn
格科微：gc9a01、gc9106l、gc9306x、gc9306（别名）
ILI 系：ili9341、ili9486
其他：nv3037、nv3041a、nv3052c、hx8282、h050iwv、jd9261t_inited、sh8601z
补充说明：这是传统 lcd 模块（components/lcd）。另外仓库里还有一套较新的 components/display 显示框架（按 interface 区分 SPI/RGB/DSI/LVDS/SDL，按 panel 区分具体屏幕），两者是并存的两套体系。需要我详细列一下 display 那套框架的能力吗？

新的Display库 比LCD库有哪些优点？
20:00

新 Display 库（components/display）与旧 LCD 库（components/lcd）相比，核心优势是架构从"驱动集合"升级为"显示抽象层"，具体如下：

1. Panel / Interface 分离（最大优点）
旧 LCD：每个屏幕型号一个 luat_lcd_opts_t，面板驱动和物理接口耦合，SPI 细节硬编码在驱动里。
新 Display：luat_display.c 中 panel（面板 IC 驱动）与 interface（spi/rgb/dsi/lvds/sdl）完全解耦。同一个面板 IC 可配不同接口（如 st7701s 同时注册在 rgb 和 dsi），新增屏幕只写 panel、新增接口只写 interface，互不影响。
2. 多屏支持（最多 5 个显示组件）
旧 LCD 基本是单屏全局配置。
新库有注册表管理多个显示组件（LUAT_DISPLAY_COMPONENT_COUNT=5），API 支持可选 [id] 参数定位指定屏幕（luat_lib_display.c），适合双屏/拼接屏。
3. 统一 FrameBuffer 管理 + 双缓冲
luat_display_fb_info 统一管理 fb_start（LCDC 显存）、draw_buf（绘制区）、fb_count（多缓冲）、stride、format。
getFbInfo() 直接把显存地址交给上层，为 AirUI/LVGL DIRECT 渲染提供底层支撑，避免中间拷贝。
pan_display 缓冲交换 + wait_vsync，可避免画面撕裂。
4. 面向硬件控制器设计（Layer/Timing/VSync）
显式提供 set_layer（图层）、wait_vsync（垂直同步）、pan_display（交换）回调——这是 LTDC/DSI/RGB 控制器需要而旧 LCD 没有的机制。
完整的 RGB timing 模型（hbp/hfp/hspw/vbp/vfp/vspw/pclk_hz + HSYNC/VSYNC/DE/PCLK 极性），可直驱 RGB 大屏；旧 LCD 主要面向 SPI 小屏。
5. 接口类型覆盖广
RGB / MIPI-DSI / LVDS / SPI(DBI) / SDL，旧 LCD 以 SPI/QSPI 为主。

6. BSP 可覆盖机制
核心流程用 LUAT_WEAK + _default 双函数模式，BSP 可强覆盖；接口驱动可替换 stub 真机实现，适配不同芯片更灵活。

7. 生命周期与资源管理标准化
标准流程 pin → panel_init → fb_probe → inf_init → set_layer → on；luat_display_destroy 完整释放 deinit/fb_info/pin，避免资源泄漏。

注意权衡：新库定位是"显示底层抽象"，目前 Lua 层绘制 API 只有 fill，没有旧 LCD 的 drawPoint/drawLine/drawCircle/二维码/字体渲染/图片解码等（这些现在交给 AirUI/LVGL 或上层做）。所以新库的"优点"主要体现在架构和硬件适配能力上，纯绘图功能反而不如旧库丰富——两者是互补关系，不是简单替代。
