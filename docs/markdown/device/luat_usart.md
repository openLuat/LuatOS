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
//成功返回0
int8_t luat_uart_setup(luat_uart_t* uart);
//关闭串口，成功返回0
uint8_t luat_uart_close(uint8_t uartid);
//手动读取缓存中的串口数据
uint32_t luat_uart_read(uint8_t uartid, uint8_t* buffer, uint32_t length);
//发送串口数据
uint32_t luat_uart_write(uint8_t uartid, uint8_t* data, uint32_t length);
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
local uartid = 1
local maxBuffer = 4*100

local result = uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1,--停止位
    uart.None,--校验位
    uart.LSB,--高低位顺序
    maxBuffer,--缓冲区大小
    function ()--接收回调
        local str = uart.read(uartid,maxBuffer)
        print("uart","receive:"..str)
    end,
    function ()--发送完成回调
        print("uart","send ok")
    end
)

if result ~= 0 then--返回值为0，表示打开成功
    print("uart open error",result)
end

--发数据
uart.write(uartid,"test")

--轮询方式，和回调方式二选一来用
sys.taskInit(function ()
    while true do
        local data = uart.read(uartid,maxBuffer)
        if data:len() > 0 then
            print(data)
        end
        sys.wait(100)--不阻塞的延时函数
    end
end)

```
