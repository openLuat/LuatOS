#!/usr/bin/python
# -*- coding: UTF-8 -*-

'''
使用 https://github.com/eliben/pycparser 生成 Lua 绑定 LVGL的 API
'''

import sys
import subprocess
import os

from pycparser import c_parser, c_ast, parse_file


methods = {}

class FuncDefVisitor(c_ast.NodeVisitor):

    def __init__(self, group, prefix):
        self.group = group
        self.prefix = prefix
        #print("FuncDefVisitor >> " + prefix)

    def visit_FuncDecl(self, node):
        try :
            is_ptr_return = False
            if node.type.__class__.__name__ == "PtrDecl":
                is_ptr_return = True
                if type(node.type.type) == c_ast.TypeDecl :
                    method_name = node.type.type.declname
                elif type(node.type.type) == c_ast.PtrDecl :
                    # 返回值是 char**,暂不支持了
                    #  lv_btnmatrix_get_map_array
                    #  lv_calendar_get_day_names
                    #  lv_calendar_get_month_names
                    #  lv_keyboard_get_map_array,
                    node.type.type.show()
                    return
                else:
                    node.type.type.show()
                    sys.exit()
            else :
                method_name = node.type.declname
            if not method_name.startswith(self.prefix):
                return
            if method_name.endswith("cb_t") or method_name.endswith("_f_t"):
                return
            if method_name in ["lv_btnmatrix_set_map", "lv_calendar_set_month_names",
                               "lv_calendar_set_day_names", "lv_label_set_text_fmt", 
                               "lv_msgbox_add_btns", "lv_msgbox_set_text_fmt", 
                               "lv_table_set_cell_value_fmt", "lv_keyboard_set_map"] :
                return
            # 因为 points[] 无法处理的方法
            if method_name in ["lv_indev_set_button_points", "lv_draw_triangle",
                               "lv_canvas_draw_line", "lv_canvas_draw_polygon", 
                               "lv_line_set_points", "lv_tileview_set_valid_positions",
                               "lv_draw_polygon"] :
                return
            # 因为各种数组无法处理的方法
            if method_name in ["lv_btnmatrix_set_ctrl_map", "lv_keyboard_set_ctrl_map", "lv_calendar_set_highlighted_dates",
                               "lv_chart_set_points", "lv_chart_set_ext_array", "lv_gauge_set_needle_count"] :
                return
            #print(method_name + "(", end="")
            method_args = []
            method_return = "void"
            if type(node.type) == c_ast.TypeDecl :
                method_return = node.type.type.names[0]
            else :
                method_return = node.type.type.type.names[0] + "*"
            if node.args :
                #print("has args")
                for arg in node.args:
                    #print(arg.type.__class__.__name__)
                    #print(arg.name)
                    if arg.type.__class__.__name__ == "PtrDecl" :
                        # 指针类型
                        #print(arg.type.declname, "*", arg.type.type.names[0], )
                        #arg.type.show()
                        method_args.append([arg.name, arg.type.type.type.names[0] + "*"])
                    elif arg.type.__class__.__name__ == "TypeDecl":
                        if arg.type.type.names[0] != "void" :
                            method_args.append([arg.name, arg.type.type.names[0]])
                    elif arg.type.__class__.__name__ == "ArrayDecl":
                        method_args.append([arg.name, arg.type.type.type.names[0] + "[]"])
                    else :
                        #print("FUCK", arg.type.__class__.__name__, arg.type.names[0], arg.name, ",", )
                        print(arg.type.__class__.__name__)
                        arg.show()
                        sys.exit()
                    #print(arg.type, arg.name, ",",)
            sb = method_return + " " + method_name + "("
            if len(method_args) > 0 :
                for arg in method_args :
                    sb += str(arg[1]) + " " + str(arg[0]) + ", "
                sb = sb[:-2]
            sb += ");"
            #print(sb)
            if not self.group in methods :
                methods[self.group] = {}
            if not self.prefix in methods[self.group]:
                methods[self.group][self.prefix] = []
            methods[self.group][self.prefix].append({"group":self.group, "prefix":self.prefix, "name":method_name, "ret":method_return, "args":method_args})
        except  Exception:
            import traceback
            traceback.print_exc()
            sys.exit()

