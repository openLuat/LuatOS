#!/usr/bin/python
# -*- coding: UTF-8 -*-

'''
使用 https://github.com/eliben/pycparser 生成 Lua 绑定 LVGL的 API
'''

import sys
import subprocess
import os
import traceback

from pycparser import c_parser, c_ast, parse_file


methods = {}
enums = []
enum_names = set({})
miss_arg_types = set({})
miss_ret_types = set({})


# 各种命名, 但全都上int变种
map_lv_ints = ["lv_arc_type_t", "lv_style_int_t", "lv_coord_t", "lv_spinner_dir_t", "lv_drag_dir_t",
                    "lv_keyboard_mode_t", "int16_t", "int8_t", "int32_t", "uint8_t", "uint16_t", "uint32_t",
                    "lv_chart_type_t", "lv_border_side_t", "lv_anim_value_t", "lv_img_src_t", "lv_text_decor_t",
                    "lv_align_t", "lv_spinner_type_t", "lv_dropdown_dir_t", "lv_scrollbar_mode_t",
                    "lv_label_long_mode_t", "lv_chart_axis_t", "lv_blend_mode_t", "lv_bidi_dir_t",
                    "lv_slider_type_t", "lv_tabview_btns_pos_t",
                    "lv_indev_type_t", "lv_disp_size_t",
                    "lv_opa_t", "lv_label_align_t", "lv_fit_t", "lv_bar_type_t", "lv_btn_state_t",
                    "lv_gesture_dir_t", "lv_state_t", "lv_layout_t", "lv_cpicker_color_mode_t",
                    "lv_disp_rot_t", "lv_grad_dir_t", "lv_chart_type_t", "lv_text_align_t", "lv_arc_mode_t", "lv_table_cell_ctrl_t",
                    "lv_scroll_snap_t", "lv_style_prop_t", "lv_draw_mask_line_side_t", "lv_obj_flag_t",
                    "lv_roller_mode_t", "lv_slider_mode_t", "lv_arc_mode_t", "lv_text_align_t", "lv_bar_mode_t", "lv_part_t",
                    "lv_text_flag_t", "lv_style_selector_t", "lv_dir_t", "lv_scroll_snap_t", "lv_style_prop_t", "lv_base_dir_t",
                    "lv_slider_mode_t", "lv_arc_mode_t", "lv_text_align_t", "lv_btnmatrix_ctrl_t"]

custom_method_names = ["lv_img_set_src", "lv_imgbtn_set_src"]

