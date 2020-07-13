package com.luatos.toolkit;

import com.luatos.toolkit.bean.FnLang;

public class LuatRenderingSetup {

    /**
     * 仅输入下面指定的 API<br>
     * 支持, "C" 和 "LUA"
     * <p>
     * !! 注意，需要全部大写 默认的，都会输出（即，只要解析器收集到的函数签名，都会输出为文档）
     */
    private String[] lang;
    /**
     * 这个开关如果设置为 true，所有空白的函数签名都会被无视<br>
     * 默认 false
     */
    private boolean dropEmptyComment;

    public LuatRenderingSetup() {
        super();
    }

    public boolean hasLang() {
        return null != lang && lang.length > 0;
    }

    public String[] getLang() {
        return lang;
    }

    public FnLang[] getLangEnum() {
        if (!this.hasLang()) {
            return new FnLang[0];
        }
        FnLang[] langs = new FnLang[this.lang.length];
        for (int i = 0; i < this.lang.length; i++) {
            String la = this.lang[i].toUpperCase();
            FnLang l2 = FnLang.valueOf(la);
            langs[i] = l2;
        }
        return langs;
    }

    public void setLang(String[] lang) {
        this.lang = lang;
    }

    public boolean isDropEmptyComment() {
        return dropEmptyComment;
    }

    public void setDropEmptyComment(boolean dropEmptyComment) {
        this.dropEmptyComment = dropEmptyComment;
    }

}