#!/usr/bin/python
# -*- coding: UTF-8 -*-

import sys
import os
import io
import re
import json
import shutil

source_path = r"../luat"
snippet_path = r"snippet.json"
if len(sys.argv) >= 3:
    source_path = sys.argv[1]
    snippet_path = sys.argv[2]

print("path:")
print(source_path)
print(snippet_path)

file_list = []
for home, dirs, files in os.walk(source_path):
    for filename in files:
        if filename.endswith(".c"):
            file_list.append(os.path.join(home, filename))

for home, dirs, files in os.walk(source_path+"/../lua"):
    for filename in files:
        if filename.endswith(".c"):
            file_list.append(os.path.join(home, filename))

for home, dirs, files in os.walk(source_path+"/../components"):
    for filename in files:
        if filename.endswith(".c"):
            file_list.append(os.path.join(home, filename))

#注释的格式：
# /*
# @module  模块的调用名
# @summary 模块的简短描述信息
# @version 版本号，可选
# @data    日期，可选
# */

# /*
# @api/function module.function(调用时用到的完整函数名)
# @string 第一个参数，@后跟参数类型，空格后跟参数解释
# @number[opt=nil] 第二个参数，默认值为nil
# @table[opt={}] 第三个参数，默认值为{}
# ...根据实际，列出所有参数
# @return 类型 返回的第一个值，这里是解释
# @return string 返回的第二个值，类型为string
# ...根据实际，列处所有返回值
# @usage
# --使用的例子，可多行
# lcoal a,b,c = module.function("test",nil,{1,2,3})
# */
# static int l_module_function(lua_State *L) {
#     //一堆代码
# }
modules = []
#数据结构：
# modules = [
#     {
#         'module': 'adc',
#         'summary': '数模转换',
#         'url': 'https://xxxxxx',
#         'api':[
#             {
#                 'api':'adc.read(id)',
#                 'summary': '读取adc通道',
#                 'args': [
#                     {
#                         'type': 'int',
#                         'summary': '通道id,与具体设备有关,通常从0开始'
#                     }
#                 ],
#                 'return': [
#                     {
#                         'type': 'int',
#                         'summary': '原始值'
#                     },
#                     {
#                         'type': 'int',
#                         'summary': '计算后的值'
#                     }
#                 ],
#                 'usage': '-- 打开adc通道2,并读取\nif adc.open(2) then...'
#             },
#         ]
#     }
# ]

print("found %d files" % len(file_list))

modules = []
for file in file_list:
    text = ""
    try:
        f = io.open(file,"r",encoding="utf-8")
        text = f.read()
        f.close()
    except:
        #print("read fail, maybe not use utf8")
        continue

    module = {}

    file = file.replace("\\","/")
    if file.rfind("luat/") >= 0:
        file = file[file.rfind("luat/"):]
        module["url"] = "https://gitee.com/openLuat/LuatOS/tree/master/"+file
    else:
        module["url"] = ""


    # 注释头
    r = re.search(r"/\* *\n *@module *(\w+)\n *@summary *(.+)\n",text,re.I|re.M)
    if r:
        module["module"] = r.group(1)
        module["summary"] = r.group(2)
        module["api"] = []
    else:
        continue

    for mstep in range(len(modules)-1,-1,-1):
        if modules[mstep]["module"] == module["module"]:
            module["api"] = modules[mstep]["api"]
            del modules[mstep]
            module["url"] = ""

    #后面的数据
    lines = text.splitlines()
    line_now = 0
    while line_now<len(lines)-3:
        #匹配api完整名称行
        name = re.search(r" *@api *(.+) *",lines[line_now+2],re.I)
        if lines[line_now].startswith("/*") and name:
            api = {}
            api["api"] = name.group(1)
            api["summary"] = re.search(r" *(.+) *",lines[line_now+1],re.I).group(1)
            line_now += 3
            api["args"] = []
            api["return"] = []
            api["usage"] = ""
            arg_re = r" *@([^ ]+) +(.+) *"
            return_re = r" *@return *([^ ]+) +(.+) *"
            #匹配输入参数
            while True:
                arg = re.search(arg_re,lines[line_now],re.I)
                arg_return = re.search(return_re,lines[line_now],re.I)
                if arg and not arg_return:
                    api["args"].append({'type':arg.group(1),'summary':arg.group(2)})
                    line_now+=1
                else:
                    break
            #匹配返回值
            while True:
                arg = re.search(return_re,lines[line_now],re.I)
                if arg:
                    api["return"].append({'type':arg.group(1),'summary':arg.group(2)})
                    line_now+=1
                else:
                    break
            #匹配用法例子
            while True:
                arg = re.search(" *@usage *",lines[line_now],re.I)
                if arg:
                    line_now+=1
                    while lines[line_now].find("*/") < 0:
                        api["usage"] += lines[line_now]+"\n"
                        line_now+=1
                else:
                    line_now+=2
                    break
            module["api"].append(api)
        else:
            line_now += 1
    #没有api的包，不导入
    if len(module["api"]) > 0:
        modules.append(module)
        print(module["module"])