class FuncDefVisitor(c_ast.NodeVisitor):

    def __init__(self, group, prefix):
        self.group = group
        self.prefix = prefix
        #print("FuncDefVisitor >> " + prefix)

    def visit_Enum(self, node):
        if not node.values :
            return
        try :
            _index_val = None
            for e in node.values:
                k = e.name
                val = e.name
                '''
                if e.value :
                    if e.value.__class__.__name__ == "Constant" :
                        if e.value.value.startswith("0x") :
                            val = int(e.value.value[2:], 16)
                        else :
                            val = int(e.value.value)
                        #print("add enum", e.name, val)
                        if _index_val == None :
                            _index_val = val + 1
                    else :
                        print("skip enum ", e.name, e.value)
                        pass
                else:
                    if _index_val == None :
                        _index_val = 0
                    val = _index_val
                    #print("add enum", e.name, _index_val)
                    _index_val += 1
                '''
                if val != None and k not in enum_names :
                    enum_names.add(k)
                    enums.append([k, val])
        except Exception :
            import traceback
            traceback.print_exc()
            sys.exit()

    def visit_FuncDecl(self, node):
        try :
            is_ptr_return = False
            method_name = None
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
            # 一些回调方法, 这些没法自动生成
            if method_name.endswith("_cb") or method_name.endswith("cb_t") or method_name.endswith("_f_t"):
                print("skip callback func", method_name)
                return
            if method_name in ["lv_btnmatrix_set_map", "lv_calendar_set_month_names",
                               "lv_calendar_set_day_names", "lv_label_set_text_fmt", 
                               "lv_msgbox_add_btns", "lv_msgbox_set_text_fmt", 
                               "lv_table_set_cell_value_fmt", "lv_keyboard_set_map", 
                               "lv_dropdown_get_selected_str", "lv_roller_get_selected_str",
                               "lv_canvas_set_buffer", "lv_dropdown_set_symbol"] :
                return
            # 因为 points[] 无法处理的方法
            if method_name in ["lv_indev_set_button_points", "lv_draw_triangle",
                               "lv_canvas_draw_line", "lv_canvas_draw_polygon", 
                               "lv_line_set_points", "lv_tileview_set_valid_positions",
                               "lv_draw_polygon"] :
                return
            # 因为各种数组无法处理的方法
            if method_name in ["lv_btnmatrix_set_ctrl_map", "lv_keyboard_set_ctrl_map", "lv_calendar_set_highlighted_dates",
                               "lv_chart_set_points", "lv_chart_set_ext_array", "lv_gauge_set_needle_count", "lv_style_transition_dsc_init"] :
                return
            # 这方法不太可能有人用吧,返回值是uint8_t*,很少见
            if method_name in ["lv_font_get_glyph_bitmap"] :
                return
            if method_name in custom_method_names :
                return
            #print(method_name + "(", end="")
            method_args = []
            method_return = "void"
            if type(node.type) == c_ast.TypeDecl :
                method_return = node.type.type.names[0]
            elif type(node.type.type.type) == c_ast.Struct :
                if node.type.type.type.name == "_lv_obj_t":
                    method_return = "lv_obj_t*"
                else :
                    method_return = "struct" + node.type.type.type.name + "*"
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
                        if arg.type.type.type.__class__.__name__ == "Struct" :
                            if arg.type.type.type.name == "_lv_obj_t":
                                method_args.append([arg.name, "lv_obj_t*"])
                            else :
                                method_args.append([arg.name, "struct "+arg.type.type.type.name+"*"])
                        else :
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
            print ("method_name", method_name, "error")
            import traceback
            traceback.print_exc()
            sys.exit()

def handle_groups(group, path):
    for name in os.listdir(path) :
        if not name.endswith(".h"):
            continue
        if name in ["lv_obj_style_gen.h", "lv_async.h", "lv_fs.h", "lv_log.h", "lv_mem.h",
                    "lv_printf.h", "lv_style_gen.h", "lv_timer.h", "lv_indev.h", "lv_img_decoder.h", "lv_img_cache.h", "lv_img_buf.h",
                    "lv_task.h", "lv_debug.h"]:
            continue
        if name.startswith("lv_draw_") :
            continue
        try :
            #print(">>>>>>>>>>>>" + name)
            ast = parse_file(os.path.join(path, name), use_cpp=True, cpp_path='''C:/msys64/mingw32/bin/cpp.exe''', cpp_args=['-E', '-Imock', '-I../../../pycparser/utils/fake_libc_include', '-I.', '-I../../lua/include', '-I../../luat/include'])
            v = FuncDefVisitor("lv_" + group, name[:-2])
            v.visit(ast)
        except  Exception :
            print("error>>>>>>>>>>>>" + name)
            #traceback.print_exc()
        #sys.exit()

