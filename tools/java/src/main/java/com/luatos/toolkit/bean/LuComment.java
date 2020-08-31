package com.luatos.toolkit.bean;

import java.util.LinkedList;
import java.util.List;
import java.util.regex.Matcher;

import org.nutz.lang.Strings;
import org.nutz.lang.util.Regex;

public class LuComment {

    private boolean closed;

    private int space;

    private LuCmtType type;

    private List<String> lines;

    public LuComment() {}

    public LuComment(String block) {
        this.parse(block);
    }

    public void clear() {
        this.type = null;
        this.lines = null;
    }

    public boolean isLuaHead() {
        return LuCmtType.LUA_HEAD == this.type;
    }

    public boolean isLuaSign() {
        return LuCmtType.LUA_SIGN == this.type;
    }

    public boolean isBlock() {
        return LuCmtType.BLOCK == this.type;
    }

    public boolean isLines() {
        return LuCmtType.LINES == this.type;
    }

    public boolean isEmpty() {
        return null == lines || lines.isEmpty();
    }

    public int getSpace() {
        return space;
    }

    public void setSpace(int space) {
        this.space = space;
    }

    public LuCmtType getType() {
        return type;
    }

    public void setType(LuCmtType type) {
        this.type = type;
    }

    public boolean isClosed() {
        return closed;
    }

    public void setClosed(boolean closed) {
        this.closed = closed;
    }

    public List<String> getLines() {
        return lines;
    }

    public void setLines(List<String> lines) {
        this.lines = lines;
    }

    private static final String BLK_BEGIN = "^(\\s*)(/[*][*]*) ?(.*)$";
    private static final String BLK_LINE = "^(\\s*[*]\\s)(.*)$";
    private static final String BLK_END = "^(.*) *([*]/)\\s*$";
    private static final String LIN_CMT = "^(\\s*)(// ?)(.*)$";

    /**
     * @param line
     * @return LuCmtAppend
     */
    public LuCmtAppend appendLine(String line) {
        if (null == lines) {
            lines = new LinkedList<>();
        }

        // 已经关闭了
        if (this.closed) {
            return LuCmtAppend.REJECT;
        }

        Matcher m;

        // 单行注释
        m = Regex.getPattern(LIN_CMT).matcher(line);
        if (m.find()) {
            if (null == this.type) {
                this.type = LuCmtType.LINES;
                this.space = m.group(1).length();
            }
            // 必须自己也是单行注释
            else if (!this.isLines()) {
                return LuCmtAppend.REJECT;
            }

            // 成功加入
            lines.add(m.group(3));
            return LuCmtAppend.ACCEPT;
        }

        // 多行注释:
        // -> /*
        // -> **
        // -> *
        m = Regex.getPattern(BLK_BEGIN).matcher(line);
        if (m.find()) {
            if (null == this.type) {
                this.type = LuCmtType.BLOCK;
                this.space = m.group(1).length();
            }
            // 必须自己也是块注释
            else if (!this.isBlock()) {
                return LuCmtAppend.REJECT;
            }
            // 成功加入
            String str = m.group(3);
            // 计入（如果已经开始计入注释行了，那么空行也加进来，当然最后一行除外
            if (!Strings.isBlank(str) || !this.isEmpty()) {
                lines.add(str);
            }
            return LuCmtAppend.ACCEPT;
        }

        // 多行注释: 结尾
        m = Regex.getPattern(BLK_END).matcher(line);
        if (m.find()) {
            if (this.isBlock()) {
                String str = m.group(1);
                if (!Strings.isBlank(str))
                    lines.add(str);
            }
            this.closed = true;
            return LuCmtAppend.CLOSED;
        }

        // 其他的普通行，只有多行注释才能接受
        if (this.isBlock() || this.isLuaSign() || this.isLuaHead()) {
            // 多行注释的话，试图去掉前面的星星
            m = Regex.getPattern(BLK_LINE).matcher(line);
            if (m.find()) {
                line = m.group(2).trim();
            }
            // 记入行
            lines.add(line);
            // 如果这个行是一个函数声明，那么切换特殊类型
            if (this.isBlock()) {
                if (line.startsWith("@function")) {
                    this.setType(LuCmtType.LUA_SIGN);
                } else if (line.startsWith("@api")) {
                    this.setType(LuCmtType.LUA_SIGN);
                } else if (line.startsWith("@module")) {
                    this.setType(LuCmtType.LUA_HEAD);
                }
            }
            return LuCmtAppend.ACCEPT;
        }

        return LuCmtAppend.REJECT;
    }

    public void parse(String block) {
        String[] ss = block.split("\r?\n");
        for (String s : ss) {
            if (LuCmtAppend.ACCEPT != this.appendLine(s)) {
                return;
            }
        }
    }

    public String toString() {
        if (this.isEmpty()) {
            return "";
        }
        return Strings.join(System.lineSeparator(), lines);
    }

}
