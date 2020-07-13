package com.luatos.toolkit.bean;

import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;

import org.nutz.lang.Lang;
import org.nutz.lang.Strings;

import com.luatos.toolkit.LuatRenderingSetup;
import com.luatos.toolkit.Luats;

public class LuDocument {

    private LuHead head;

    private List<FnSign> functions;

    public boolean hasHead() {
        return null != head;
    }

    public LuHead getHead() {
        return head;
    }

    public void setHead(LuHead title) {
        this.head = title;
    }

    public void mergeHead(LuHead head) {
        if (null == this.head) {
            this.head = head;
        } else {
            this.head.mergeWith(head);
        }
    }

    public String getTitle() {
        if (null != head)
            return head.getTitle();
        return null;
    }
    
    public String getDisplayTitle() {
        if (null != head)
            return head.getDisplayTitle();
        return null;
    }
    
    public String getDisplaySummary() {
        if (null != head)
            return Strings.sBlank(head.getSummary(), head.getDisplayTitle());
        return null;
    }

    public void setDefaultTitle(String title) {
        if (null == head) {
            head = new LuHead();
        }
        if (!head.hasTitle()) {
            head.setTitle(title);
        }
    }

    public String getPath() {
        if (null != head)
            return head.getPath();
        return null;
    }

    public void setPath(String path) {
        if (null == head) {
            head = new LuHead();
        }
        head.setPath(path);
    }

    public boolean hasFunctions() {
        return null != this.functions && !this.functions.isEmpty();
    }

    public List<FnSign> getFunctions() {
        return functions;
    }

    public List<FnSign> fetchFunctions(LuatRenderingSetup setup) {
        // 木有函数
        if (!this.hasFunctions()) {
            return new LinkedList<FnSign>();
        }
        // 木有约束
        if (null == setup || (!setup.isDropEmptyComment() && !setup.hasLang())) {
            return this.functions;
        }

        List<FnSign> list = new ArrayList<>(this.functions.size());

        // 首先整理一下要过滤的语言
        FnLang[] langs = setup.getLangEnum();

        // 逐个判断一下
        for (FnSign fn : this.functions) {
            // 没有匹配语言
            if (langs.length > 0) {
                if (!Lang.contains(langs, fn.getLang())) {
                    continue;
                }
            }
            // 没有匹配注释
            if (setup.isDropEmptyComment()) {
                if (Strings.isBlank(fn.getSummary())) {
                    continue;
                }
            }
            // 嗯，这下可以加入
            list.add(fn);
        }
        return list;
    }

    public void setFunctions(List<FnSign> functions) {
        this.functions = functions;
    }

    public void addFunctions(FnSign func) {
        if (null == this.functions) {
            this.functions = new LinkedList<>();
        }
        this.functions.add(func);
    }

    public boolean equals(Object o) {
        if (o instanceof LuDocument) {
            LuDocument doc = (LuDocument) o;
            if (!Luats.isSame(head, doc.head))
                return false;
            if (!Luats.isSameList(functions, doc.functions))
                return false;

            return true;
        }
        return false;
    }

}
