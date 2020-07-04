package org.luatos.toolkit.impl;

import org.luatos.toolkit.api.TagParser;
import org.luatos.toolkit.bean.LuHead;
import org.nutz.lang.Lang;
import org.nutz.lang.util.NutMap;

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