def handle_groups(group, path):
    for name in os.listdir(path) :
        if not name.endswith(".h"):
            continue
        if name in ["lv_obj_style_dec.h", "lv_theme_empty.h", "lv_theme_material.h", "lv_theme_mono.h", "lv_theme_template.h"]:
            continue
        if name.startswith("lv_draw_") :
            continue
        try :
            #print(">>>>>>>>>>>>" + name)
            ast = parse_file(os.path.join(path, name), use_cpp=True, cpp_path="clang", cpp_args=['-E', '-I../../../pycparser/utils/fake_libc_include', '-I.', '-I../../lua/include', '-I../../luat/include'])
            v = FuncDefVisitor("lv_" + group, name[:-2])
            v.visit(ast)
        except  Exception :
            print("error>>>>>>>>>>>>" + name)
        #sys.exit()

def main():
    handle_groups("core", "src/lv_core/")
    handle_groups("draw", "src/lv_draw/")
    handle_groups("font", "src/lv_font/")
    handle_groups("misc", "src/lv_misc/")
    handle_groups("themes", "src/lv_themes/")
    handle_groups("widgets", "src/lv_widgets/")

    print("============================================================")

    if not os.path.exists("gen/") :
        os.makedirs("gen/")
    # 首先, 输出全部.h文件
    with open("gen/luat_lv_gen.h", "w") as fh :
        fh.write("\r\n")
        fh.write("#include \"luat_base.h\"\n")
        #fh.write("#include \"lvgl.h\"\n")
        fh.write("#ifndef LUAT_LV_GEN\n")
        fh.write("#define LUAT_LV_GEN\n")
        for group in methods :
            fh.write("\n")
            fh.write("// group " + group + "\n")
            for prefix in methods[group] :
                # 输出头文件
                fh.write("// prefix " + group + " " + prefix + "\n")
                for m in methods[group][prefix] :
                    sb = "int luat_" + m["name"] + "(lua_State *L);\n"
                    fh.write(sb)

                # 然后, 输出src文件
                if not os.path.exists("gen/"+group+ "/") :
                    os.makedirs("gen/"+group+"/")
                with open("gen/"+group+"/luat_" + prefix + ".c", "w") as f :
                    f.write("\r\n")
                    f.write("#include \"luat_base.h\"\n")
                    #f.write("#include \"gen/%s/luat_%s.h\"\n" % (group, prefix))
                    f.write("#include \"lvgl.h\"\n")
                    f.write("\n\n")

                    for m in methods[group][prefix] :
                        f.write("//  " + mtostr(m) + "\n")
                        f.write("int luat_" + m["name"] + "(lua_State *L) {\n")
                        argnames = []
                        if len(m["args"]) > 0:
                            _index = 1
                            _miss_arg_type = False
                            for arg in m["args"] :
                                #if (arg[1].endswith("*")) :
                                #    f.write("    %s %s = NULL;\n" % (str(arg[1]), str(arg[0])))
                                #else :
                                #    f.write("    %s %s;\n" % (str(arg[1]), str(arg[0])))
                                cnt, incr, miss_arg_type = gen_lua_arg(arg[1], arg[0], _index)
                                _miss_arg_type = _miss_arg_type or miss_arg_type
                                f.write("    " + cnt + "\n")
                                if miss_arg_type :
                                    f.write("    // miss arg convert\n")
                                _index += incr
                                argnames.append(str(arg[0]))
                        else :
                            pass
                        if "void" != m["ret"] :
                            if m["ret"].endswith("*") :
                                f.write("    %s ret = NULL;\n" % (m["ret"], ))
                            else :
                                f.write("    %s ret;\n" % (m["ret"], ))
                        else :
                            pass # end of non-void return
                        #f.write("    //----\n")
                        #f.write("    \n")
                        #f.write("    //----\n")
                        if "void" != m["ret"] :
                            f.write("    ret = ")
                        else:
                            f.write("    ")
                        f.write(m["name"] + "(")
                        f.write(" ,".join(argnames))
                        f.write(");\n")

                        # 处理方法的返回值

                        # 无返回的
                        if "void" == m["ret"] :
                            f.write("    return 0;\n")
                        elif m["ret"] == "char*":
                            f.write("    lua_pushstring(L, ret);\n")
                            f.write("    return 1;\n")
                        # 返回值是指针的
                        elif m["ret"].endswith("*") :
                            f.write("    lua_pushlightuserdata(L, ret);\n")
                            f.write("    return 1;\n")
                        # 返回值是数值的
                        elif m["ret"] == "lv_res_t":
                            f.write("    lua_pushboolean(L, ret == 0 ? 1 : 0);\n")
                            f.write("    lua_pushinteger(L, ret);\n")
                            f.write("    return 2;\n")
                        # 返回值是布尔值的
                        elif m["ret"] == "bool" :
                            f.write("    lua_pushboolean(L, ret);\n")
                            f.write("    return 1;\n")
                        # 其他的暂不支持
                        else :
                            f.write("    return 0;\n")
                        f.write("}\n\n")

        fh.write("#endif\n")

