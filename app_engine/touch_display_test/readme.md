# 触摸显示位置偏移测试（touch_display_test）

## 1. 功能简介

用于测试屏幕**显示位置与触摸位置是否存在偏移**的产测工具。

开机自动完成显示（display 底层初始化 + AirUI）、触摸（GT911）初始化后，进入测试界面：

1. **坐标网格**：全屏绘制网格线，并在四边按像素标注坐标刻度，右上角标注屏幕分辨率，边框即屏幕坐标范围 `0 ~ W-1` / `0 ~ H-1` 的边界
2. **触摸标记**：手指按到哪里，就在触摸上报坐标处画一个**红色十字标记**，旁边用黄色文字标注 `序号:(x,y)`，同时通过 log 打印触摸坐标
3. **清屏按钮**：点击屏幕右下角"清屏"按钮，清除所有十字标记（按钮区域内的触摸只打印日志、不画标记，避免遮挡）

本工程只保留显示、触摸、AirUI 初始化功能，**不含**网络、音频、应用工厂、OTA 等任何其他业务；
所有型号的**供电时序（power_on）、引脚配置（pins）和显示初始化方式（display 底层初始化）
与 factory_new 工厂工程完全一致**。

## 2. 如何判断偏移

| 现象 | 结论 |
|------|------|
| 十字交点正好落在手指按压点/网格交点上 | 显示与触摸无偏移 |
| 十字交点相对手指按压点整体偏移固定距离 | 存在**固定偏移**，按十字旁坐标文字与实际按压位置的差值量化 |
| 偏移量随位置线性变化（角落偏得多、中间偏得少） | 存在**缩放误差**，常见于触摸分辨率与显示分辨率配置不一致 |
| 偏移方向与屏幕旋转相关 | 检查 LCD 旋转/方向与触摸坐标映射是否配套 |

推荐测试点：屏幕 4 个角、4 条边的中点、中心点，共 9 个点；与 log 中打印的坐标互相印证。

## 3. 支持型号

与 `C:\gitee\LuatOS\app_engine\factory_new` 中所有已实现型号一致（≥800×480 / 480×854），
修改 `main.lua` 中的 `PROJECT` 字符串即可切换硬件：

| PROJECT | 屏幕 |
|---------|------|
| Engine_Air1602_5inch_720x1280_002_V000 | 5寸 RGB NV3052C 720x1280 |
| Engine_Air1602_5inch_720x1280_003_V000 | 5寸 RGB NV3052C 720x1280 |
| Engine_Air1602_5inch_480x854_005_V000 | 5寸 RGB ST7701S 480x854 |
| Engine_Air1602_7inch_1024x600_000_V000 | 7寸 RGB HX8282 1024x600 |
| Engine_Air1602_7inch_1024x600_004_V000 | 7寸 RGB HX8282 1024x600 |
| Engine_Air1602_10inch1_1024x600_001_V000 | 10寸 RGB HX8282 1024x600 |
| Engine_Air1602_AirLCD_1090_09421_V000 | 9寸 RGB HX8282 1024x600 |
| Engine_Air1602_AirLCD_1100_10421_V000 | 10寸 RGB HX8282 1024x600 |
| Engine_Air8601_7inch_1024x600_010_V000 | 7寸 RGB HX8282 1024x600 |
| Engine_Air8602_9inch_1024x600_010_V000 | 9寸 RGB HX8282 1024x600 |
| EVB_Air8101_AirLCD_1020_000_V020 | 5寸 RGB H050IWV 800x480 |
| EVB_Air8101_AirLCD_1070_000_V020 | 7寸 RGB HX8282 1024x600 |
| EVB_Air8101_AirLCD_1090_000_V020 | 9寸 RGB HX8282 1024x600 |
| EVB_Air8101_AirLCD_1100_000_V020 | 10.1寸 RGB HX8282 1024x600 |
| EVB_Air8101B_5inch_480x854_000_V010 | 5寸 RGB ST7701S 480x854 |
| EVB_Air8101B_5inch_480x854_000_V020 | 5寸 RGB GC9503 480x854 |
| EVB_Air1601_5inch_800x480_000_V011 | 5寸 RGB 800x480 |
| EVB_Air1601_7inch_1024x600_000_V011 | 7寸 RGB HX8282 1024x600 |
| EVB_Air1601_7inch_1024x600_000_V012 | 7寸 RGB HX8282 1024x600 |
| EVB_Air1601_10inch1_1024x600_000_V011 | 10.1寸 RGB HX8282 1024x600 |