def make_style_dec():

    import json

    defines = []

    with open("src/lv_core/lv_obj_style_dec.h") as f :
        for line in f.readlines():
            if line.startswith("_LV_OBJ_STYLE_SET_GET_DECLARE") :
                desc = line[len("_LV_OBJ_STYLE_SET_GET_DECLARE")+1:-2].strip()
                vals = desc.split(", ")
                if vals[1] == "transition_path":
                    continue
                defines.append(vals)

    with open("gen/luat_lv_style_dec.h", "w") as f :
        f.write('''#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_lvgl.h"
#include "lvgl.h"
        
''')
        RTL = []
        for dec in defines :
            # 添加 set和get
            f.write("int luat_lv_style_set_%s(lua_State *L);\n" % (dec[1], ))
            f.write("int luat_lv_style_get_%s(lua_State *L);\n" % (dec[1], ))
            RTL.append("{\"style_set_%s\", luat_lv_style_set_%s, 0}," % (dec[1],dec[1],))
            #RTL.append("{\"style_get_%s\", luat_lv_style_get_%s, 0}," % (dec[1],dec[1],))
        f.write("\n")
        f.write("#define LUAT_LV_STYLE_DEC_RLT ")
        f.write("\\\n".join(RTL))
        f.write("\n")

    with open("gen/lv_core/luat_lv_style_dec.c", "w") as f :
        f.write('''#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_lvgl.h"
#include "lvgl.h"
        
''')    
        for dec in defines :
            # 先添加set方法
            f.write("int luat_lv_style_set_%s(lua_State *L){\n" % (dec[1], ))
            f.write("    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);\n")
            f.write("    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);\n")
            if dec[2] in map_lv_ints:
                f.write("    %s %s = (%s)luaL_checkinteger(L, 3);\n" % (dec[2], dec[3], dec[2]))
                f.write("    lv_style_set_%s(_style, state, %s);\n" % (dec[1], dec[3]))
            elif dec[2] == "bool" :
                f.write("    %s %s = (%s)lua_toboolean(L, 3);\n" % (dec[2], dec[3], dec[2]))
                f.write("    lv_style_set_%s(_style, state, %s);\n" % (dec[1], dec[3]))
            elif dec[2] == "lv_color_t" :
                f.write("    %s %s;\n" % (dec[2], dec[3]))
                f.write("    %s.full = luaL_checkinteger(L, 3);\n" % (dec[3],))
                f.write("    lv_style_set_%s(_style, state, %s);\n" % (dec[1], dec[3]))
            elif dec[2] == "const char *":
                f.write("    %s %s = (%s)luaL_checkstring(L, 3);\n" % (dec[2], dec[3], dec[2]))
                f.write("    lv_style_set_%s(_style, state, %s);\n" % (dec[1], dec[3]))
            elif dec[2] == "const lv_font_t *" or dec[2] == "lv_font_t*":
                f.write("    %s %s = (%s)lua_touserdata(L, 3);\n" % (dec[2], dec[3], dec[2]))
                f.write("    lv_style_set_%s(_style, state, %s);\n" % (dec[1], dec[3]))
            else :
                f.write("    %s %s;\n" % (dec[2], dec[3]))
                f.write("    // TODO %s %s\n" % (dec[2], dec[3]))
                f.write("    lv_style_set_%s(_style, state, %s);\n" % (dec[1], dec[3]))
                print("what? " + dec[2] + " " + dec[1])
            f.write("    return 0;\n")
            f.write("}\n\n")

            # 然后添加get方法
            # f.write("int luat_lv_style_get_%s(lua_State *L){\n" % (dec[1], ))
            # f.write("    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);\n")
            # f.write("    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);\n")
            # if dec[2] in map_lv_ints or dec[2] == "bool":
            #     f.write("    %s %s;\n" % (dec[2], dec[3]))
            #     f.write("    lv_style_get_%s(_style, state, &%s);\n" % (dec[1], dec[3]))
            #     f.write("    lua_pushinteger(L, %s);\n" % (dec[3], ))
            # elif dec[2] == "lv_color_t" :
            #     f.write("    %s %s;\n" % (dec[2], dec[3]))
            #     f.write("    lv_style_get_%s(_style, state, &%s);\n" % (dec[1], dec[3]))
            #     f.write("    lua_pushinteger(L, %s.full);\n" % (dec[3], ))
            # elif dec[2] == "const char *":
            #     f.write("    %s %s = (%s)luaL_checkstring(L, 3);\n" % (dec[2], dec[3], dec[2]))
            #     f.write("    lv_style_get_%s(_style, state, %s);\n" % (dec[1], dec[3]))
            #     f.write("    lua_pushstring(L, %s);\n" % (dec[3], ))
            # else :
            #     f.write("    %s %s;\n" % (dec[2], dec[3]))
            #     f.write("    // TODO %s %s\n" % (dec[2], dec[3]))
            #     f.write("    lv_style_get_%s(_style, state, %s);\n" % (dec[1], dec[3]))
            #     f.write("    lua_pushlightuserdata(L, %s);\n" % (dec[3], ))
            #     print("what? " + dec[2] + " " + dec[1])
            # f.write("    return 1;\n")
            # f.write("}\n\n")

