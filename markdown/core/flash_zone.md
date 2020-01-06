# Flash分区

## 各区域分配


|分区名     |内容           |格式|起始地址|大小|
|----------|---------------|-------|----|---|
|system    | 代码区    |  hex    |   |  |
|lua_vm    | lua虚拟机本身  |  hex     |   |  |
|lua_libs  | lua库          |  hex   |   |  |
|lua_files | 用户脚本        | filesystem |   |  |
