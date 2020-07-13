package com.luatos.toolkit.bean;

import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;

import org.nutz.lang.Strings;

import com.luatos.toolkit.Luats;

public class FnSign {

    /**
     * 原始的输入
     */
    private String rawText;

    private String summary;

    private FnLang lang;

    private String modifier;

    private String name;

    private List<FnReturn> returns;

    private List<FnParam> params;

    private List<FnExample> examples;

    private FnSign refer;

    public String toString() {
        String str = "";
        if (null != summary) {
            str += "/*\n" + summary + "\n*/\n";
        }
        if (null != modifier) {
            str += this.modifier.toString().toLowerCase() + " ";
        }

        String pmStr = "";
        if (null != params) {
            List<String> pms = new ArrayList<>(params.size());
            for (FnParam pm : params) {
                pms.add(pm.toString());
            }
            pmStr = Strings.join(", ", pms);
        }

        String res = "";
        if (null != returns) {
            List<String> reList = new ArrayList<>(this.returns.size());
            for (FnReturn re : returns) {
                reList.add(re.getType());
            }
            res = Strings.join(",", reList);
        }

        str += String.format("%s %s(%s)", res, name, pmStr);

        if (!Strings.isBlank(rawText)) {
            str += "\n-----------\nraw:\n" + rawText;
        }

        return str;
    }

    public String toSignature() {
        String str = "";
        if (null != modifier) {
            str += this.modifier.toString().toLowerCase() + " ";
        }

        String pmStr = "";
        if (null != params) {
            List<String> pms = new ArrayList<>(params.size());
            for (FnParam pm : params) {
                pms.add(pm.toSignature(this.isLangC()));
            }
            pmStr = Strings.join(", ", pms);
        }

        String res = "";
        if (null != returns && this.isLangC()) {
            List<String> reList = new ArrayList<>(this.returns.size());
            for (FnReturn re : returns) {
                reList.add(re.toSignature());
            }
            res = Strings.join(",", reList);
            if (!res.endsWith("*")) {
                res += " ";
            }
        }

        str += String.format("%s%s(%s)", res, name, pmStr);

        return str;
    }

    public boolean equals(Object o) {
        if (o instanceof FnSign) {
            FnSign fn = (FnSign) o;
            return isSame(fn, true);
        }
        return false;
    }

    public boolean isSame(FnSign fn, boolean ignoreRawText) {
        if (!ignoreRawText) {
            if (!Luats.isSame(this.rawText, fn.rawText)) {
                return false;
            }
        }
        if (!Luats.isSame(this.lang, fn.lang))
            return false;

        if (!Luats.isSame(this.modifier, fn.modifier))
            return false;

        if (!Luats.isSame(this.name, fn.name))
            return false;

        if (!Luats.isSameList(this.returns, fn.returns))
            return false;

        if (!Luats.isSameList(this.params, fn.params))
            return false;

        if (!Luats.isSameList(this.examples, fn.examples))
            return false;

        return true;
    }

    public String getRawText() {
        return rawText;
    }

    public void setRawText(String rawText) {
        this.rawText = rawText;
    }

    public boolean hasSummary() {
        return !Strings.isBlank(summary);
    }

    public String getSummary() {
        return summary;
    }

    public void setSummary(String comment) {
        this.summary = comment;
    }

    public boolean isLangC() {
        return FnLang.C == this.lang;
    }

    public boolean isLangLua() {
        return FnLang.LUA == this.lang;
    }

    public FnLang getLang() {
        return lang;
    }

    public String getLangName() {
        return null == lang ? "" : lang.toString().toLowerCase();
    }

    public void setLang(FnLang type) {
        this.lang = type;
    }

    public boolean isLocal() {
        return this.isModifier("local");
    }

    public boolean isStatic() {
        return this.isModifier("static");
    }

    public boolean isModifier(String mod) {
        if (null != this.modifier) {
            return this.modifier.contains(mod);
        }
        return false;
    }

    public String getModifier() {
        return modifier;
    }

    public void setModifier(String mod) {
        if (!Strings.isBlank(mod)) {
            this.modifier = Strings.trim(mod);
        } else {
            this.modifier = null;
        }
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public boolean isName(String name) {
        return Luats.isSame(this.name, name);
    }

    public boolean isNameEndsWith(String name) {
        if (null != this.name) {
            return this.name.endsWith(name);
        }
        return false;
    }

    public boolean hasReturns() {
        return null != this.returns && !this.returns.isEmpty();
    }

    public List<FnReturn> getReturns() {
        return returns;
    }

    public void setReturns(List<FnReturn> returns) {
        this.returns = returns;
    }

    public void addReturn(FnReturn fr) {
        if (null == this.returns) {
            this.returns = new LinkedList<>();
        }
        this.returns.add(fr);
    }

    public int getReturnCount() {
        if (null != this.returns) {
            return this.returns.size();
        }
        return 0;
    }

    public boolean isReturnMatch(int index, String type) {
        if (index >= 0 && index < this.getReturnCount()) {
            FnReturn fr = this.returns.get(index);
            return fr.isType(type);
        }
        return false;
    }

    public boolean hasParams() {
        return null != this.params && !this.params.isEmpty();
    }

    public List<FnParam> getParams() {
        return params;
    }

    public void setParams(List<FnParam> params) {
        this.params = params;
    }

    public void addParam(FnParam param) {
        if (null == this.params) {
            this.params = new LinkedList<>();
        }
        this.params.add(param);
    }

    public int getParamsCount() {
        if (null != this.params) {
            return this.params.size();
        }
        return 0;
    }

    public boolean isParamMatch(int index, String type, String name) {
        if (index >= 0 && index < this.getParamsCount()) {
            FnParam fp = this.params.get(index);
            if (!fp.isType(type))
                return false;
            if (!fp.isName(name))
                return false;

            return true;
        }
        return false;
    }

    public boolean hasExamples() {
        return null != this.examples && !this.examples.isEmpty();
    }

    public List<FnExample> getExamples() {
        return examples;
    }

    public void setExamples(List<FnExample> examples) {
        this.examples = examples;
    }

    public void addExample(FnExample example) {
        if (null == this.examples) {
            this.examples = new LinkedList<>();
        }
        this.examples.add(example);
    }

    public boolean hasRefer() {
        return null != this.refer;
    }

    public FnSign getRefer() {
        return refer;
    }

    public void setRefer(FnSign refer) {
        this.refer = refer;
    }

}
