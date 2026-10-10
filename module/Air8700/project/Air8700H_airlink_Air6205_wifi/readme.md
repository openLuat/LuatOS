# Air8700H + Air6205 WiFi热点配置Demo

## 1. 功能简介

本demo演示Air8700H通过SPI接口使用Airlink协议连接Air6205 WiFi模块，实现：
- 创建WiFi热点，默认名称 `luatos_ + IMEI后4位`，无密码
- 手机连接热点后访问Web页面配置WiFi名称/密码和串口波特率
- 配置参数持久化保存到flash，重启后自动加载

## 2. 硬件准备

| 硬件 | 数量 | 备注 |
|------|------|------|
| Air8700H开发板 | 1 | 主控，烧录本demo固件 |
| Air6205核心板 | 1 | WiFi模块，烧录airlink SPI从机固件 |
| 杜邦线 | 若干 | 连接SPI和控制引脚 |

## 3. 接线说明

| Air8700H引脚 | Air6205引脚 | 功能 |
|-------------|------------|------|
| SPI0_CLK | SPI_CLK | SPI时钟 |
| SPI0_MOSI | SPI_MOSI | SPI主出从入 |
| SPI0_MISO | SPI_MISO | SPI主入从出 |
| GPIO8 | CS | SPI片选 |
| GPIO33 | RDY | 就绪信号 |
| GPIO24 | IRQ | 中断信号 |
| GPIO32 | RST | WiFi模块复位 |
| GND | GND | 共地 |

> 引脚定义可在 `main.lua` 的 `airlink_wifi_ap.open()` 调用中修改。

## 4. 运行步骤

1. 为Air6205烧录airlink SPI从机固件
2. 为Air8700H烧录本demo固件（使用Luatools工具）
3. 将 `config_page.html` 烧录到设备的 `/luadb/` 目录
4. 按接线说明连接两块开发板
5. 上电启动，Air6205自动创建WiFi热点
6. 手机连接热点（名称格式 `luatos_XXXX`，无密码）
7. 浏览器访问 `http://192.168.4.1/config`
8. 在Web页面修改WiFi名称、密码、串口波特率，点击保存

## 5. 预期效果

- 上电后Air6205创建WiFi热点，手机可搜索到
- 连接热点后访问配置页面，显示当前配置信息
- 修改配置后提示"配置成功，重启后生效"
- 串口波特率修改后立即生效
- 设备重启后自动加载上次保存的配置

## 6. 文件说明

| 文件 | 功能 |
|------|------|
| main.lua | 入口文件，仅加载模块和启动任务，不含业务逻辑 |
| app_main.lua | 应用主任务，初始化流程和模块调度 |
| airlink_wifi_ap.lua | Airlink初始化和WiFi AP创建（支持SPI/UART） |
| http_config.lua | Web配置服务器，HTTP请求处理和页面渲染 |
| config.lua | 配置管理，参数读写和flash持久化 |
| config_page.html | Web配置页面模板（需烧录到/luadb/目录） |

## 7. 注意事项

- Air6205需要烧录支持airlink SPI从机模式的固件
- SPI引脚定义根据实际硬件修改，不同开发板引脚可能不同
- 首次使用自动创建默认热点（luatos_ + IMEI后4位）
- WiFi密码留空表示开放热点（无密码）
- 配置文件存储在设备根目录 `/airlink_cfg.json`

## 8. 支持模组

| 模组型号 | 角色 | 是否支持 |
|---------|------|---------|
| Air8700H | 主控端（SPI主机） | ✅ |
| Air6205 | 从机端（WiFi模块） | ✅ |
| Air8101 | 主控端（SPI主机） | ✅ |
| Air780EHM | 主控端（UART模式） | ✅ |