def main():
    handle_groups("core", "src/lv_core/")
    handle_groups("draw", "src/lv_draw/")
    handle_groups("font", "src/lv_font/")
    handle_groups("misc", "src/lv_misc/")
    handle_groups("themes", "src/lv_themes/")
    handle_groups("widgets", "src/lv_widgets/")

    print("============================================================")

    gen_methods()

    gen_enums()

    print_miss()

    print("============================================================")
    c = 0
    for group in methods :
        for prefix in methods[group] :
            c += len(methods[group][prefix])
    print("Method count", c)

    make_style_dec()

def print_miss():

    for m in miss_arg_types :
        print("MISS arg type : ", m)
    for m in miss_ret_types :
        print("MISS ret type : ", m)
    pass

def gen_enums():
    if not os.path.exists("gen/") :
        os.makedirs("gen/")

    with open("gen/luat_lv_enum.h", "w") as fh :
        fh.write("\r\n")
        fh.write("#include \"luat_base.h\"\n")
        #fh.write("#include \"lvgl.h\"\n")
        fh.write("#ifndef LUAT_LV_ENUM\n")
        fh.write("#define LUAT_LV_ENUM\n")

        #for e in enums:
        #    if e[0].startswith("_"):
        #        continue
        #    fh.write("#if (" + e[0] + " != " + str(e[1]) + ")\n")
        #    fh.write("#error \"ERROR\"\n")
        #    fh.write("#endif\n")

        fh.write("#include \"rotable.h\"\n")
        fh.write("#define LUAT_LV_ENMU_RLT {\"T\", NULL, 0xFF},\\\n")
        for e in enums:
            if e[0].startswith("_"):
                continue
            fh.write("    {\"%s\", NULL, %s},\\\n" % (e[0][3:], e[1]))

        fh.write("\n\n")

        fh.write("#endif\n")

