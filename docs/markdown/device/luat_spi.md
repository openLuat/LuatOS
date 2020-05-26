# SPI

## 基本信息

* 起草日期: 2020-03-27
* 设计人员: [chenxuuu](https://github.com/chenxuuu)

## 为什么需要SPI

* 与外部设备收发数据进行通信

## 设计思路和边界

* 管理并抽象SPI的C API, 提供一套Lua API供用户代码调用

## C API(平台层)

```c
//初始化配置SPI各项参数，并打开SPI
//成功返回0
int8_t luat_spi_setup(luat_spi_t* spi);
//关闭SPI，成功返回0
uint8_t luat_spi_close(uint8_t spi_id);
//收发SPI数据，返回接收字节数
uint32_t luat_spi_transfer(uint8_t spi_id, uint8_t* send_buf, uint8_t* recv_buf, uint32_t length);
//收SPI数据，返回接收字节数
uint32_t luat_spi_recv(uint8_t spi_id, uint8_t* recv_buf, uint32_t length);
//发SPI数据，返回发送字节数
uint32_t luat_spi_send(uint8_t spi_id, uint8_t* send_buf, uint32_t length);
```

## Lua API

### 常量

```lua
--高低位顺序
spi.LSB
spi.MSB--一般用这个
--主从
spi.master
spi.slave
--半双工/全双工
spi.half
spi.full
```

### 用例

```lua
local spiId = 1
local cs = 10

local result = spi.setup(
    spiId,--串口id
    cs,
    0,--CPHA
    0,--CPOL
    8,--数据宽度
    20000000,--最大频率20M
    spi.MSB,--高低位顺序    可选，默认高位在前
    spi.master,--主模式     可选，默认主
    spi.full,--全双工       可选，默认全双工
)

if result ~= 0 then--返回值为0，表示打开成功
    print("spi open error",result)
end

--发数据
spi.write(spiId,"test")

--收数据
print(spi.recv(spiId,10))

--收发数据
print(spi.transfer(spiId,"test"))
```