#按名字排个序
def sorfFnc(k):
    return k["module"]
modules.sort(key=sorfFnc)

##################  接口数据提取完毕  ##################

#生成自动补全文件
snippet = {'_G': {'body': '_G(${0:...})', 'description': '_G', 'prefix': '_G'}, '_VERSION': {'body': '_VERSION(${0:...})', 'description': '_VERSION', 'prefix': '_VERSION'}, 'assert': {'body': 'assert(${1:v}${2:[, message]})', 'description': 'assert()', 'prefix': 'assert'}, 'collectgarbage': {'body': 'collectgarbage(${1:[opt]}${2:[, arg]})', 'description': 'collectgarbage()', 'prefix': 'collectgarbage'}, 'coroutine.create': {'body': 'coroutine.create( ${1:function} )', 'description': 'coroutine.create', 'prefix': 'coroutine.create'}, 'coroutine.isyieldable': {'body': 'coroutine.isyieldable( )', 'description': 'coroutine.isyieldable', 'prefix': 'coroutine.isyieldable'}, 'coroutine.resume': {'body': 'coroutine.resume( ${1:co}${2:[, val1, ···]} )', 'description': 'coroutine.resume', 'prefix': 'coroutine.resume'}, 'coroutine.running': {'body': 'coroutine.running( )', 'description': 'coroutine.running', 'prefix': 'coroutine.running'}, 'coroutine.status': {'body': 'coroutine.status( ${1:co} )', 'description': 'coroutine.status', 'prefix': 'coroutine.status'}, 'coroutine.wrap': {'body': 'coroutine.wrap( ${1:function} )', 'description': 'coroutine.wrap', 'prefix': 'coroutine.wrap'}, 'coroutine.yield': {'body': 'coroutine.yield( ${1:...} )', 'description': 'coroutine.yield', 'prefix': 'coroutine.yield'}, 'debug.debug': {'body': 'debug.debug()', 'description': 'debug.debug ()', 'prefix': 'debug.debug'}, 'debug.getfenv': {'body': 'debug.getfenv(${0:...})', 'description': 'debug.getfenv (o)', 'prefix': 'debug.getfenv'}, 'debug.gethook': {'body': 'debug.gethook( ${1:[thread]} )', 'description': 'debug.gethook ([thread])', 'prefix': 'debug.gethook'}, 'debug.getinfo': {'body': 'debug.getinfo( ${1:[thread],}${2:f}${3:[, what]} )', 'description': 'debug.getinfo ([thread,] f [, what])', 'prefix': 'debug.getinfo'}, 'debug.getlocal': {'body': 'debug.getlocal( ${1:[thread],}${2:f}${3:[, local]} )', 'description': 'debug.getlocal ([thread,] f, local)', 'prefix': 'debug.getlocal'}, 'debug.getmetatable': {'body': 'debug.getmetatable( ${1:value} )', 'description': 'debug.getmetatable (value)', 'prefix': 'debug.getmetatable'}, 'debug.getregistry': {'body': 'debug.getregistry()', 'description': 'debug.getregistry ()', 'prefix': 'debug.getregistry'}, 'debug.getupvalue': {'body': 'debug.getupvalue( ${1:f}, ${2:up} )', 'description': 'debug.getupvalue (f, up)', 'prefix': 'debug.getupvalue'}, 'debug.getuservalue': {'body': 'debug.getuservalue(${0:...})', 'description': 'debug.getuservalue (u)', 'prefix': 'debug.getuservalue'}, 'debug.getuservalue ': {'body': 'debug.getuservalue ( ${1:u} )', 'description': 'debug.getuservalue (u)', 'prefix': 'debug.getuservalue '}, 'debug.setfenv': {'body': 'debug.setfenv(${0:...})', 'description': 'debug.setfenv (object, table)', 'prefix': 'debug.setfenv'}, 'debug.sethook': {'body': 'debug.sethook( ${1:[thead,]}${2:hook}, ${3:mask}${4:[, count]} )', 'description': 'debug.sethook ([thread,] hook, mask [, count])', 'prefix': 'debug.sethook'}, 'debug.setlocal': {'body': 'debug.setlocal( ${1:[thead,]}${2:level}, ${3:local}, ${4:value} )', 'description': 'debug.setlocal ([thread,] level, local, value)', 'prefix': 'debug.setlocal'}, 'debug.setmetatable': {'body': 'debug.setmetatable( ${1:value}, ${2:table} )', 'description': 'debug.setmetatable (value, table)', 'prefix': 'debug.setmetatable'}, 'debug.setupvalue': {'body': 'debug.setupvalue( ${1:f}, ${2:up}, ${3:value} )', 'description': 'debug.setupvalue (f, up, value)', 'prefix': 'debug.setupvalue'}, 'debug.setuservalue': {'body': 'debug.setuservalue( ${1:udata}, ${2:value} )', 'description': 'debug.setuservalue (udata, value)', 'prefix': 'debug.setuservalue'}, 'debug.traceback': {'body': 'debug.traceback( ${1:[thread,]}${2:[message]}${3:[, level]} )', 'description': 'debug.traceback ([thread,] [message [, level]])', 'prefix': 'debug.traceback'}, 'debug.upvalueid': {'body': 'debug.upvalueid( ${1:f}, ${2:n})', 'description': 'debug.upvalueid (f, n)', 'prefix': 'debug.upvalueid'}, 'debug.upvaluejoin': {'body': 'debug.upvaluejoin( ${1:f1}, ${2:n1}, ${3:f2}, ${4:n2} )', 'description': 'debug.upvaluejoin (f1, n1, f2, n2)', 'prefix': 'debug.upvaluejoin'}, 'dofile': {'body': 'dofile(${1:[filename]})', 'description': 'dofile ([filename])', 'prefix': 'dofile'}, 'elif': {'body': 'else if ${1:condition} then\n\t${0:-- body}\n', 'description': 'elif', 'prefix': 'elif'}, 'error': {'body': 'error(${0:...})', 'description': 'error (message [, level])', 'prefix': 'error'}, 'file:close': {'body': 'file:close(${0:...})', 'description': 'file:close ()', 'prefix': 'file:close'}, 'file:flush': {'body': 'file:flush(${0:...})', 'description': 'file:flush ()', 'prefix': 'file:flush'}, 'file:lines': {'body': 'file:lines(${0:...})', 'description': 'file:lines ()', 'prefix': 'file:lines'}, 'file:read': {'body': 'file:read(${0:...})', 'description': 'file:read (...)', 'prefix': 'file:read'}, 'file:seek': {'body': 'file:seek(${0:...})', 'description': 'file:seek ([whence] [, offset])', 'prefix': 'file:seek'}, 'file:setvbuf': {'body': 'file:setvbuf(${0:...})', 'description': 'file:setvbuf (mode [, size])', 'prefix': 'file:setvbuf'}, 'file:write': {'body': 'file:write(${0:...})', 'description': 'file:write (...)', 'prefix': 'file:write'}, 'for': {'body': 'for ${1:i}=${2:1},${3:10} do\n\t${0:print(i)}\nend', 'description': 'for i=1,10', 'prefix': 'for'}, 'fori': {'body': 'for ${1:i},${2:v} in ipairs(${3:table_name}) do\n\t${0:print(i,v)}\nend', 'description': 'for i,v in ipairs()', 'prefix': 'fori'}, 'forp': {'body': 'for ${1:k},${2:v} in pairs(${3:table_name}) do\n\t${0:print(k,v)}\nend', 'description': 'for k,v in pairs()', 'prefix': 'forp'}, 'fun': {'body': 'function ${1:function_name}( ${2:...} )\n\t${0:-- body}\nend', 'description': 'function', 'prefix': 'fun'}, 'function': {'body': 'function ${1:function_name}( ${2:...} )\n\t${0:-- body}\nend', 'description': 'function', 'prefix': 'function'}, 'getfenv': {'body': 'getfenv(${0:...})', 'description': 'getfenv ([f])', 'prefix': 'getfenv'}, 'getmetatable': {'body': 'getmetatable(${1:object})', 'description': 'getmetatable (object)', 'prefix': 'getmetatable'}, 'if': {'body': 'if ${1:condition} then\n\t${0:-- body}\nend', 'description': 'if', 'prefix': 'if'}, 'ifel': {'body': 'if ${1:condition} then\n\t${2:-- body}\nelse\n\t${0:-- body}\nend', 'description': 'ifel', 'prefix': 'ifel'}, 'io.close': {'body': 'io.close(${0:...})', 'description': 'io.close ([file])', 'prefix': 'io.close'}, 'io.flush': {'body': 'io.flush(${0:...})', 'description': 'io.flush ()', 'prefix': 'io.flush'}, 'io.input': {'body': 'io.input(${0:...})', 'description': 'io.input ([file])', 'prefix': 'io.input'}, 'io.lines': {'body': 'io.lines(${0:...})', 'description': 'io.lines ([filename])', 'prefix': 'io.lines'}, 'io.open': {'body': 'io.open(${0:...})', 'description': 'io.open (filename [, mode])', 'prefix': 'io.open'}, 'io.output': {'body': 'io.output(${0:...})', 'description': 'io.output ([file])', 'prefix': 'io.output'}, 'io.popen': {'body': 'io.popen(${0:...})', 'description': 'io.popen (prog [, mode])', 'prefix': 'io.popen'}, 'io.read': {'body': 'io.read(${0:...})', 'description': 'io.read (...)', 'prefix': 'io.read'}, 'io.tmpfile': {'body': 'io.tmpfile(${0:...})', 'description': 'io.tmpfile ()', 'prefix': 'io.tmpfile'}, 'io.type': {'body': 'io.type(${0:...})', 'description': 'io.type (obj)', 'prefix': 'io.type'}, 'io.write': {'body': 'io.write(${0:...})', 'description': 'io.write (...)', 'prefix': 'io.write'}, 'ipairs': {'body': 'ipairs(${0:...})', 'description': 'ipairs (t)', 'prefix': 'ipairs'}, 'load': {'body': 'load(${0:...})', 'description': 'load (func [, chunkname])', 'prefix': 'load'}, 'loadfile': {'body': 'loadfile(${0:...})', 'description': 'loadfile ([filename])', 'prefix': 'loadfile'}, 'loadstring': {'body': 'loadstring(${0:...})', 'description': 'loadstring (string [, chunkname])', 'prefix': 'loadstring'}, 'local': {'body': 'local ${1:x} = ${0:1}', 'description': 'local x = 1', 'prefix': 'local'}, 'math.abs': {'body': 'math.abs( ${1:x} )', 'description': 'math.abs', 'prefix': 'math.abs'}, 'math.acos': {'body': 'math.acos( ${1:x} )', 'description': 'math.acos', 'prefix': 'math.acos'}, 'math.asin': {'body': 'math.asin( ${1:x} )', 'description': 'math.asin', 'prefix': 'math.asin'}, 'math.atan': {'body': 'math.atan( ${1:y}${2:[, x]} )', 'description': 'math.atan', 'prefix': 'math.atan'}, 'math.atan2': {'body': 'math.atan2(${0:...})', 'description': 'math.atan2 (y, x)', 'prefix': 'math.atan2'}, 'math.ceil': {'body': 'math.ceil( ${1:x} )', 'description': 'math.ceil', 'prefix': 'math.ceil'}, 'math.cos': {'body': 'math.cos( ${1:x} )', 'description': 'math.cos', 'prefix': 'math.cos'}, 'math.cosh': {'body': 'math.cosh(${0:...})', 'description': 'math.cosh (x)', 'prefix': 'math.cosh'}, 'math.deg': {'body': 'math.deg( ${1:x} )', 'description': 'math.deg', 'prefix': 'math.deg'}, 'math.exp': {'body': 'math.exp( ${1:x} )', 'description': 'math.exp', 'prefix': 'math.exp'}, 'math.floor': {'body': 'math.floor( ${1:x} )', 'description': 'math.floor', 'prefix': 'math.floor'}, 'math.fmod': {'body': 'math.fmod( ${1:x},${2:y} )', 'description': 'math.fmod', 'prefix': 'math.fmod'}, 'math.frexp': {'body': 'math.frexp(${0:...})', 'description': 'math.frexp (x)', 'prefix': 'math.frexp'}, 'math.huge': {'body': 'math.huge(${0:...})', 'description': 'math.huge', 'prefix': 'math.huge'}, 'math.ldexp': {'body': 'math.ldexp(${0:...})', 'description': 'math.ldexp (m, e)', 'prefix': 'math.ldexp'}, 'math.log': {'body': 'math.log( ${1:x}${2:[, base]} )', 'description': 'math.log', 'prefix': 'math.log'}, 'math.log10': {'body': 'math.log10(${0:...})', 'description': 'math.log10 (x)', 'prefix': 'math.log10'}, 'math.math.randomseed': {'body': 'math.math.randomseed( ${1:x} )', 'description': 'math.math.randomseed', 'prefix': 'math.math.randomseed'}, 'math.max': {'body': 'math.max( ${1:x},${2:...} )', 'description': 'math.max', 'prefix': 'math.max'}, 'math.maxinteger': {'body': 'math.maxinteger(${0:...})', 'description': 'math.maxinteger', 'prefix': 'math.maxinteger'}, 'math.min': {'body': 'math.min( ${1:x},${2:...} )', 'description': 'math.min', 'prefix': 'math.min'}, 'math.mininteger': {'body': 'math.mininteger(${0:...})', 'description': 'math.mininteger', 'prefix': 'math.mininteger'}, 'math.modf': {'body': 'math.modf( ${1:x} )', 'description': 'math.modf', 'prefix': 'math.modf'}, 'math.pi': {'body': 'math.pi(${0:...})', 'description': 'math.pi', 'prefix': 'math.pi'}, 'math.pow': {'body': 'math.pow(${0:...})', 'description': 'math.pow (x, y)', 'prefix': 'math.pow'}, 'math.rad': {'body': 'math.rad(${0:...})', 'description': 'math.rad (x)', 'prefix': 'math.rad'}, 'math.random': {'body': 'math.random( ${1:[m]}${2:[, n]} )', 'description': 'math.random', 'prefix': 'math.random'}, 'math.randomseed': {'body': 'math.randomseed(${0:...})', 'description': 'math.randomseed (x)', 'prefix': 'math.randomseed'}, 'math.sin': {'body': 'math.sin( ${1:x} )', 'description': 'math.sin', 'prefix': 'math.sin'}, 'math.sinh': {'body': 'math.sinh(${0:...})', 'description': 'math.sinh (x)', 'prefix': 'math.sinh'}, 'math.sqrt': {'body': 'math.sqrt( ${1:x} )', 'description': 'math.sqrt', 'prefix': 'math.sqrt'}, 'math.tan': {'body': 'math.tan( ${1:x} )', 'description': 'math.tan', 'prefix': 'math.tan'}, 'math.tanh': {'body': 'math.tanh(${0:...})', 'description': 'math.tanh (x)', 'prefix': 'math.tanh'}, 'math.tointeger': {'body': 'math.tointeger( ${1:x} )', 'description': 'math.tointeger', 'prefix': 'math.tointeger'}, 'math.type': {'body': 'math.type( ${1:x} )', 'description': 'math.type', 'prefix': 'math.type'}, 'math.ult': {'body': 'math.ult(${0:...})', 'description': 'math.ult (m, n)', 'prefix': 'math.ult'}, 'module': {'body': 'module(${0:...})', 'description': 'module (name [, ...])', 'prefix': 'module'}, 'next': {'body': 'next(${1:table}${2:[, index]})', 'description': 'next (table [, index])', 'prefix': 'next'}, 'os.clock': {'body': 'os.clock(${0:...})', 'description': 'os.clock ()', 'prefix': 'os.clock'}, 'os.date': {'body': 'os.date(${0:...})', 'description': 'os.date ([format [, time]])', 'prefix': 'os.date'}, 'os.difftime': {'body': 'os.difftime(${0:...})', 'description': 'os.difftime (t2, t1)', 'prefix': 'os.difftime'}, 'os.execute': {'body': 'os.execute(${0:...})', 'description': 'os.execute ([command])', 'prefix': 'os.execute'}, 'os.exit': {'body': 'os.exit(${0:...})', 'description': 'os.exit ([code])', 'prefix': 'os.exit'}, 'os.getenv': {'body': 'os.getenv(${0:...})', 'description': 'os.getenv (varname)', 'prefix': 'os.getenv'}, 'os.remove': {'body': 'os.remove(${0:...})', 'description': 'os.remove (filename)', 'prefix': 'os.remove'}, 'os.rename': {'body': 'os.rename(${0:...})', 'description': 'os.rename (oldname, newname)', 'prefix': 'os.rename'}, 'os.setlocale': {'body': 'os.setlocale(${0:...})', 'description': 'os.setlocale (locale [, category])', 'prefix': 'os.setlocale'}, 'os.time': {'body': 'os.time(${0:...})', 'description': 'os.time ([table])', 'prefix': 'os.time'}, 'os.tmpname': {'body': 'os.tmpname(${0:...})', 'description': 'os.tmpname ()', 'prefix': 'os.tmpname'}, 'package.config': {'body': 'package.config(${0:...})', 'description': 'package.config', 'prefix': 'package.config'}, 'package.cpath': {'body': 'package.cpath(${0:...})', 'description': 'package.cpath', 'prefix': 'package.cpath'}, 'package.loaded': {'body': 'package.loaded(${0:...})', 'description': 'package.loaded', 'prefix': 'package.loaded'}, 'package.loaders': {'body': 'package.loaders(${0:...})', 'description': 'package.loaders', 'prefix': 'package.loaders'}, 'package.loadlib': {'body': 'package.loadlib(${0:...})', 'description': 'package.loadlib (libname, funcname)', 'prefix': 'package.loadlib'}, 'package.path': {'body': 'package.path(${0:...})', 'description': 'package.path', 'prefix': 'package.path'}, 'package.preload': {'body': 'package.preload(${0:...})', 'description': 'package.preload', 'prefix': 'package.preload'}, 'package.searchers': {'body': 'package.searchers(${0:...})', 'description': 'package.searchers', 'prefix': 'package.searchers'}, 'package.searchpath': {'body': 'package.searchpath(${0:...})', 'description': 'package.searchpath (name, path [, sep [, rep]])', 'prefix': 'package.searchpath'}, 'package.seeall': {'body': 'package.seeall(${0:...})', 'description': 'package.seeall (module)', 'prefix': 'package.seeall'}, 'pairs': {'body': 'pairs(${0:...})', 'description': 'pairs (t)', 'prefix': 'pairs'}, 'pcall': {'body': 'pcall(${0:...})', 'description': 'pcall (f, arg1, ...)', 'prefix': 'pcall'}, 'print': {'body': 'print(${1:...})', 'description': 'print(...)', 'prefix': 'print'}, 'require': {'body': 'require"${1:module}"', 'description': 'require()', 'prefix': 'require'}, 'ret': {'body': 'return ${1:...}', 'description': 'return ...', 'prefix': 'ret'}, 'select': {'body': 'select(${1:index}, ${2:...})', 'description': 'select (index, ···)', 'prefix': 'select'}, 'setfenv': {'body': 'setfenv(${0:...})', 'description': 'setfenv (f, table)', 'prefix': 'setfenv'}, 'setmetatable': {'body': 'setmetatable(${1:table}, ${2:metatable})', 'description': 'setmetatable (table, metatable)', 'prefix': 'setmetatable'}, 'tonumber': {'body': 'tonumber(${1:e}${2:[, base]})', 'description': 'tonumber (e [, base])', 'prefix': 'tonumber'}, 'tostring': {'body': 'tostring(${1:v})', 'description': 'tostring (v)', 'prefix': 'tostring'}, 'type': {'body': 'type(${1:v})', 'description': 'type (v)', 'prefix': 'type'}, 'unpack': {'body': 'unpack(${0:...})', 'description': 'unpack (list [, i [, j]])', 'prefix': 'unpack'}, 'xpcall': {'body': 'xpcall(${0:...})', 'description': 'xpcall (f, err)', 'prefix': 'xpcall'},"sys.publish(...)": {"body": "sys.publish(${1:...})","description": "发布内部消息，存储在内部消息队列中\r\n返回值：\r\n无\r\n例子：\r\npublish(\"NET_STATUS_IND\")\r\n","prefix": "sys.publish(...)"},"sys.restart(r)": {"body": "sys.restart(${1:r})","description": "软件重启\r\n返回值：\r\n无\r\n例子：\r\nsys.restart('程序超时软件重启')\r\n","prefix": "sys.restart(r)"},"sys.run()": {"body": "sys.run()","description": "run()从底层获取core消息并及时处理相关消息，查询定时器并调度各注册成功的任务线程运行和挂起\r\n返回值：\r\n无\r\n例子：\r\nsys.run()\r\n","prefix": "sys.run()"},"sys.setRollBack(flag, secs)": {"body": "sys.setRollBack(${1:flag},${2: secs})","description": "设置“lua脚本运行出错时，是否回退原始烧写版本”的功能开关。如果没有调用此接口设置，默认回滚\r\n返回值：\r\nnil\r\n例子：\r\nsys.setRollBack(true)\r\nsys.setRollBack(false)\r\n","prefix": "sys.setRollBack(flag, secs)"},"sys.subscribe(id, callback)": {"body": "sys.subscribe(${1:id},${2: callback})","description": "订阅消息\r\n返回值：\r\n无\r\n例子：\r\nsubscribe(\"NET_STATUS_IND\", callback)\r\n","prefix": "sys.subscribe(id, callback)"},"sys.taskInit(fun, ...)": {"body": "sys.taskInit(${1:fun},${2: ...})","description": "创建一个任务线程,在模块最末行调用该函数并注册模块中的任务函数，main.lua导入该模块即可\r\n返回值：\r\nco  返回该任务的线程号\r\n例子：\r\nsys.taskInit(task1,'a','b')\r\n","prefix": "sys.taskInit(fun, ...)"},"sys.timerIsActive(val, ...)": {"body": "sys.timerIsActive(${1:val},${2: ...})","description": "判断某个定时器是否处于开启状态\r\n返回值：\r\nnumber 开启状态返回true，否则nil","prefix": "sys.timerIsActive(val, ...)"},"sys.timerLoopStart(fnc, ms, ...)": {"body": "sys.timerLoopStart(${1:fnc},${2: ms},${3: ...})","description": "开启一个循环定时器\r\n返回值：\r\nnumber 定时器ID，如果失败，返回nil","prefix": "sys.timerLoopStart(fnc, ms, ...)"},"sys.timerStart(fnc, ms, ...)": {"body": "sys.timerStart(${1:fnc},${2: ms},${3: ...})","description": "开启一个定时器\r\n返回值：\r\nnumber 定时器ID，如果失败，返回nil","prefix": "sys.timerStart(fnc, ms, ...)"},"sys.timerStop(val, ...)": {"body": "sys.timerStop(${1:val},${2: ...})","description": "关闭定时器\r\n返回值：\r\n无\r\n例子：\r\ntimerStop(1)\r\n","prefix": "sys.timerStop(val, ...)"},"sys.timerStopAll(fnc)": {"body": "sys.timerStopAll(${1:fnc})","description": "关闭同一回调函数的所有定时器\r\n返回值：\r\n无\r\n例子：\r\ntimerStopAll(cbFnc)\r\n","prefix": "sys.timerStopAll(fnc)"},"sys.unsubscribe(id, callback)": {"body": "sys.unsubscribe(${1:id},${2: callback})","description": "取消订阅消息\r\n返回值：\r\n无\r\n例子：\r\nunsubscribe(\"NET_STATUS_IND\", callback)\r\n","prefix": "sys.unsubscribe(id, callback)"},"sys.wait(ms)": {"body": "sys.wait(${1:ms})","description": "Task任务延时函数，只能用于任务函数中\r\n返回值：\r\n定时结束返回nil,被其他线程唤起返回调用线程传入的参数\r\n例子：\r\nsys.wait(30)\r\n","prefix": "sys.wait(ms)"},"sys.waitUntil(id, ms)": {"body": "sys.waitUntil(${1:id},${2: ms})","description": "Task任务的条件等待函数（包括事件消息和定时器消息等条件），只能用于任务函数中。\r\n返回值：\r\nresult 接收到消息返回true，超时返回false\r\n例子：\r\nresult, data = sys.waitUntil(\"SIM_IND\", 120000)\r\n","prefix": "sys.waitUntil(id, ms)"},"sys.waitUntilExt(id, ms)": {"body": "sys.waitUntilExt(${1:id},${2: ms})","description": "Task任务的条件等待函数扩展（包括事件消息和定时器消息等条件），只能用于任务函数中。\r\n返回值：\r\nmessage 接收到消息返回message，超时返回false\r\n例子：\r\nresult, data = sys.waitUntilExt(\"SIM_IND\", 120000)\r\n","prefix": "sys.waitUntilExt(id, ms)"},"table.concat(t,s)": {"body": "table.concat(${1:t},${2: s})","description": "表连接\r\n返回值：\r\n  字符串\r\n例子：\r\nfruits = {\"banana\",\"orange\",\"apple\"}\r\n-- 返回 table 连接后的字符串\r\nprint(\"连接后的字符串 \",table.concat(fruits))\r\n--连接后的字符串     bananaorangeapple\r\n\r\n-- 指定连接字符\r\nprint(\"连接后的字符串 \",table.concat(fruits,\", \"))\r\n--连接后的字符串     banana, orange, apple\r\n\r\n-- 指定索引来连接 table\r\nprint(\"连接后的字符串 \",table.concat(fruits,\", \", 2,3))\r\n--连接后的字符串     orange, apple\r\n","prefix": "table.concat()"},"table.gsort(t, f)": {"body": "table.gsort(${1:t},${2: f})","description": "返回一个迭代器函数,每次调用函数都会返回hash表的排序后的键值对\r\n返回值：\r\nfunction.\r\n例子：\r\ntest = {a=1,f=9,d=2,c=8,b=5}\r\nfor name,line in pairsByKeys(test) do print(name,line) end\r\n","prefix": "table.gsort(t, f)"},"table.insert(t,d)": {"body": "table.insert(${1:t},${2: d})","description": "添加table参数\r\n返回值：\r\n  table\r\n例子：\r\nfruits = {\"banana\",\"orange\",\"apple\"}\r\n\r\n-- 在末尾插入\r\ntable.insert(fruits,\"mango\")\r\nprint(\"索引为 4 的元素为 \",fruits[4])\r\n--索引为 4 的元素为     mango\r\n\r\n-- 在索引为 2 的键处插入\r\ntable.insert(fruits,2,\"grapes\")\r\nprint(\"索引为 2 的元素为 \",fruits[2])\r\n--索引为 2 的元素为     grapes\r\n\r\nprint(\"最后一个元素为 \",fruits[5])\r\n--最后一个元素为     mango\r\n","prefix": "table.insert()"},"table.remove(t,i)": {"body": "table.remove(${1:t},${2: i})","description": "移除table参数\r\n返回值：\r\n  table","prefix": "table.remove()"},"string.byte()": {"body": "string.byte()","description": "接收控制字符，返回ASCII码\r\n返回值：\r\n  ASCII码\r\n例子：\r\nstring.byte(\"ABCD\")  --65\r\nstring.byte(\"ABCD\",4) --68\r\n","prefix": "string.byte()"},"string.char()": {"body": "string.char()","description": "接收ASCII码，返回对应的控制字符\r\n返回值：\r\n  字符\r\n例子：\r\nstring.char(97,98,99,100)   --abcd\r\n","prefix": "string.char()"},"string.find()": {"body": "string.find()","description": "查找第一个字符串 s 中匹配到的 pattern\r\n返回值：\r\n  返回匹配字符具体位置。不存在则返回 nil\r\n例子：\r\nstring.find(\"Hello Lua user\", \"Lua\", 1)   --7   9\r\n","prefix": "string.find()"},"string.format()": {"body": "string.format()","description": "格式化字符串\r\n返回值：\r\n  字符串\r\n例子：\r\nstring.format(\"the value is:%d\",4)   --the value is:4\r\n","prefix": "string.format()"},"string.gsub()": {"body": "string.gsub()","description": "字符串替换","prefix": "string.gsub()"},"string.len()": {"body": "string.len()","description": "计算字符串长度\r\n返回值：\r\n  字符串长度\r\n例子：\r\nstring.len(\"abc\")  --3\r\n","prefix": "string.len()"},"string.lower()": {"body": "string.lower()","description": "字符串全部转为小写字母\r\n返回值：\r\n  小写字母字符串","prefix": "string.lower()"},"string.rep()": {"body": "string.rep()","description": "字符串拷贝\r\n返回值：\r\n  字符串\r\n例子：\r\nstring.rep(\"abcd\",2)   --abcdabcd\r\n","prefix": "string.rep()"},"string.reverse()": {"body": "string.reverse()","description": "字符串反转\r\n返回值：\r\n  反转后的字符串\r\n例子：\r\nstring.reverse(\"Luat\")  --tauL\r\n","prefix": "string.reverse()"},"string.split(str, delimiter)": {"body": "string.split(${1:str},${2: delimiter})","description": "按照指定分隔符分割字符串\r\n返回值：\r\n分割后的字符串列表\r\n例子：\r\n\"123,456,789\":split(',') -> {'123','456','789'}\r\n","prefix": "string.split(str, delimiter)"},"string.upper()": {"body": "string.upper()","description": "字符串全部转为大写字母\r\n返回值：\r\n  大写字母字符串","prefix": "string.upper()"},}
for module in modules:
    for api in module["api"]:
        api_str = api["api"][0:api["api"].find("(")]
        body = api["api"].replace(" ","")
        arg_s = re.search(r"\((.+)\)",body)#内部参数取出来，加上编号搞
        if arg_s:
            body = api_str + "("
            arg_s = arg_s.group(1).split(",")
            n = 1
            for i in arg_s:
                body += "${"+str(n)+":"+i+"},"
                n+=1
            body = body[0:-1]+")"
        snippet[api_str] = {
            'body': body,
            'description': api["summary"],
            'prefix': api_str,
        }