未填写 PROJECT 或映射未命中时，回退到 PC 模拟器配置（可直接在 PC 上跑通流程）。

## 4. 使用步骤

1. 打开 `main.lua`，把 `PROJECT` 改成待测型号（见上表），`VERSION` 可保持默认
2. 用 Luatools 按对应芯片平台下载脚本到整机（固件需带 `display` 库，即 LUAT_USE_DISPLAY）
3. 开机后屏幕显示坐标网格，依次触摸屏幕 4 个角、4 边中点、中心点
4. 观察每个十字标记是否落在手指按压点上；同时在 Luatools 日志中查看打印的坐标：
   ```
   I/user.touch_test_win  触摸按下 x=240 y=427 track=0
   I/user.touch_test_win  第1个触摸标记 已画在 x=240 y=427
   ```
5. 点击右下角"清屏"按钮，清除所有标记后继续测试
6. 按第 2 节的对照表给出偏移结论；需要复测换型号时，只改 `PROJECT` 重新下载即可

## 5. 目录结构

```
touch_display_test/
├── main.lua                  入口：PROJECT 选择 + 初始化流程（LCD→TP→测试界面→背光）
├── touch_test_win.lua        测试界面：坐标网格 + 触摸十字标记 + 清屏按钮
├── core/
│   └── platform_loader.lua   平台检测 + 配置加载 + pins/供电时序（精简版）
├── config/                   各型号硬件配置（与 factory_new 一致，含供电/引脚/RGB时序参数）
├── drv/
│   ├── lcd/
│   │   ├── lcd_common.lua    驱动加载 + AirUI 初始化封装 + 背光控制
│   │   ├── lcd_display_rgb   RGB 屏统一驱动（内部走 display.init）
│   │   └── lcd_st7701s_5in   ST7701S IC 初始化序列（ic_init 回调）
│   └── tp/tp_gt911.lua       GT911 触摸驱动（含触摸尺寸继承 LCD 兜底）
└── readme.md                 本说明
```

## 6. 显示初始化方式（factory_new · display 底层初始化）

所有 RGB 屏统一走 `lcd_display_rgb` 驱动，内部调用 `display.init("custom", ...)`
**一次完成**：SPI IC 寄存器序列（custom_cmds）→ RGB 接口时序（hbp/hspw/hfp/vbp/vspw/vfp/pclk）
→ FrameBuffer 分配。需要 SPI 初始化的面板 IC 由配置文件提供 `ic_init` 回调
（如 `ic_init = require("lcd_st7701s_5in").ic_init`），纯 RGB 时序驱动的面板无需 ic_init。

触摸侧 `tp_gt911` 在 tp 未显式配置 w/h 时自动继承 LCD 分辨率——display 库路径不再调
`lcd.init("custom", ...)` 注册内核默认 LCD 配置，缺 w/h 会导致触摸初始化被 input 适配器拒绝。

## 7. 注意事项

1. 本工程的 `config/`、`drv/` 从 factory_new 工厂工程拷贝而来，供电时序、引脚复用、
   RGB 时序与 IC 初始化参数与 factory_new 保持一致；factory_new 升级硬件支持时，同步拷贝对应文件即可
2. 测试界面**不做密度缩放**，网格刻度与触摸坐标一比一对应（物理像素），这是准确判断偏移的前提
3. 网格间距自适应：短边 ≤480 像素的屏按 50 像素画格，其余按 100 像素画格
4. log 中触摸移动（TP_MOVE）事件不打印，只打印按下/抬起，避免刷屏
5. 工程不包含 FOTA、网络等内容，如需完整功能请使用 factory_new 工厂工程
6. factory_new 的 `platform_loader` PROJECT_MAP 遗漏了 `EVB_Air8101B_5inch_480x854_000_V010`
   → `evb_8101b_5i_v1`（配置文件存在但未映射），本工程已补挂，建议 factory_new 同步修复
