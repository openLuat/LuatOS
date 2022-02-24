#!/usr/bin/python
# -*- coding: UTF-8 -*-

import sys
import os
import io
import re
import json
import shutil

source_path = r"../luat"
if len(sys.argv) >= 3:
    source_path = sys.argv[1]

print("path:")
print(source_path)

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

for home, dirs, files in os.walk(source_path+"/../bsp/rtt"):
    for filename in files:
        if filename.endswith(".c"):
            file_list.append(os.path.join(home, filename))

#注释的格式：
# /*
# @sys_pub mod
# 第一行写明消息的用途，如：WIFI扫描结束
# WLAN_SCAN_DONE  （该topic的完整名称）
# @string 第一个传递的数据，@后跟数据类型，空格后跟数据解释，如果没有就别写这几行
# @number 第二个数据
# ...根据实际，列出所有传递的数据
# @usage
# --使用的例子，可多行
# sys.taskInit(function()
#     xxxxxxxxxx
#     xxxxxxx
#     sys.waitUntil("WLAN_SCAN_DONE")
#     xxxxxxxxxx
# end)
# */
modules = []
#数据结构：
# modules = {
#     'mod': [
#         {
#             'topic':'WLAN_SCAN_DONE',
#             'summary': 'WIFI扫描结束',
#             'return': [
#                 {
#                     'type': 'string',
#                     'summary': '第一个传递的数据'
#                 },
#                 {
#                     'type': 'number',
#                     'summary': '第二个数据'
#                 }
#             ],
#             'usage': 'sys.taskInit(function()...'
#         },
#         ...
#     ],
#     ...
# }

print("found %d files" % len(file_list))

modules = {}
for file in file_list:
    text = ""
    try:
        f = io.open(file,"r",encoding="utf-8")
        text = f.read()
        f.close()
    except:
        #print("read %s fail, maybe not use utf8" % file)
        continue

    #后面的数据
    lines = text.splitlines()
    line_now = 0
    while line_now<len(lines)-3:
        #匹配api完整名称行
        name = re.search(r" *@sys_pub *(.+) *",lines[line_now+1],re.I)
        if lines[line_now].startswith("/*") and name:
            mod = name.group(1)#模块名
            api = {}
            api["topic"] = re.search(r" *(.+) *",lines[line_now+3],re.I).group(1)
            api["summary"] = re.search(r" *(.+) *",lines[line_now+2],re.I).group(1)
            line_now += 4
            api["return"] = []
            api["usage"] = ""
            arg_re = r" *@([^ ]+) +(.+) *"
            usage_re = r" *@usage *"
            #匹配返回参数
            while True:
                arg = re.search(arg_re,lines[line_now],re.I)
                arg_return = re.search(usage_re,lines[line_now],re.I)
                if arg and not arg_return:
                    api["return"].append({'type':arg.group(1),'summary':arg.group(2)})
                    line_now+=1
                else:
                    break
            #匹配用法例子
            while True:
                arg = re.search(usage_re,lines[line_now],re.I)
                if arg:
                    line_now+=1
                    while lines[line_now].find("*/") < 0:
                        api["usage"] += lines[line_now]+"\n"
                        line_now+=1
                else:
                    line_now+=2
                    break
            if not (mod in modules):
                modules[mod] = []
            modules[mod].append(api)
        else:
            line_now += 1

##################  接口数据提取完毕  ##################

doc = open("../../luatos-wiki/api/sys_pub.md", "a+",encoding='utf-8')
doc.write("# sys系统消息\n")
doc.write("\n\n")
doc.write("此处列举了LuatOS框架中自带的系统消息列表\n\n")
doc.write("\n\n")

for _, (name,module) in enumerate(modules.items()):
    doc.write("## "+name+"\n\n")
    doc.write("\n\n")
    doc.write("["+name+"接口文档页](https://wiki.luatos.com/api/"+name+".html)\n\n")
    doc.write("\n\n")
    for pub in module:
        doc.write("### "+pub["topic"]+"\n\n")
        doc.write(pub["summary"]+"\n\n")

        doc.write("**额外返回参数**\n\n")
        if len(pub["return"]) > 0:
            doc.write("|返回参数类型|解释|\n|-|-|\n")
            for arg in pub["return"]:
                doc.write("|"+arg["type"].replace("|","\|")+"|"+arg["summary"].replace("|","\|")+"|\n")
            doc.write("\n")
        else:
            doc.write("无\n\n")

        doc.write("**例子**\n\n")
        if len(pub["usage"]) == 0:
            doc.write("无\n\n")
        else:
            doc.write("```lua\n"+pub["usage"]+"\n```\n\n")

        doc.write("---\n\n")

doc.close()
