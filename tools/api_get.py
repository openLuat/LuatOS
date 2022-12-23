import re
import io
import os

def get_file_list(paths, ext = ".c"):
    file_list = []
    for path in paths:
        for home, _, files in os.walk(path):
            for filename in files:
                if filename.endswith(ext):
                    file_list.append(os.path.join(home, filename))
    return file_list

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
# @demo  demo路径
# @video 视频链接
# @usage
# --使用的例子，可多行
# lcoal a,b,c = module.function("test",nil,{1,2,3})
# */
# static int l_module_function(lua_State *L) {
#     //一堆代码
# }
#
#//@const NONE number 无校验
########################################################
#数据结构：
# modules = [
#     {
#         'module': 'adc',
#         'summary': '数模转换',
#         'url': 'https://xxxxxx',
#         'demo': 'adc',
#         'video': 'https://xxxxx',
#         'usage': '--xxxxxxx',
#         'tag': 'bsp里的tag',
#         'const': [
# {
#    'var':'uart.NONE',
#    'type':'number',
#    'summary':'无校验',
# },
# ],
#         'api':[
#             {
#                 'api':'adc.read(id)',
#                 'summary': '读取adc通道',
#                 'tag': 'bsp里的tag',
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
def get_modules(file_list, start="/*", end="*/"):
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
        r = re.search(re.escape(start) + r" *\n *@module *(\w+)\n *@summary *(.+)\n",text,re.I|re.M)
        if r:
            module["module"] = r.group(1)
            module["summary"] = r.group(2)
            module["usage"] = ""
            module["demo"] = ""
            module["video"] = ""
            module["tag"] = ""
            module["api"] = []
            module["const"] = []
        else:
            continue

        for mstep in range(len(modules)-1,-1,-1):
            if modules[mstep]["module"] == module["module"]:
                module = modules[mstep]
                del modules[mstep]
                module["url"] = ""

        #后面的数据
        lines = text.splitlines()
        line_now = 0
        isGotApi = False #是否已经有过接口？ 或者是否第一段注释已结束？
        while line_now<len(lines)-3:
            if lines[line_now].find(end) >= 0:
                isGotApi = True #第一段注释结束了，不用找例子了
            if not isGotApi:#库自带的例子
                if re.search(" *@demo *.+",lines[line_now],re.I):
                    module["demo"] = "https://gitee.com/openLuat/LuatOS/tree/master/demo/"
                    module["demo"] += re.search(" *@demo * (.+) *",lines[line_now],re.I).group(1)
                    line_now+=1
                    continue
                if re.search(" *@video *.+",lines[line_now],re.I):
                    module["video"] = re.search(" *@video * (.+) *",lines[line_now],re.I).group(1)
                    line_now+=1
                    continue
                if re.search(" *@tag *.+",lines[line_now],re.I):
                    module["tag"] = re.search(" *@tag * (.+) *",lines[line_now],re.I).group(1)
                    line_now+=1
                    continue
                if re.search(" *@usage *",lines[line_now],re.I):
                    line_now+=1
                    while lines[line_now].find(end) < 0:
                        module["usage"] += lines[line_now]+"\n"
                        line_now+=1
                    isGotApi = True
                    continue
            #匹配api完整名称行
            name = re.search(r" *@api *(.+) *",lines[line_now+2],re.I)
            if not name:
                name = re.search(r" *@function *(.+) *",lines[line_now+2],re.I)
            #匹配常量
            const_re = re.search(r"[ \-]*//@const +(.+?) +(.+?) +(.+)",lines[line_now],re.I)
            if const_re:
                const = {}
                const["var"] = module["module"]+"."+const_re.group(1)
                const["type"] = const_re.group(2)
                const["summary"] = const_re.group(3)
                module["const"].append(const)
            if lines[line_now].startswith(start) and name:
                api = {}
                api["api"] = name.group(1)
                api["summary"] = re.search(r" *(.+) *",lines[line_now+1],re.I).group(1)
                api["tag"] = ""
                line_now += 3
                api["args"] = []
                api["return"] = []
                api["usage"] = ""
                if re.search(" *@tag *.+",lines[line_now],re.I):
                    api["tag"] = re.search(" *@tag * (.+) *",lines[line_now],re.I).group(1)
                    line_now+=1
                arg_re = r" *@([^ ]+) +(.+) *"
                return_re = r" *@return *([^ ]+) +(.+) *"
                isGotApi = True
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
                        while lines[line_now].find(end) < 0:
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
    return modules