def mtostr(m) :
    sb = m["ret"] + " " + m["name"] + "("
    if len(m["args"]) > 0 :
        for arg in m["args"] :
            sb += str(arg[1]) + " " + str(arg[0]) + ", "
        sb = sb[:-2]
    sb += ")"
    return sb

map_lua_arg = {
    "lv_coord_t" : {"fmt": "{} {} = (lv_coord_t)luaL_checkinteger(L, {});", "incr" : 1},
    "int16_t" : {"fmt": "{} {} = (int16_t)luaL_checkinteger(L, {});", "incr" : 1},
    "int8_t" : {"fmt": "{} {} = (int8_t)luaL_checkinteger(L, {});", "incr" : 1},
    "int32_t" : {"fmt": "{} {} = (int32_t)luaL_checkinteger(L, {});", "incr" : 1},
    "uint8_t" : {"fmt": "{} {} = (uint8_t)luaL_checkinteger(L, {});", "incr" : 1},
    "uint16_t" : {"fmt": "{} {} = (uint16_t)luaL_checkinteger(L, {});", "incr" : 1},
    "uint32_t" : {"fmt": "{} {} = (uint32_t)luaL_checkinteger(L, {});", "incr" : 1},
    "bool" : {"fmt": "{} {} = (bool)lua_toboolean(L, {});", "incr" : 1},
    "size_t" : {"fmt": "{} {} = (size_t)luaL_checkinteger(L, {});", "incr" : 1},
    "char" : {"fmt": "{} {} = (char)luaL_checkinteger(L, {});", "incr" : 1},

    "lv_anim_enable_t" : {"fmt": "{} {} = (lv_anim_enable_t)luaL_checkinteger(L, {});", "incr" : 1},# 与uint8等价
    "lv_scrollbar_mode_t" :  {"fmt": "{} {} = (lv_scrollbar_mode_t)luaL_checkinteger(L, {});", "incr" : 1},# 与uint8等价
    "lv_layout_t" : {"fmt": "{} {} = (lv_layout_t)luaL_checkinteger(L, {});", "incr" : 1},# 与uint8等价

    "lv_style_property_t" : {"fmt": "{} {} = (lv_style_property_t)luaL_checkinteger(L, {});", "incr" : 1}, # uint16_t
    "lv_style_state_t" : {"fmt": "{} {} = (lv_style_state_t)luaL_checkinteger(L, {});", "incr" : 1}, # uint16_t

    #"lv_color_t" : {"fmt": "{} {} = \\{.full = luaL_checkinteger(L, {})\\};", "incr" : 1},

    "lv_align_t" : {"fmt": "{} {} = (lv_align_t)luaL_checkinteger(L, {});", "incr" : 1},
    "lv_state_t" : {"fmt": "{} {} = (lv_state_t)luaL_checkinteger(L, {});", "incr" : 1},
    "lv_style_int_t" : {"fmt": "{} {} = (lv_style_int_t)luaL_checkinteger(L, {});", "incr" : 1},
    "lv_style_property_t" : {"fmt": "{} {} = (lv_style_property_t)luaL_checkinteger(L, {});", "incr" : 1},
    "lv_fit_t" : {"fmt": "{} {} = (lv_fit_t)luaL_checkinteger(L, {});", "incr" : 1},

    "char*" : {"fmt": "{} {} = (char*)luaL_checkstring(L, {});", "incr" : 1},
}


def gen_lua_arg(tp, name, index):
    if tp in map_lua_arg :
        fmt = map_lua_arg[tp]["fmt"]
        return fmt.format(str(tp), str(name), str(index)), map_lua_arg[tp]["incr"], False
    if tp.endswith("*"):
        return "{} {} = lua_touserdata(L, {});".format(str(tp), str(name), str(index)), 1, False
    if tp == "lv_color_t" :
        return "%s %s = {0};\n" % (tp, name) + "    %s.full = luaL_checkinteger(L, %d);" % (name, index), 1, False
    print("miss arg type", tp)
    return "{} {};".format(str(tp), str(name)), 1, True

if __name__ == '__main__':
    main()
