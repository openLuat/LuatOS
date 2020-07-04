package org.luatos.toolkit.impl;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.luatos.toolkit.api.FnSignParser;
import org.luatos.toolkit.api.LuDocParser;
import org.luatos.toolkit.bean.FnSign;
import org.luatos.toolkit.bean.LuComment;
import org.luatos.toolkit.bean.LuDocument;
import org.luatos.toolkit.bean.LuHead;
import org.nutz.lang.Lang;
import org.nutz.lang.Strings;
import org.nutz.lang.util.Regex;

public class CLuDocParser implements LuDocParser {

    private LuHeadParser headParser = new LuHeadParser();
    private FnSignParser cFnParser = new CFnSignParser();
    private FnSignParser docxyFnParser = new DoxyFnSignParser();

    @Override
    public LuDocument parse(String input) {
        // 准备
        String[] lines = input.split("\r?\n");

        // 准备归纳的实体列表，元素有两种类型
        // - String - 一个 C 函数的签名定义
        // - LuComment - 声明的注释，可以是 LUA_HEAD/LUA_SIGN/BLOCK/LINES
        List<Object> entities = new ArrayList<>(lines.length / 2);

        // 归纳需要解析的实体
        createEntities(lines, entities);

        // 打印测试
        // Luats.printEntities(entities);

        // 准备要生成的文档
        LuDocument doc = new LuDocument();

        joinEntities(doc, entities);

        return doc;
    }

    private void joinEntities(LuDocument doc, List<Object> entities) {
        // 最后一次生成的 Fn, 以备函数融合(将 c 函数关联至 lua 的函数定义)
        LuComment lastCmt = null;
        FnSign lastFn = null;

        // 循环开始了
        for (Object en : entities) {
            // 处理注释
            if (en instanceof LuComment) {
                LuComment cmt = (LuComment) en;
                // 头部·头部
                if (cmt.isLuaHead()) {
                    LuHead head = headParser.parse(cmt.toString());
                    doc.mergeHead(head);
                    continue;
                }

                // 函数
                if (cmt.isLuaSign()) {
                    // 推入旧的
                    if (lastFn != null) {
                        doc.addFunctions(lastFn);
                    }
                    // 开始新的
                    lastCmt = null;
                    lastFn = docxyFnParser.parse(cmt.toString());
                }
                // 普通注释
                else {
                    lastCmt = cmt;
                }
                // 无论如何，后面的逻辑就不需要了
                continue;
            }
            // 处理C方法
            FnSign fn = null;
            if (en instanceof String) {
                fn = cFnParser.parse(en.toString());
            }
            // 呃，什么鬼？
            else {
                throw Lang.impossible();
            }

            // 看看有木有可能融合
            if (lastFn != null) {
                // 当前方式是个 lua 的 C 签名
                if (fn.isStatic()
                    && fn.isReturnMatch(0, "int")
                    && fn.getParamsCount() == 1
                    && fn.isParamMatch(0, "lua_State*", "L")) {
                    // 前序方法名称与当前方法匹配
                    if (fn.isNameEndsWith(lastFn.getName().replace('.', '_'))) {
                        // 融合吧
                        lastFn.setRefer(fn);
                        doc.addFunctions(lastFn);
                        lastFn = null;
                        lastCmt = null;
                        continue;
                    }
                }
            }

            // 融合注释
            if (null != lastCmt) {
                fn.setSummary(lastCmt.toString());
                lastCmt = null;
            }

            // 记入文档
            doc.addFunctions(fn);

            // 清理之前
            lastFn = null;
            lastCmt = null;
        }

        // 最后一个函数
        if (lastFn != null) {
            doc.addFunctions(lastFn);
        }
    }

    private void createEntities(String[] lines, List<Object> entities) {
        // 当前注释
        LuComment cmt = null;
        Matcher m;

        // 准备注释行的判断
        Pattern P_CMT = Regex.getPattern("^\\s*(/[/*]).*$");
        Pattern P_FNC = Regex.getPattern("^\\s*static [\\w\\d ]+\\(.*\\).*$");

        // 逐行循环
        for (String line : lines) {
            // 嗯单行注释行
            // 嗯多行注释
            m = P_CMT.matcher(line);
            if (m.find()) {
                if (null == cmt) {
                    cmt = new LuComment();
                }
                if (!cmt.appendLine(line)) {
                    entities.add(cmt);
                    cmt = null;
                }
                continue;
            }
            // 嗯，看看是不是可以加入注释
            if (null != cmt) {
                if (cmt.appendLine(line)) {
                    continue;
                }
                if (!cmt.isEmpty() && cmt.getSpace() == 0) {
                    // 看看是不是水平线
                    String str = cmt.toString();
                    String lin = Strings.dup(str.charAt(0), str.length());
                    if (!str.equals(lin)) {
                        entities.add(cmt);
                    }
                }
                cmt = null;
            }

            // 嗯 静态函数
            m = P_FNC.matcher(line);
            if (m.find()) {
                entities.add(line.trim());
            }

            // 嗯，无视
        }
    }
}
