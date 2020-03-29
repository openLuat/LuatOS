# Luat核心

## 基本信息

* 起草日期: 2019-11-25
* 设计人员: [wendal](https://github.com/wendal)

## Luat核心是怎么个存在

总得来说, Luat核心就是运行luat脚本的最基本设施及核心流程

### 最基本的设施包含

* Lua虚拟机 -- 负责解析和执行脚本
* 消息总线  -- 与宿主rtos系统进行单向信息传递
* 文件系统  -- 读写文件,对核心来说,是读取lua脚本
* 定时器    -- 脚本内的延时机制

### 核心流程(Lua表达)

基于消息总线的响应式处理

```lua
while 1 do
    local msgtype, msgdata = rtos.receive(0)
    if msgtype and handlers[msgtype] then
        handlers[msgtype](msgtype, msgdata)
    end
end
```

逐行描述
```lua
-- 最外层,是一个无穷循环, 除非出错,否则永不退出
while 1 do
    -- 从消息队列接收信息, 无限等待
    -- msgtype是消息的类型,总是一个数值
    -- msgdata是消息的内容,不一定存在
    local msgtype, msgdata = rtos.recv(0)
    -- handlers是消息处理器的table
    if msgtype and handlers[msgtype] then
        -- 如果存在对应msgtype的处理器,则执行之
        handlers[msgtype](msgtype, msgdata)
    end
end
```

## 核心流程(C层面)

```c
void l_rtos_recv(luaState* L) {
    rtos_msg msg;
    uint32_t re;
    re = luat_msgbus_get(&msg, lua_checkint(L, 1));
    if (re) {
        // TODO喂狗
    }
    else {
        msg.handler(L);
    }
}
```

### 关于msg.handler

为了隔离具体处理逻辑, msg包含msg.ptr和msg.handler两部分
1. 注意, 没有msg.id, 这部分数据由msg.handler回调函数自行设置到lua栈
2. msg.ptr是msg.handler所需要的数据,通过luat_msgbus_data隐式传递.

## 相关知识点

* [定时器](/markdown/core/luat_timer)
* [消息总线](/markdown/core/luat_msgbus)
* [文件系统](/markdown/core/luat_fs)
