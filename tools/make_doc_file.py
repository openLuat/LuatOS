import shutil
import os

def make(path,modules,index_text):
    try:
        shutil.rmtree(path)
    except:
        pass
    os.mkdir(path)

    doc = open(path+"index.rst", "a+",encoding='utf-8')
    doc.write(index_text)

    for module in modules:
        mdoc = open(path+module["module"]+".md", "a+",encoding='utf-8')
        mdoc.write("# "+module["module"]+" - "+module["summary"]+"\n\n")
        if len(module["url"]) > 0:
            mdoc.write("> 本页文档由[这个文件]("+module["url"]+")自动生成。如有错误，请提交issue或帮忙修改后pr，谢谢！\n\n")

        if len(module["demo"]) > 0:
            mdoc.write("> 本库有专属demo，[点此链接查看"+module["module"]+"的demo例子]("+module["demo"]+")\n")
        if len(module["video"]) > 0:
            mdoc.write("> 本库还有视频教程，[点此链接查看]("+module["video"]+")\n\n")
        else:
            mdoc.write("\n")

        if len(module["usage"]) > 0:
            mdoc.write("**示例**\n\n")
            mdoc.write("```lua\n"+module["usage"]+"\n```\n\n")

        if len(module["const"]) > 0:
            mdoc.write("## 常量\n\n")
            mdoc.write("|常量|类型|解释|\n|-|-|-|\n")
            for const in module["const"]:
                mdoc.write("|"+const["var"].replace("|","\|")+"|"+const["type"].replace("|","\|")+"|"+const["summary"].replace("|","\|")+"|\n")
            mdoc.write("\n\n")

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

    doc.close()


def get_description(api):
    s = api["api"]+" - "+api["summary"]+"\n"
    if len(api["args"]) > 0:
        s = s + "传入值：\n"
        for arg in api["args"]:
            s  = s + arg["type"] + " " + arg["summary"]+"\n"
    if len(api["return"]) > 0:
        s = s + "返回值：\n"
        for arg in api["return"]:
            s  = s + arg["type"] + " " + arg["summary"]+"\n"
    if len(api["usage"]) > 0:
        s = s + "例子：\n" + api["usage"]
    return s