def gen_methods():

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
                fh.write("\n#define LUAT_" + prefix.upper() + "_RLT ")
                for m in methods[group][prefix] :
                    sb = "    {\"%s\", luat_%s, 0},\\\n" % (m["name"][3:], m["name"])
                    fh.write(sb)
                fh.write("\n")

                # 然后, 输出src文件
                if not os.path.exists("gen/"+group+ "/") :
                    os.makedirs("gen/"+group+"/")
                with open("gen/"+group+"/luat_" + prefix + ".c", "w") as f :
                    f.write("\r\n")
                    f.write("#include \"luat_base.h\"\n")
                    #f.write("#include \"gen/%s/luat_%s.h\"\n" % (group, prefix))
                    f.write("#include \"lvgl.h\"\n")
                    f.write("#include \"luat_lvgl.h\"\n")
                    f.write("\n\n")

                    for m in methods[group][prefix] :
                        f.write("//  " + mtostr(m) + "\n")
                        f.write("int luat_" + m["name"] + "(lua_State *L) {\n")
                        f.write("    LV_DEBUG(\"CALL " + m["name"]+"\");\n");
                        argnames = []
                        if len(m["args"]) > 0:
                            _index = 1
                            _miss_arg_type = False
                            for arg in m["args"] :
                                #if (arg[1].endswith("*")) :
                                #    f.write("    %s %s = NULL;\n" % (str(arg[1]), str(arg[0])))
                                #else :
                                #    f.write("    %s %s;\n" % (str(arg[1]), str(arg[0])))
                                cnt, incr, miss_arg_type = gen_lua_arg(arg[1], arg[0], _index, prefix)
                                _miss_arg_type = _miss_arg_type or miss_arg_type
                                f.write("    " + cnt + "\n")
                                if miss_arg_type :
                                    f.write("    // miss arg convert\n")
                                    miss_arg_types.add(arg[1])
                                _index += incr
                                #if arg[1] == "lv_area_t*" or arg[1] == "lv_point_t*":
                                #    argnames.append("&"+str(arg[0]))
                                #else:
                                #    argnames.append(str(arg[0]))
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
                        gen_lua_ret(m["ret"], f)
                        
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
    "lv_coord_t" : {"fmt": "{} {} = (lv_coord_t)luaL_checknumber(L, {});", "incr" : 1},
    "int16_t" : {"fmt": "{} {} = (int16_t)luaL_checkinteger(L, {});", "incr" : 1},
    "int8_t" : {"fmt": "{} {} = (int8_t)luaL_checkinteger(L, {});", "incr" : 1},
    "int32_t" : {"fmt": "{} {} = (int32_t)luaL_checkinteger(L, {});", "incr" : 1},
    "uint8_t" : {"fmt": "{} {} = (uint8_t)luaL_checkinteger(L, {});", "incr" : 1},
    "uint16_t" : {"fmt": "{} {} = (uint16_t)luaL_checkinteger(L, {});", "incr" : 1},
    "uint32_t" : {"fmt": "{} {} = (uint32_t)luaL_checkinteger(L, {});", "incr" : 1},
    "bool" : {"fmt": "{} {} = (bool)lua_toboolean(L, {});", "incr" : 1},
    "size_t" : {"fmt": "{} {} = (size_t)luaL_checkinteger(L, {});", "incr" : 1},
    "char" : {"fmt": "{} {} = (char)luaL_checkinteger(L, {});", "incr" : 1},

    "lv_anim_enable_t" : {"fmt": "{} {} = (lv_anim_enable_t)lua_toboolean(L, {});", "incr" : 1},# 与uint8等价
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

    "lv_opa_t" : {"fmt": "{} {} = (lv_opa_t)luaL_checknumber(L, {});", "incr" : 1}, # uint8_t
    "lv_img_cf_t" : {"fmt": "{} {} = (lv_img_cf_t)luaL_checkinteger(L, {});", "incr" : 1}, # uint8_t
    "lv_arc_type_t" : {"fmt": "{} {} = (lv_arc_type_t)luaL_checkinteger(L, {});", "incr" : 1}, # uint8_t
    "lv_chart_axis_t" : {"fmt": "{} {} = (lv_chart_axis_t)luaL_checkinteger(L, {});", "incr" : 1}, # uint8_t
    "lv_cpicker_type_t" : {"fmt": "{} {} = (lv_cpicker_type_t)luaL_checkinteger(L, {});", "incr" : 1}, # uint8_t
    "lv_img_cf_t" : {"fmt": "{} {} = (lv_img_cf_t)luaL_checkinteger(L, {});", "incr" : 1}, # uint8_t
    "lv_anim_value_t" : {"fmt": "{} {} = (lv_anim_value_t)luaL_checkinteger(L, {});", "incr" : 1}, # int16
}


