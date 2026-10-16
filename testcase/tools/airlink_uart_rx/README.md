# AirLink UART接收缓存主机回归

本目录是显式运行的独立主机工具，不加入固件、测试自动发现或设备启动流程。

```sh
python3 testcase/tools/airlink_uart_rx/run_tests.py \
  --baseline 35c1af35eac7014f04762ed366cdfdb8fb8694ce \
  --output ../build
```

需要Python 3、Git、Clang、pthread及ASan/UBSan。输出必须是全新目录，拒绝覆盖历史结果。单阶段30秒截止，真实退出和stdout/stderr分别保留，二进制在每组后删除。

驱动测试编译实际完整驱动，平台头文件由主机声明替代，函数体不修改。两个原版追加交错负控制分别使用1040/260字节旧缓存和130字节新数据；修复版由真实pthread mutex替代RTOS mutex，并由另一个线程在追加复制中途读取/peek/clear，检验忙返回与内容完整性。另覆盖两口独立、并发初始化、资源失败、空/短读及溢出策略。日志和msgbus必须在调用线程已释放锁后执行。

Lua绑定测试逐字提取当前`l_uart_rx`函数，仅替代Lua栈、底层read和zbuff依赖。原版短读负控制证明查询5字节、实际只读2字节时把未写入的尾部计入used；修复版覆盖短读、负查询/读、空读、扩容失败、uint32溢出、非法used和正常追加。原版编译保留既有告警，修复版使用`-Werror`，均启用ASan/UBSan。

原版输出`DEFECT_REPRODUCED`且退出0表示成功检出既有缺陷。修复版通过只代表主机C回归；尚未执行目标FreeRTOS、Air8000固件链接、实际UART接线或长稳测试，也未证明历史网络/GPIO异常属于同一根因。实际测试结果以本次新目录RESULT.md及各阶段原始退出为准。
