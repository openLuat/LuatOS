# 引擎主机出厂工程

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 程序入口，负责平台检测、硬件驱动加载和任务调度
2. **ui_main.lua** - UI 主程序，负责加载所有窗口模块并初始化 LCD/触摸驱动
3. **app_main.lua** - 业务逻辑加载器，依次加载网络、WiFi、NTP、测速、设置等业务模块

### 1.2 硬件驱动模块（根据平台和屏幕型号选择）
- **Air8000/Air8101代码会根据型号自动选择驱动**
1. **lcd_drv_air8000w_4in.lua** - Air8000W LCD 驱动（ST7796，SPI 接口，480×800）
2. **lcd_drv_air8101_5in.lua** - Air8101 LCD 驱动（ST7701S，RGB 接口，480×854）
3. **tp_drv_air8000w.lua** - Air8000W 触摸驱动（GT911，I2C0）
4. **tp_drv_air8101.lua** - Air8101 触摸驱动（GT911，I2C1）

- **Air1601/Air1602有三种屏幕型号，需要手动选择对应的LCD驱动和触摸驱动**

1. **lcd_drv_air1601_5in.lua** - Air1601 5 寸屏 LCD 驱动（NV3052C，RGB 接口，720×1280）
2. **tp_drv_air1601_5in.lua** - Air1601 5 寸屏触摸驱动（GT911，I2C1）

3. **lcd_drv_air1601_7in.lua** - Air1601 7 寸屏 LCD 驱动（RGB 接口，1024×600）
4. **lcd_drv_air1601_10in.lua** - Air1601 10 寸屏 LCD 驱动（RGB 接口，1024×600）

5. **tp_drv_air1601_7or10.lua** - Air1601 7/10 寸屏触摸驱动（GT911，I2C1）

### 1.3 网络驱动模块（根据平台自动选择）

1. **netdrv_4g_air8000w.lua** - Air8000W 4G 网络驱动
2. **netdrv_wifi_air8101.lua** - Air8101 WiFi 网络驱动
3. **netdrv_wifi_air1601.lua** - Air1601/Air1602 WiFi 网络驱动（Airlink SPI 桥接）
4. **netdrv_pc.lua** - PC 模拟器网络驱动

### 1.4 业务逻辑模块

1. **status_provider_app.lua** - 时间/日期/信号强度状态维护，定时发布状态更新事件
2. **wifi_app_air8000w.lua** - Air8000W WiFi 管理（扫描/连接/断开/自动连接，基于 exnetif）
3. **wifi_app_air1601.lua** - Air1601/Air1602 WiFi 管理（扫描/连接/断开，Airlink SPI 驱动）
4. **wifi_app_common.lua** - WiFi 公共逻辑（状态构建、网络刷新、扫描校验、断连原因）
5. **wifi_storage.lua** - WiFi 配置持久化存储（基于 fskv）
6. **ntp_app.lua** - NTP 授时，连网后自动同步系统时间
7. **speedtest_app.lua** - 基于 Cloudflare 的延迟/抖动/下载/上传测速
8. **settings_display_app.lua** - 屏幕亮度管理（PWM 背光）
9. **settings_buzz_app.lua** - 触摸反馈音管理（PWM 蜂鸣器）
10. **settings_storage_app.lua** - 存储空间信息采集
11. **settings_memory_app.lua** - 内存信息采集（系统/Lua VM/PSRAM）
12. **settings_about_app.lua** - 设备信息采集（型号/唯一ID/固件版本/内核版本）
13. **settings_config_app.lua** - 设备名称管理（基于 fskv 持久化）

### 1.5 窗口模块

