# LuatOS 文档生成工具

```js
{
  // 工作目录：即项目目录
  "workdir": "D:/github/LuatOS/",
  // 要生成什么类型的文档
  // 支持: md | json
  "as": ["md"],
  // 搜索文档的入口
  "entries": [{
    // 入口标题
    "title": "LuaAPI模块",
    // 入口路径，相对 workdir
    "path": "luat/modules",
    // 搜索的文件前缀
    // 从 workdir+path 之后的路径开始算，一定不是 "/" 开头
    "prefix": [],
    // 搜索文件后缀
    "suffix": [".c"],
    // 仅输入下面指定的 API
    // 支持, "C" 和 "LUA"
    // !! 注意，需要全部大写
    // 默认的，都会输出（即，只要解析器收集到的函数签名，都会输出为文档）
    "lang" : ["C", "LUA"],
    // 这个开关如果设置为 true，所有空白的函数签名都会被无视
    // 默认 false
    "dropEmptyComment": true,
    // 文档集用那个文件作为模板，默认是入口目录下的 README.md 文件
    // 模板文件的 ${index} 占位符会放置生成的索引列表
    // 占位符 ${index} 则为本配置声明的 title 段
    "readme" : "README.md"
    // 输出路径，相对 output
    // 占位符 ${name} 表示 path 对应目录的名字
    // 本例中，它表示 "modules"
    "out": "${name}",
    // 是否递归深层搜索目录
    "deep": true
  }],
  // 输出文档的目录
  // 占位符 ${workdir} 就是工作目录
  "output": "${workdir}/docs/api/"
}
```