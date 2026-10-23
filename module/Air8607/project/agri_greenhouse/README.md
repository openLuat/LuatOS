# 农业大棚智能控制大屏 · Air8607

> Air8607 + 10 寸 RGB 屏（1024x600 免序列）+ GT911 触摸
> 横屏三列布局：环境指标 / 棚区分布 / 设备控制 / 室外气象 / 灌溉水质 / 智能告警，
> 数据来自 `app/mock_data.lua` 模拟数据源，真机联调替换为真实采集结果即可，UI 无需改动。

---

## 目录结构

```
module/Air8607/project/agri_greenhouse/
├── README.md
├── main.lua                    主程序入口（只做加载）
├── app/
│   ├── app_main.lua            应用主入口：硬件初始化 + 业务模块加载 + 启动编排
│   └── mock_data.lua           传感器模拟数据源（真机替换为真实采集回调）
├── ui/
│   ├── ui_main.lua             UI 主入口：界面模块加载与构建/刷新接口
│   └── ui_dashboard.lua        大屏三列布局 UI
└── drv/
    └── lcd/
        └── exd_air8607_rgb.lua 10寸 RGB 屏显示IC初始化扩展库
```

## 启动流程

1. `power_on()` —— 供电 / 背光 PWM3 上电占空比 0 / I2C 引脚配置
2. `exd.setup()` —— 显示初始化（复位 + RGB 时序 + 帧缓冲）
3. `airui` 初始化 —— init + 字体加载 + 旋转
4. `ui_main.build()` —— 进入大屏 UI 界面
5. `touch_init()` —— GT911 触摸初始化 + airui 绑定
6. `backlight_on()` —— 界面就绪后点亮背光，随后时钟每秒刷新、传感器数据每 5 秒刷新

## 硬件引脚

与 `module/Air8607/project/factory/config/eng_8607_10i_v0.lua` 对齐：

| 功能 | 引脚 |
|---|---|
| LCD 复位 | pin_rst = 15 |
| LCD 供电 | pin_pwr = 17（低有效） |
| 背光 | PWM3 (GPIO13) |
| 触摸 I2C1 (400kHz) | pin_rst = 14，pin_int = 51 |