1. **welcome_win.lua** - 开机动画窗口（鼠标搜索动画）
2. **idle_win.lua** - 桌面启动器窗口（时间/日期/信号/快捷入口/外部应用网格）
3. **settings_win.lua** - 设置主窗口（亮度/WiFi/存储/更新/声音/关于入口）
4. **settings_display_win.lua** - 屏幕亮度设置窗口（滑动条调节）
5. **settings_storage_win.lua** - 存储与内存信息窗口
6. **settings_sound_win.lua** - 触摸反馈音设置窗口（开关/音量/时长/测试）
7. **settings_about_win.lua** - 关于设备窗口（名称/型号/ID/版本）
8. **wifi_list_win.lua** - WiFi 列表窗口（开关/已保存网络/附近网络/扫描）
9. **wifi_detail_win.lua** - WiFi 详情窗口（SSID/IP/密码/信号/断开）
10. **wifi_connect_win.lua** - WiFi 连接窗口（密码输入/高级配置）
11. **app_store_win.lua** - 应用市场窗口（搜索/分类/安装/卸载/更新/分页）
12. **speedtest_win.lua** - 网络测速窗口（延迟/抖动/下载/上传）

## 二、演示效果

本工程为完整的引擎主机出厂固件，包含开机动画、桌面启动器、系统设置、WiFi 管理、应用市场、网络测速等完整功能。

| 首页| 系统设置 | 应用市场 | 网速测速 | 应用列表 | 应用界面 |
|---------|--------|---------|---------|---------|---------|
| <img src="https://docs.openLuat.com/cdn/image/idle_win.png"> | <img src="https://docs.openLuat.com/cdn/image/settings_win.png">| <img src="https://docs.openLuat.com/cdn/image/app_store_win.png">| <img src="https://docs.openLuat.com/cdn/image/speedtest_win.png"> |<img src="https://docs.openLuat.com/cdn/image/app_2.png"> | <img src="https://docs.openLuat.com/cdn/image/app_1.png"> |

## 三、演示硬件环境

