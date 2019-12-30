# LuatOS 基于Luat的嵌入式实时系统平台



## 项目管理文档

* [平台架构图](markdown/proj/system_struct.md) 项目的总体架构
* [项目管理](markdown/proj/project_manager.md) 描述项目角色及分工
* [环境搭建](markdown/proj/build_sdk.md) 描述从0搭建整个编译过程
* [编码规范](markdown/proj/code_style.md) 主要是规范代码风格

## 核心层文档

* [平台层](markdown/core/luat_platform.md) 平台层设计
* [flash存储规划](markdown/core/flash_zone.md) flash空间分配
* [内存管理](markdown/core/luat_memory.md) 内存分配与管理
* [定时器](markdown/core/luat_timer.md) 定时器(单次/循环)API
* [消息总线](markdown/core/luat_msgbus.md) 消息总线机制
* [底层核心](markdown/core/luat_core.md) Luat核心层
* [低功耗API](markdown/core/luat_pm.md) 低功耗管理
* [FOTA](markdown/core/fota.md) 在线升级
* [文件系统](markdown/core/luat_fs.md) 文件系统操作
* [API列表](markdown/core/luat_api.md) API列表

## 外设API设计

* [io操作](markdown/device/luat_io.md)
* [GPIO外设](markdown/device/luat_gpio.md)
* [UART外设](markdown/device/luat_usart.md)
* [ADC外设](markdown/device/luat_adc.md)
* [I2C外设](markdown/device/luat_i2c.md)
* [SPI外设](markdown/device/luat_spi.md)

## 网络通信层

* [lwip](markdown/network/luat_lwip.md)
* [aliyun-iot](markdown/network/luat_aliyun.md)
* [onenet](markdown/network/luat_onenet.md)
* [coap](markdown/network/luat_coap.md)
* [mqtt](markdown/network/luat_mqtt.md)
* [ping](markdown/network/luat_ping.md)
* [sntp](markdown/network/luat_sntp.md)
* [http](markdown/network/luat_http.md)

## 应用层

* [cjson](markdown/LuaTask/luat_cjson.md) 提供cjson的Lua绑定
* [protobuf](markdown/LuaTask/luat_protobuf.md) 提供protobuf的Lua绑定

## 工具支持

* [Luatools]() 日志读取/脚本下载/底层刷机/合并刷机包
* [批量刷机]()

## 技术讨论

* [Lua版本对比]()

## 相关平台及链接

* [持续构建]() 对每一个提交进行编译检查
* [API文档]() 对代码API进行展示

