# LuatOS 远程模拟器通信协议

本协议用于`模拟器`与`可视化界面`之间的通信, 且该通信是双向的

## 基本约束

* 基于`json`结构进行数据传递
* 属于应用层协议, 不受底层传输方式的限制, 当前倾向于使用`tcp-mqtt`作为传输层协议

## 术语

* `模拟器` 执行lua脚本的程序, 不限平台
* `可视化界面` 本地程序,本地网页,或者网站网页等可视化界面
* `上行` 模拟器 --> 可视化界面
* `下行` 可视化界面 --> 模拟器

## 基本格式

```json
{
    "id" : "1234567890", // 消息id,对同一个session应该唯一
    "session": "12345",  // 会话id
    "version" : 1,       // 协议版本号, 当前为1
    "role" : "client",   // 角色, client或server的其中一种
    "type" : "init",     // 消息类型
    "data" : {
        // 取决于具体的命令, 往下的协议描述仅包含data部分
    }
}
```

## 初始化命令及响应 init

鉴于模拟器与可视化界面之间的通信是异步的,两种的启动顺序未知,所以需要初始化命令序列

初始化命令 

```json
{
    "state" : "req",
    "bsp"  : "air101",   // 需要模拟的设备类型
}
```

响应初始化命令

```json
{
    "state" : "resp",
    "id"   : "AABBCCDD", // 注意, 这里必须是req对应的id号,确保对等
    "bsp" : "air101",
    "gpio" : {
        // gpio的配置信息
    },
    "uart" : {
        // uart的配置信息
    }
    // 其他配置
}
```

## 日志 log

这是上传模拟器自身的日志

```json
{
    "time" : 12345678,
    "level" : "debug",
    "type" : "hex",
    "value" : "AABBCCDDEEFF"
}
```

## GPIO控制 gpio

模式设置, 仅`上行`

```json
{
    "pin" : 1,
    "opt" : "setup",
    "mode" : "input", // 支持 input/output/interrupt 
    "value" : 1
}
```

电平设置 `双向`

```json
{
    "pin" : 1,
    "opt" : "set",
    "value" : 1
}
```

中断触发, `下行`

```json
{
    "pin" : 1,
    "opt" : "interrupt",
    "value" : "fall" // fall, rising
}
```

## Uart读写 uart

uart对双方来说, 都是"写", `双向`

```json
{
    "id" : 1,
    "opt" : "write",
    "type" : "hex",
    "value" : "AABBCC"
}
```

## 显示 display

显示初始化

```json
{
    "opt" : "init",
    "w" : 800,
    "h" : 640,
    "colorspace" : "rgb565",
    "colorswap" : true
}
```

更新显示内容

```json
{
    "opt" : "zone_update",
    "area" : {
        "x1" : 123,
        "y1" : 123,
        "x2" : 456,
        "y2" : 456,
    },
    "rbuff" : {
        "type" : "hex",
        "value" : "AABBCCDDEEFF"
    }
}
```

## 输入设备 indev

当前仅支持位置输入, 对应单点触摸屏, 鼠标

```json
{
    "opt" : "pointer",
    "pointer" : {
        "x" : 123,
        "y" : 456,
        "state" : 1 // 0 抬起, 1 按下
    }
}
```

