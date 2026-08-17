***
alwaysApply: true
***

# Git 提交规范

## 核心要求

**⚠️ 重要：每次修改文件后，必须先询问用户是否提交，得到确认后再执行 git add + git commit + git push！**

## 提交类型说明

| 类型 | 说明 | 使用示例 |
|------|------|----------|
| `add` | 新增文件、功能、配置 | `add: 新增用户登录功能` |
| `del` | 删除代码、文件、无用逻辑 | `del: 删除废弃的配置文件` |
| `update` | 修改已有代码、优化、重构（非bug） | `update: 优化数据库查询性能` |
| `fix` | 修复bug | `fix: 修复内存泄漏问题` |

## 提交信息格式

`<类型>: <文件名> <简要描述>`

## 提交流程（询问后执行）

```bash
git pull origin master
git add <修改的文件或目录>
git commit -m "<类型>: <文件名> <描述>"
git push origin master
```