def gen_lua_arg(tp, name, index, prefix=None):
    if prefix == "lv_arc" :
        if name == "start" or name == "end" or "uint16_t" == tp or "int16_t" == tp :
            return "{} {} = ({})luaL_checknumber(L, {});".format(tp, name, tp, index), 1, False
    if tp in map_lua_arg :
        fmt = map_lua_arg[tp]["fmt"]
        return fmt.format(str(tp), str(name), str(index)), map_lua_arg[tp]["incr"], False
    if tp in map_lv_ints :
        return "{} {} = ({})luaL_checkinteger(L, {});".format(tp, name, tp, index), 1, False
    #if tp == "lv_area_t*" :
    #    cnt = "lua_pushvalue(L, %d);\n" % (index,)
    #    cnt += "    %s %s = {0};\n" % (tp[:-1], name)
    #    cnt += "    lua_geti(L, -1, 1); %s.x1 = luaL_checkinteger(L, -1); lua_pop(L, 1);\n" % (name,)
    #    cnt += "    lua_geti(L, -1, 2); %s.y1 = luaL_checkinteger(L, -1); lua_pop(L, 1);\n" % (name,)
    #    cnt += "    lua_geti(L, -1, 3); %s.x2 = luaL_checkinteger(L, -1); lua_pop(L, 1);\n" % (name,)
    #    cnt += "    lua_geti(L, -1, 4); %s.y2 = luaL_checkinteger(L, -1); lua_pop(L, 1);\n" % (name,)
    #    cnt += "    lua_pop(L, 1);\n"
    #    return cnt, 1, False
    # if tp == "lv_point_t*" :
    #     cnt = "lua_pushvalue(L, %d);\n" % (index,)
    #     cnt += "    %s %s = {0};\n" % (tp[:-1], name)
    #     cnt += "    lua_geti(L, -1, 1); %s.x = luaL_checkinteger(L, -1); lua_pop(L, 1);\n" % (name,)
    #     cnt += "    lua_geti(L, -1, 2); %s.y = luaL_checkinteger(L, -1); lua_pop(L, 1);\n" % (name,)
    #     cnt += "    lua_pop(L, 1);\n"
    #     return cnt, 1, False
    if tp == "lv_font_t*":
        return "{} {} = ({})lua_touserdata(L, {});".format(str(tp), str(name), str(tp), str(index)), 1, False
    if tp == "lv_color_t" :
        return "%s %s = {0};\n" % (tp, name) + "    %s.full = luaL_checkinteger(L, %d);" % (name, index), 1, False
    if tp.endswith("*"):
        return "{} {} = ({})lua_touserdata(L, {});".format(str(tp), str(name), str(tp), str(index)), 1, False
    #print("miss arg type", tp)
    return "{} {};".format(str(tp), str(name)), 1, True

map_lua_ret = {
    "void" : ["return 0;"],
    "char*" : ["lua_pushstring(L, ret);", "return 1;"],
    "lv_res_t" : ["lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);", "lua_pushinteger(L, ret);", "return 2;"],
    "bool" : ["lua_pushboolean(L, ret);", "return 1;"],
    "lv_fs_res_t" :  ["lua_pushboolean(L, ret == 0 ? 1 : 0);", "lua_pushinteger(L, ret);", "return 2;"],
    "lv_draw_mask_res_t" :  ["lua_pushboolean(L, ret == 0 ? 1 : 0);", "lua_pushinteger(L, ret);", "return 2;"],
    "lv_color_hsv_t" : [ "lua_pushinteger(L, ret.h);",  "lua_pushinteger(L, ret.s);",  "lua_pushinteger(L, ret.v);", "return 3;"],
    "lv_point_t" : [ "lua_pushinteger(L, ret.x);",  "lua_pushinteger(L, ret.y);",  "return 2;"],
}


def gen_lua_ret(tp, f) :
    # 数值类
    if tp in map_lv_ints :
        f.write("    lua_pushinteger(L, ret);\n")
        f.write("    return 1;\n")
    # 配好的匹配
    elif tp in map_lua_ret :
        for line in map_lua_ret[tp] :
            f.write("    ")
            f.write(line)
            f.write("\n")
    # lv_color_t需要特别处理一下
    elif tp == "lv_color_t" :
        f.write("    lua_pushinteger(L, ret.full);\n")
        f.write("    return 1;\n")
    # 返回值是指针的
    elif tp.endswith("*") :
        if tp != "lv_obj_t*":
            miss_ret_types.add(tp)
        f.write("    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);\n")
        f.write("    return 1;\n")
    # 其他的暂不支持
    else :
        miss_ret_types.add(tp)
        f.write("    return 0;\n")

if __name__ == '__main__':
    main()
