# REPL for LuatOS

设计一个REPL(Read–eval–print loop), 即"读取-求值-输出" 循环

直接兼容lua.exe的REPL比较麻烦, 而且lua自带的REPL也没有真正的多行支持

所以, 当前设计两种模式

1. 简单单行, 以`\r`/`\n`为结束符
2. 有头有尾的多行, 以 `<<EOF`开始, 以 `EOF` 结束

