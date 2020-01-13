# 消息总线

## 基本信息

* 起草日期: 2019-11-25
* 设计人员: [wendal](https://github.com/wendal)

## 为什么需要消息总线

1. 底层是rtos, lua虚拟机运行在一个thread中
2. rtos要求一个线程必须在空闲时让出cpu资源,不能以死循环方式实现`延时`
3. lua以单线程执行,对`中断`运行并不友好
4. 定时器/GPIO中断/UART数据进入/网络数据进入,都属于`中断`
5. 通过消息总线的方式,让`中断`信息以生产者的方式存在, 由`rtos.receive`作为消费者

## 设计思路和边界

1. 只涉及消息的收取和支出
2. 使用固定大小的消息体,节省内存资源

## 数据结构

消息体以4字节对齐的方式存在

```c
struct rtos_msg {
    luat_msg_hanlder handler;
    void* ptr;
} rtos_msg;

#define LUAT_MSGBUS_ITEMCOUNT ((size_t)0xFF)
```

其中

* handler 消息回调函数
* ptr     消息负载,有具体消息类型决定

## C API

```C
void luat_msgbus_init(void);
void* luat_msgbus_data();
uint32_t luat_msgbus_put(struct rtos_msg* msg, size_t timeout);
uint32_t luat_msgbus_get(struct rtos_msg* msg, size_t timeout);
uint32_t luat_msgbus_freesize(void);
```

### 发送消息

```c
uint32_t luat_msgbus_put(rtos_msg* msg, size_t timeout);
uint32_t luat_msgbus_get(rtos_msg* msg, size_t timeout);
uint32_t luat_msgbus_freesize(void);
```

### Luat 调试 API

下列API用于debug, 不一定实现, 本模块暂不提供用户Lua API

```lua
--  获取剩余当前队列的长度
rtos.msgbus_current_size() -- 返回数值
-- 获取队列里面的全部消息,有可能为空队列
rtos.msgbus_list() -- 返回 [[msgtype, msgdata], ...]
-- 清空队列
rtos.msgbus_clear() -- 无返回
-- 放入一个消息
rtos.msgbuf_send(msgtype, msgdata) -- 无返回
```

## 可用消息类型

|消息类型|消息数据|备注|
|--------|-------|----|
|MSG_TIMER|FUNC|定时器|
|MSG_UART_RXDATA|UART_ID, LEN|串口接收|
|MSG_UART_TX_DONE|UART_ID|串口发送完成|
|MSG_INT|GPIO_ID,INT|GPIO中断|

## 相关知识点

* [Luat核心机制](luat_core.md)
