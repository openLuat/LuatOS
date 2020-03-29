# 平台架构

## 总体架构

![](EC616_core_struct_v20191125.jpg)

## Luat核心流程

1. 系统启动,创建消息队列
2. 注册周边回调函数
3. 执行lua脚本
4. lua脚本轮训等待消息队列


```lua
while 1 do
    local msg = rtos.receive(0)
    if msg then
        handle(msg)
    end
end
```

![](EC616_core_workflow_v20191125.jpg)

