# Air780EPM 工厂测试工程

## 项目简介

本项目是基于合宙Air780EPM（Air780EHM）模组的工厂测试工程，用于生产测试和设备监控。

## 功能特性

### 传感器数据采集
- **SHT30温湿度传感器**: I2C接口，地址0x44，测量温度和湿度
- **VOC空气质量传感器(AGS02MA)**: I2C接口，地址0x1A，测量TVOC浓度
- **CPU温度**: 通过ADC读取芯片内部温度
- **LBS基站定位**: 免费单基站定位，获取经纬度

### 数据上报
- **上报频率**: 默认180秒，可通过Web端远程修改（最小5秒）
- **上报协议**: AirCloud excloud TCP协议
- **上报字段**: 温度、湿度、VOC、CPU温度、信号强度、设备ID、时间戳、经纬度

### 设备控制
- **上报频率设置**: Web端可远程修改上报频率，保存到fskv断电不丢失
- **LED控制**:
  - 闪烁5秒（亮1秒灭1秒）
  - 常亮
  - 熄灭
- **TTS语音播报**: 支持文字转语音播报

### 系统监控
- **外部看门狗**: Air153D看门狗芯片，防止系统死机（超时240秒）
- **网络状态**: 自动重连，支持4G/以太网

## 硬件配置

| 组件 | 型号 | 接口 | 引脚 |
|------|------|------|------|
| 主控模组 | Air780EPM (Air780EHM) | - | - |
| 温湿度传感器 | SHT30 | I2C | GPIO1(SCL), GPIO2(SDA) |
| VOC传感器 | AGS02MA | I2C | GPIO1(SCL), GPIO2(SDA) |
| LED指示灯 | - | GPIO | GPIO27（高电平点亮） |
| 看门狗芯片 | Air153D | GPIO | GPIO24 |

## 目录结构

```
Air8780_factory/
├── main.lua                    # 主程序入口
├── app/
│   ├── app_main.lua            # 应用模块加载入口
│   ├── aircloud/
│   │   └── aircloud_app.lua    # AirCloud云平台通信模块
│   ├── sensor/
│   │   ├── sensor_app.lua      # 传感器数据采集模块
│   │   ├── AirSHT30_1000.lua   # SHT30温湿度传感器驱动
│   │   └── AirVOC_1000.lua     # VOC空气质量传感器驱动
│   ├── led/
│   │   └── led_app.lua         # LED灯控制模块
│   └── watchdog/
│       └── watchdog_app.lua    # 外部看门狗模块
├── drv/
│   ├── netdrv_device.lua       # 网络驱动设备选择
│   └── netdrv/
│       ├── netdrv_4g.lua       # 4G网卡驱动
│       └── netdrv_pc.lua       # PC模拟器网卡驱动
└── web/
    ├── index.html              # Web管理界面
    └── login.html              # 登录页面
```

## 云端命令协议

通过AirCloud excloud协议的自定义下行命令（tag 1281）控制设备：

### 设置上报频率
```
命令格式: "cycle:秒数"
示例: "cycle:60"  → 设置上报频率为60秒
最小值: 5秒
```

### LED控制
```
命令格式: "led:操作"
示例:
  "led:blink" → LED闪烁5秒（亮1秒灭1秒）
  "led:on"    → LED常亮
  "led:off"   → LED熄灭
```

## Web管理界面

访问Web管理界面可进行以下操作：

### 设备监控
- 实时显示传感器数据（温度、湿度、VOC）
- 显示CPU温度和4G信号强度
- 显示设备在线状态和最后更新时间

### 设备控制
- 修改上报频率（5-600秒）
- LED控制（闪烁5秒/常亮/熄灭）
- TTS语音播报

### 历史数据
- 查看历史传感器数据
- 数据图表展示
- 轨迹地图显示

## 开发说明

### 添加新传感器
1. 在`app/sensor/`目录下创建传感器驱动文件
2. 在`sensor_app.lua`中加载驱动并实现读取逻辑
3. 在`aircloud_app.lua`中添加数据上报字段

### 修改上报频率
1. 修改`sensor_app.lua`中的`DEFAULT_CYCLE`常量
2. 或通过Web端远程修改（会保存到fskv）

### 修改LED引脚
1. 修改`app/led/led_app.lua`中的`LED_PIN`常量

## 版本历史

- **v1.1.0** (2026-09-10)
  - 新增LED灯控制功能（闪烁/常亮/熄灭）
  - 默认上报频率改为180秒
  - 优化代码注释和文档

- **v1.0.0** (2026-09-09)
  - 初始版本
  - 支持SHT30+VOC传感器数据采集
  - 支持AirCloud数据上报
  - 支持远程修改上报频率
  - 支持外部看门狗
