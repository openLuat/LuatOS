package com.luatos.toolkit.impl;

import java.util.LinkedList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.nutz.lang.Strings;
import org.nutz.lang.util.NutMap;
import org.nutz.lang.util.Regex;

import com.luatos.toolkit.api.TagParser;

/**
 * 逐行处理输入的标签，类似下面的输入结构
 * 
 * <pre>
 * &#64;module  rtos
 * &#64;summary RTOS底层操作库
 * &#64;version 1.0
 * &#64;date    2020.03.30
 * </pre>
 * 
 * @author zozoh(zozohtnt@gmail.com)
 */
public class NutMapTagParser implements TagParser<NutMap> {

    /**
     * 正则，要能提出两个分组，一个表标签名，一个表标签值
     */
    private String regex;

    /**
     * 标签名在正则中的分组
     */
    private int keyIndex;

    /**
     * 标签值在正则中的分组
     */
    private int valIndex;

    public NutMapTagParser() {
        this("^@(\\w+)\\s+(.+)$", 1, 2);
    }

    public NutMapTagParser(String regex, int keyIndex, int valIndex) {
        this.regex = regex;
        this.keyIndex = keyIndex;
        this.valIndex = valIndex;
    }

    @Override
    public NutMap parse(String input) {
        NutMap map = new NutMap();
        String[] lines = input.split("\r?\n");

        // 获得模式
        Pattern p = Regex.getPattern(regex);

        // 准备开始
        String key = null;
        List<String> val = null;

        for (String line : lines) {
            // 无视空行
            if (Strings.isEmpty(line))
                continue;

            // 是否是一个标签的开始
            Matcher m = p.matcher(line);
            if (m.find()) {
                // 推入旧的
                if (null != key) {
                    map.put(key, Strings.join("\n", val));
                }
                // 开启新的
                key = Strings.trim(m.group(this.keyIndex));
                val = new LinkedList<>();
                val.add(Strings.trim(m.group(this.valIndex)));
            }
            // 加入旧标签
            else if (null != key) {
                val.add(Strings.trim(line));
            }
        }

        // 推入最后一个
        if (null != key) {
            map.put(key, Strings.join("\n", val));
        }

        return map;
    }

}
