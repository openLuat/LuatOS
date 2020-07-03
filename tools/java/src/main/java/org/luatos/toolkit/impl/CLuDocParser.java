package org.luatos.toolkit.impl;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.luatos.toolkit.api.LuDocParser;
import org.luatos.toolkit.bean.LuComment;
import org.luatos.toolkit.bean.LuDocument;
import org.nutz.lang.Strings;
import org.nutz.lang.util.Regex;

public class CLuDocParser implements LuDocParser {

    @Override
    public LuDocument parse(String input) {
        String[] lines = input.split("\r?\n");

        List<Object> entities = new ArrayList<>(lines.length / 2);

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

        // 测试打印一下
        String hr = Strings.dup('-', 40);
        for (Object en : entities) {
            System.out.println(hr);
            System.out.println(en.toString());
        }

        return null;
    }

}
