# UART

## 基本信息

* 起草日期: 2020-01-14
* 设计人员: [chenxuuu](https://github.com/chenxuuu)

## 为什么需要Uart

* 与外部设备收发数据进行通信

## 设计思路和边界

* 管理并抽象Uart的C API, 提供一套Lua API供用户代码调用

## C API(平台层)

```c
//初始化配置串口各项参数，并打开串口
//成功返回串口id，失败返回负数的原因代码
int8_t luat_uart_setup(luat_uart_t* uart);
//关闭串口
uint8_t luat_uart_close(uint8_t uartid);
//获取未读取串口数据的长度
uint32_t luat_uart_bytes_to_read(uint8_t uartid);
//手动读取缓存中的串口数据
luat_uart_data_t luat_uart_read(uint8_t uartid, uint32_t length);
//发送串口数据
uint32_t luat_uart_write(uint8_t uartid, luat_uart_data_t* data);
```

## Lua API

### 常量

```lua
--校验位
uart.Odd
uart.Even
uart.None
--高低位顺序
uart.LSB
uart.MSB
```

### 用例

```lua
local uartName = "uart1"

local uartid = uart.setup(
    uartName,--设备名
    115200,--波特率
    8,--数据位
    1,--停止位
    uart.None,--校验位
    uart.LSB,--高低位顺序
    4*100--缓冲区大小
)

--发数据
uart.write(uartid,"test")

--方式1:轮询
while true do
    if uart.toRead(uartid) > 0 then
        local len = uart.unread(uartid)
        print(uart.read(uartid,len))
    end
    sys.wait(100)--不阻塞的延时函数
end

--方式2:收数据回调
sys.subscribe("IRQ_"..uartName, function(uartid)
    local len = uart.toRead(uartid)
    print(uart.read(uartid,len))
end)

```