- type-c 数据线 x 1
- 合宙引擎主机 x 1，可以通过[合宙引擎主机购买链接](https://luat.taobao.com/category-1841239809.htm?spm=a1z10.1-c-s.w5002-24045920810.3.5e431170zwnEuQ&search=y&catName=%BA%CF%D6%E6%D2%FD%C7%E6%D6%F7%BB%FA) 进行购买


## 四、演示软件环境

### 4.1 开发工具

- [Luatools 下载调试工具](https://docs.openluat.com/air8000/luatos/common/download/) - 固件烧录和代码调试

### 4.2 内核固件

- Air8000W：[点击下载 Air8000W 最新版本内核固件](https://docs.openluat.com/air8000/luatos/firmware/)
- Air8101：[点击下载 Air8101 最新版本内核固件](https://docs.openluat.com/air8101/luatos/firmware/)
- Air1601：[点击下载 Air1601 最新版本内核固件](https://docs.openluat.com/air1601/luatos/firmware/)


## 五、演示核心步骤

### 5.1 硬件准备

- 通过 type-c 数据线对引擎主机供电


### 5.2 软件配置

在 `main.lua` 中根据实际使用的平台和屏幕尺寸选择对应驱动：

```lua
-- 平台检测（hmeta.model 为主，rtos.bsp 为回退）
local ok, _model = pcall(hmeta.model)
if not ok or not _model then _model = rtos.bsp() end
_G.model_str = tostring(_model or "")

-- 加载显示驱动/触摸驱动（根据平台选择对应驱动）
if _G.model_str:find("Air8000") then
    pins.setup(31, "PWM0")
    pins.setup(35, "PWM4")
    lcd_drv = require "lcd_drv_air8000w_4in"
    tp_drv = require "tp_drv_air8000w"
elseif _G.model_str:find("Air8101") then
    pins.setup(11, "I2C1_SDA")
    pins.setup(12, "I2C1_SCL")
    pins.setup(14, "PWM1")
    lcd_drv = require "lcd_drv_air8101_5in"
    tp_drv = require "tp_drv_air8101"
elseif _G.model_str:find("Air1601") or _G.model_str:find("Air1602") then
    -- 根据实际屏幕尺寸选择对应 LCD 驱动（三选一）
    lcd_drv = require "lcd_drv_air1601_5in"
    -- lcd_drv = require "lcd_drv_air1601_7in"
    -- lcd_drv = require "lcd_drv_air1601_10in"

    -- 触摸驱动（5 寸和 7/10 寸二选一）
    -- tp_drv = require "tp_drv_air1601_5in"
    tp_drv = require "tp_drv_air1601_7or10"
else
    -- PC 模拟器复用 Air8101 驱动
    lcd_drv = require "lcd_drv_air8101_5in"
    tp_drv = require "tp_drv_air8101"
end
```

### 5.3 软件烧录

1. 使用 Luatools 烧录对应型号的最新内核固件
2. 下载并烧录本工程所有脚本文件
3. 将 `res/` 目录下的图片资源随脚本一起烧录
4. 设备自动重启后开始运行
5. [点击查看 Luatools 下载和详细使用](https://docs.openluat.com/air8000/common/Luatools/)

### 5.4 功能测试

#### 5.4.1 开机流程

1. 设备上电后自动运行主程序
2. 显示开机动画（鼠标飞向搜索图标的动画效果）
3. 动画结束后自动进入桌面启动器

#### 5.4.2 桌面操作

1. 桌面显示当前时间、日期和星期
2. 状态栏显示 WiFi/4G 信号强度图标和设备名称
3. 点击"设置"进入系统设置
4. 点击"应用市场"进入应用管理
5. 点击"网络测速"进入测速页面
6. 左右滑动切换外部应用页面

#### 5.4.3 设置操作

1. 显示亮度：拖动滑动条或点击 +/- 按钮调节屏幕亮度
2. WiFi 设置：查看/扫描/连接 WiFi 网络
3. 存储空间：查看文件系统使用情况
4. 触摸音效：开启/关闭触摸反馈音，调节音量和时长
5. 关于设备：查看和修改设备名称、型号、固件版本等信息

#### 5.4.4 WiFi 操作

1. 开启 WiFi 开关，自动扫描附近网络
2. 点击已保存网络直接连接
3. 点击附近网络进入连接页面，输入密码
4. 点击已连接网络查看详情（SSID/IP/MAC/信号强度）
5. 支持断开连接和密码显隐切换

#### 5.4.5 应用市场操作

1. 搜索应用：点击搜索框弹出键盘输入
2. 分类筛选：点击侧边栏选择"全部/已安装/通信/工具/游戏/工业/健康"
3. 安装应用：点击"安装"按钮，显示安装进度
4. 卸载应用：已安装的应用显示"卸载"按钮
5. 更新应用：有更新时显示"更新"按钮

#### 5.4.6 网络测速操作

1. 点击"开始测速"启动测试
2. 实时显示延迟/抖动/下载速度/上传速度
3. 测试完成后显示最终结果

### 5.5 预期效果

- **系统启动**：正常初始化，显示开机动画，自动进入桌面
- **NTP 授时**：连网后自动同步系统时间，桌面时钟正常显示
- **WiFi 管理**：正常扫描和连接网络，自动重连
- **应用市场**：外部应用正常安装/卸载/更新
- **触摸操作**：准确的触摸定位和事件响应
- **窗口切换**：流畅的窗口过渡效果
- **设置功能**：亮度/声音/存储/内存/设备信息正常显示和调节

### 5.6 故障排除

1. **显示异常**：检查 LCD 接线，确认对应驱动文件中的硬件参数正确
2. **触摸无响应**：检查 I2C 接线，确认触摸芯片型号配置正确
3. **WiFi 无法扫描**：检查网络驱动是否与平台匹配
4. **图片无法显示**：确认图片资源已正确烧录到脚本分区
5. **字体显示异常**：确认字体文件已正确烧录
6. **设备名称不保存**：确认 fskv 存储空间正常
7. **系统卡顿**：关闭调试日志，检查是否有死循环

