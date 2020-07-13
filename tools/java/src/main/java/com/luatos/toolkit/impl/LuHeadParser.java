package com.luatos.toolkit.impl;

import org.nutz.lang.Lang;
import org.nutz.lang.util.NutMap;

import com.luatos.toolkit.api.TagParser;
import com.luatos.toolkit.bean.LuHead;

public class LuHeadParser implements TagParser<LuHead> {

    private NutMapTagParser parser;

    public LuHeadParser() {
        this.parser = new NutMapTagParser();
    }

    @Override
    public LuHead parse(String input) {
        NutMap map = parser.parse(input);
        return Lang.map2Object(map, LuHead.class);
    }

}
