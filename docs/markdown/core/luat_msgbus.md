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

```c
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

## 如何使用msgbus

举个栗子:

```c
// 这个函数位于 luat_gpio_rtt.c , 属于平台特定的实现
// C 层, 被rtt/freertos/厂商rtos所调用的中断函数
// 它的作用, 就是接收中断, 打包为rtos_msg对象,提交到msgbus队列里面
int luat_gpio_callback(void *ptr) {
    rtos_msg msg;
    luat_gpio_t *gpio = (luat_gpio_t *)ptr; // 注册回调函数时,通常能传递一个自定义的参数
    msg.handler = gpio->hanlder; // 这里的handler, 就是下面提到的l_gpio_handler方法
    msg.ptr = ptr; // 把数据也传过去
    luat_msgbus_put(&msg, 0); // msg的数据会被复制到msgbu,所以直接传指针就行
}
// 这个函数位于 luat_lib_gpio.c ,属于通用实现
int l_gpio_handler(LuaState *L, void *ptr){
    luat_gpio_t *gpio = (luat_gpio_t *)ptr;
    lua_pushinteger(L, MSG_GPIO); // 这里才填入msgid, 而不是有rtos.recv里面写逻辑判断
    lua_pushinteger(L, gpio->pin);
    lua_pushinteger(L, gpio->dist);
    return 3;
}
// rtos.recv等待新msg的到来, 然后执行msg.handler(msg.ptr)
// while 1 do
//     local msgid, dataA, dataB = rtos.recv(0)
//     handlers[msgid](dataA, dataB)
// 在 rtos.recv 内部是这样
```
## 相关知识点

* [Luat核心机制](/markdown/core/luat_core)
