---
name: luatos-update-project-skill
description: "修改LuatOS项目代码：在已有项目基础上进行修改和扩展。触发条件：用户需要在已有LuatOS项目中添加功能、修改逻辑、修复bug等。先分析现有代码，再进行修改。"
---

# 修改LuatOS项目技能

## 概述

本技能用于在已有LuatOS项目基础上进行修改、扩展或修复，生成符合LuatOS规范的更新代码。

## 触发条件

**必须调用本技能的场景：**
- 用户需要在已有项目中添加新功能
- 用户需要修改现有功能逻辑
- 用户需要修复代码bug
- 用户需要扩展项目能力

## 执行流程（强制）

### 步骤1：MCP服务器检查

引用 [luatos-project-common-skill](#luatos-project-common-skill) 的 `公共流程1：MCP服务器状态检查`

```
IF MCP服务器检查失败 THEN
    输出错误信息，终止执行
END
```

### 步骤2：确定项目目录

```
IF 用户指定了项目目录 THEN
    使用用户指定的已有项目目录
ELSE
    自动查找或创建合适的目录
END
```

### 步骤3：分析修改需求

```
1. 理解用户需要在现有项目中修改什么
2. 识别需要修改的现有模块
3. 识别需要新增的功能模块
4. 确定修改范围和影响
```

### 步骤4：参考Demo分析

引用 [luatos-project-common-skill](#luatos-project-common-skill) 的 `公共流程2：确定参考Demo范围` 和 `公共流程3：分析相关Demo`

### 步骤5：解耦化设计

引用 [luatos-project-common-skill](#luatos-project-common-skill) 的 `公共流程4：解耦化设计规范`

**修改项目时的特殊考虑：**
- 尽量复用现有模块结构
- 新增功能独立成模块
- 保持与现有代码风格一致

### 步骤6：更新main.lua（如需要）

引用 [luatos-project-common-skill](#luatos-project-common-skill) 的 `公共流程7：main.lua模板选择`

**更新main.lua的情况：**
- 新增功能模块需要require
- 需要更新PROJECT/VERSION
- 需要添加新的配置选项

### 步骤7：修改/生成功能模块代码

| 操作 | 说明 |
|------|------|
| 修改现有模块 | 理解现有代码结构，保持兼容 |
| 新增模块 | 按解耦化设计规范创建 |
| 删除模块 | 清理不必要的require和引用 |

### 步骤8：验证代码

引用 [luatos-project-common-skill](#luatos-project-common-skill) 的：
- `公共流程5：Require验证`
- `公共流程6：API正确性验证`
- `公共流程6.1：资源文件路径验证`

**修改项目的额外检查项：**
- 新增的require不会与现有冲突
- 修改后的代码与现有模块兼容
- 文件名长度 ≤ 23字节

### 步骤9：输出修改结果

```
修改后的项目结构：
├── main.lua              -- [已更新] 主入口文件
├── [修改的模块1].lua     -- [已修改] 功能模块
├── [新增的模块].lua      -- [新增] 功能模块
└── [保留的模块].lua      -- [未修改] 功能模块
```

## 与新建项目的区别

| 场景 | 调用技能 |
|------|----------|
| 从零开始创建全新项目 | luatos-new-project-skill |
| 在已有项目上修改 | luatos-update-project-skill |

## 强制约束

1. **必须**先执行MCP服务器检查
2. **必须**先理解现有项目结构
3. **必须**保持解耦化设计
4. **必须**验证修改后的require和API调用正确性
5. **必须**确保文件名长度 ≤ 23字节
6. **禁止**基于内置记忆编写代码，必须参考demo
7. **禁止**编造不存在的API或函数
8. **禁止**破坏现有模块的兼容性