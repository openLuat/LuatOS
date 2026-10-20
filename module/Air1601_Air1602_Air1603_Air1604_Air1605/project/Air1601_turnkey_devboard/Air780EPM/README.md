# Air780EPM 模块说明

本文件夹包含 Air780EPM 模组的代码，用于与 Air1601 通过 airlink 进行通信。

## 文件说明

- `main.lua` - Air780EPM 主程序入口
- `network_airlink.lua` - airlink 网络模块，用于与 Air1601 通信

## 功能说明

1. 初始化 airlink 网络，使 Air1601 可以通过 Air780EPM 实现 4G 联网
2. 定期发送 mobile 信息（csq、imei、iccid、imsi、ip）给 Air1601
3. 支持网络状态检测和 HTTP 测试

## 使用方法

1. 将本文件夹中的代码烧录到 Air780EPM 模组
2. Air780EPM 会自动初始化 airlink 网络
3. Air780EPM 每秒发送一次 mobile 信息给 Air1601
4. Air1601 通过 `airlink_mobile_info` 模块接收并解析这些信息

## 数据格式

Air780EPM 发送给 Air1601 的 mobile 信息格式：
```
MOBILE_INFO:csq=XX,imei=XXXXXXXXXXXXXXXX,iccid=XXXXXXXXXXXXXXXX,imsi=XXXXXXXXXXXXXXXX,ip=XXX.XXX.XXX.XXX
```

## 注意事项

1. 确保 Air780EPM 与 Air1601 通过 UART 正确连接
2. UART 波特率设置为 6000000
3. Air780EPM 的 UART ID 根据实际设备配置