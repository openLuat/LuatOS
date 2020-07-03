package org.luatos.toolkit.bean;

import java.util.LinkedList;
import java.util.List;
import java.util.regex.Matcher;

import org.nutz.lang.Strings;
import org.nutz.lang.util.Regex;

public class LuDocComment {

    private LuCommentType type;

    private List<String> lines;

    public LuDocComment() {}

    public LuDocComment(String block) {
        this.parse(block);
    }

    public void clear() {
        this.type = null;
        this.lines = null;
    }

    public boolean isLuaSign() {
        return LuCommentType.LUA_SIGN == this.type;
    }

    public boolean isText() {
        return LuCommentType.TEXT == this.type;
    }

    public boolean isDisabled() {
        return LuCommentType.DISABLED == this.type;
    }

    public boolean isEmpty() {
        return null == lines || lines.isEmpty();
    }

    public LuCommentType getType() {
        return type;
    }

    public void setType(LuCommentType type) {
        this.type = type;
    }

    public List<String> getLines() {
        return lines;
    }

    public void setLines(List<String> lines) {
        this.lines = lines;
    }

    public void appendLine(String line) {
        if (null == lines) {
            lines = new LinkedList<>();
        }
        this.lines.add(line);
    }

    private static final String REG_BEGIN = "^\\s*(/[*]|[*]{1,2} ) *(.*)$";
    private static final String REG_END = "^(.*) *([*]/)\\s*$";

    public void parse(String block) {
        String[] ss = block.split("\r?\n");
        // 有可能是多重
        if (ss.length >= 2) {
            // 或者是多行或者是 Lua 的 doxygen 注释
            if (ss[0].startsWith("/*") && ss[ss.length - 1].endsWith("*/")) {
                LuCommentType type = null;
                int lastI = ss.length - 1;
                for (int i = 0; i <= lastI; i++) {
                    String s = ss[i];
                    String str = null;
                    Matcher m = Regex.getPattern(REG_BEGIN).matcher(s);
                    // 可能是普通注释第一行
                    // -> /*
                    // -> **
                    // -> *
                    if (m.find()) {
                        str = m.group(2);
                    }
                    // 看看是否是结尾
                    else {
                        m = Regex.getPattern(REG_END).matcher(s);
                        if (m.find()) {
                            str = m.group(1);
                        }
                        // 那么就是普通行咯
                        else {
                            str = s;
                        }
                    }

                    // 计入（如果已经开始计入注释行了，那么空行也加进来，当然最后一行除外
                    if (!Strings.isBlank(str) || (!this.isEmpty() && i < lastI)) {
                        this.appendLine(str);
                        // 如果声明了 docxygen 的注释，标识一下类型
                        if (null == type && str.startsWith("@function")) {
                            type = LuCommentType.LUA_SIGN;
                        }
                    }
                }

                // 最后设置一下类型
                if (null == type) {
                    type = LuCommentType.TEXT;
                }
                this.setType(type);

                return;
            }
        }
        // 看看是不是单行注释
        for (String s : ss) {
            if (s.startsWith("//")) {
                this.appendLine(s.substring(2).trim());
            }
        }
        this.setType(LuCommentType.TEXT);
    }

    public String toString() {
        if (this.isEmpty()) {
            return "";
        }
        return Strings.join(System.lineSeparator(), lines);
    }

}
