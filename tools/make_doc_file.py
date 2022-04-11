import shutil
import os

def make(path,modules,index_text):
    try:
        shutil.rmtree(path)
        os.mkdir(path)
    except:
        pass

    doc = open(path+"index.rst", "a+",encoding='utf-8')
    doc.write(index_text)
    
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

    doc.close()
