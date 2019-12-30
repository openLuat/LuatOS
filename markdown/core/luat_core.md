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
    local msgtype, msgdata = rtos.receive(0)
    -- handlers是消息处理器的table
    if msgtype and handlers[msgtype] then
        -- 如果存在对应msgtype的处理器,则执行之
        handlers[msgtype](msgtype, msgdata)
    end
end
```

## 核心流程(C层面)

```c
void luat_main(luaState* L) {
    rtos_msg msg;
    uint32_t re;
    size_t timeout = 1000; // 每1000个tick喂一次狗
    while (1) {
        // 执行pub/sub队列

        re = luat_msgbus_get(&msg, timeout);
        if (re) {
            // TODO喂狗
        }
        else {
            switch(msg.msgtype) {
            case MSG_TIMER:
                // 清理堆栈,执行回调
                luaL_pushfunction(L, msg.data);
                luaL_pcall(...);
                break;
            case MSG_GPIO:
                // 根据gpio的id, 执行回调
                break;
            case ...
            }
        }
        // 检查堆栈, 继续下一轮
    }
}
```

## 相关知识点

* [定时器](luat_timer.md)
* [消息总线](luat_msgbus.md)
* [文件系统](luat_fs.md)
