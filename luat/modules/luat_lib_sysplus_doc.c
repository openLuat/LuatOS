/*
@module  sysplus
@summary sys库的强力补充
@version 1.0
@date    2022.11.23
@tag LUAT_USE_GPIO
@usage
-- 本库是sys库的补充, 添加了如下内容:
-- 1. cwait机制
-- 2. 任务消息机制, 即sub/pub的增强版本

-- 在socket,libnet,http库等场景需要用到, 所以也需要require
*/

/*
等待接收一个目标消息
@api sysplus.waitMsg(taskName, target, timeout)
@string 任务名称，用于唤醒任务的id
@string 目标消息，如果为nil，则表示接收到任意消息都会退出
@int 超时时间，如果为nil，则表示无超时，永远等待
@return table 成功返回table型的msg，超时返回false
@usage
-- 等待任务
sysplus.waitMsg('a', 'b', 1000)
-- 注意, 本函数会自动注册成全局函数 sys_wait
*/
void doc_sysplus_wait(void){};

/*
向目标任务发送一个消息
@api sysplus.sendMsg(taskName, target, arg2, arg3, arg4)
@string 任务名称，用于唤醒任务的id
@any 消息中的参数1，同时也是waitMsg里的target
@any 消息中的参数2
@any 消息中的参数3
@any 消息中的参数4
@return bool 成功返回true, 否则返回false
@usage
-- 向任务a,目标b发送消息
sysplus.sendMsg('a', 'b')
-- 注意, 本函数会自动注册成全局函数 sys_send
*/
void doc_sysplus_send(void){};

/*
创建一个任务线程,在模块最末行调用该函数并注册模块中的任务函数,main.lua导入该模块即可
@api sysplus.taskInitEx(fun, taskName, cbFun, ...)
@function 任务函数名,用于resume唤醒时调用
@string  任务名称,用于唤醒任务的id
@function 接收到非目标消息时的回调函数
@any ... 任务函数fun的可变参数
@return number 返回该任务的线程号
@usage
sysplus.taskInitEx(task1,'a',callback)
*/
void doc_sysplus_taskInitEx(void){};

/*
删除由taskInitEx创建的任务线程
@api sysplus.taskDel(taskName)
@string  任务名称,用于唤醒任务的id
@usage
sysplus.taskDel('a')
*/
void doc_sysplus_taskDel(void){};

/*
清除指定task的消息队列
@api sysplus.cleanMsg(taskName)
@string  任务名称
@usage
sysplus.cleanMsg('a')
*/
void doc_sysplus_cleanMsg(void){};