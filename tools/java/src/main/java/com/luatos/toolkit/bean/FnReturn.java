package com.luatos.toolkit.bean;

import org.nutz.lang.Strings;

import com.luatos.toolkit.Luats;

public class FnReturn {

    protected String type;

    protected String comment;

    protected String modifier;

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

    public FnReturn() {}

    public FnReturn(String type) {
        this.setType(type);
    }

    public FnReturn(String type, String comment) {
        this.comment = comment;
        this.setType(type);
    }

    public boolean isType(String type) {
        return Luats.isSame(this.type, type);
    }

    public boolean hasType() {
        return !Strings.isBlank(type);
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        if (null != type) {
            this.type = type.replace(" ", "");
        }
    }

    public boolean hasComment() {
        return !Strings.isBlank(comment);
    }

    public String getComment() {
        return comment;
    }

    public void setComment(String comment) {
        this.comment = comment;
    }

    public String toString() {
        String str = type;
        if (!Strings.isBlank(comment)) {
            str += "/* " + comment + " */";
        }
        if (null != this.modifier) {
            return this.modifier.toString().toLowerCase() + " " + str;
        }
        return str;
    }

    public String toSignature() {
        String str = this.hasType() ? this.type : "";
        if (null != this.modifier) {
            return this.modifier.toLowerCase() + " " + str;
        }
        return str;
    }

    public boolean equals(Object o) {
        if (o instanceof FnReturn) {
            FnReturn fr = (FnReturn) o;

            if (!Luats.isSame(this.modifier, fr.modifier))
                return false;

            if (!Luats.isSame(this.type, fr.type))
                return false;

            if (!Luats.isSame(this.comment, fr.comment))
                return false;

            return true;
        }
        return false;
    }

}
