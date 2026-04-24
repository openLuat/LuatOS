AirLink的nanopb改造需求

现有问题:
1. 每个指令,都是按自己的方式编码参数, 然后执行者按相反规则解码参数, 然后执行, 这个过程完全没有标准化
2. 命令结果没有反馈, 调用都是异步的
3. 要兼容老固件要兼容, 所以老指令不能直接删除
4. 当前的rpc指令完全没有地方在用, 可以覆盖

我的想法, 做一个RPC指令, 它实现的功能点有:

1. request/response都使用nanopb进行编解码, 强约束
2. 使用单一rpc指令, 支持 request/resp/notify 多种操作
3. 统一的执行逻辑
4. airlink_flags_t 从保留bit中分配一个bit, 表达是否支持rpc指令
5. drv的实现逻辑, 如果对端支持rpc指令, 那就走rpc指令形式的实现, 否则走老的实现
6. exec也是类似逻辑, 只是rpc是单个指令, 然后rpc内部再分发到新的逻辑里

实现要求:
1. 允许新增airlink的模式(spi master/spi slave/uart是现有的), 以便支持pc模拟器自我测试, 这样测试用例才方便实现
2. 通过宏隔离新的rpc模式, pc模拟器默认开启, 记得改luat_conf_bsp.h
3. 在airlink组件目录下, 整理支持的指令及对应的pb描述文件
4. nanopb的编译器, 在 D:\tools\generator-bin