s = io.open(snippet_path,"w")
s.write(json.dumps(snippet))
s.close()
try:
    shutil.rmtree("../../luatos-wiki/api/")
    os.mkdir("../../luatos-wiki/api/")
except:
    pass

doc = open("../../luatos-wiki/api/index.rst", "a+",encoding='utf-8')
doc.write("LuatOS接口文档\n")
doc.write("==============\n\n")
doc.write("请点击左侧列表，查看各个接口。如需搜索，请直接使用搜索框进行搜索。\n\n")
doc.write(".. toctree::\n\n")


for module in modules:
    mdoc = open("../../luatos-wiki/api/"+module["module"]+".md", "a+",encoding='utf-8')
    mdoc.write("# "+module["module"]+" - "+module["summary"]+"\n\n")
    if len(module["url"]) > 0:
        mdoc.write("> 本页文档由[这个文件]("+module["url"]+")自动生成。如有错误，请提交issue或帮忙修改后pr，谢谢！\n\n")
    doc.write("   "+module["module"]+"\n")
    for api in module["api"]:
        mdoc.write("## "+api["api"]+"\n\n")
        mdoc.write(api["summary"]+"\n\n")

        mdoc.write("**参数**\n\n")
        if len(api["args"]) > 0:
            mdoc.write("|传入值类型|解释|\n|-|-|\n")
            for arg in api["args"]:
                mdoc.write("|"+arg["type"].replace("|","\|")+"|"+arg["summary"].replace("|","\|")+"|\n")
            mdoc.write("\n")
        else:
            mdoc.write("无\n\n")

        mdoc.write("**返回值**\n\n")
        if len(api["return"]) > 0:
            mdoc.write("|返回值类型|解释|\n|-|-|\n")
            for arg in api["return"]:
                mdoc.write("|"+arg["type"].replace("|","\|")+"|"+arg["summary"].replace("|","\|")+"|\n")
            mdoc.write("\n")
        else:
            mdoc.write("无\n\n")

        mdoc.write("**例子**\n\n")
        if len(api["usage"]) == 0:
            mdoc.write("无\n\n")
        else:
            mdoc.write("```lua\n"+api["usage"]+"\n```\n\n")

        mdoc.write("---\n\n")

    mdoc.close()
    os.system("pandoc -o ./../../luatos-wiki/api/"+module["module"]+".rst ./../../luatos-wiki/api/"+module["module"]+".md")
    os.remove("./../../luatos-wiki/api/"+module["module"]+".md")

doc.close()
