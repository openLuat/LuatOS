package com.luatos.toolkit.bean;

import org.nutz.lang.Strings;

import com.luatos.toolkit.Luats;

public class FnParam extends FnReturn {

    private String name;

    public boolean hasName() {
        return !Strings.isBlank(name);
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        if (Strings.isBlank(name)) {
            this.name = null;
        } else {
            this.name = name;
        }
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

    public String toString() {
        String str = toTypeName();
        if (!Strings.isBlank(comment)) {
            str += "/* " + comment + " */";
        }
        return str;
    }

    private String toTypeName() {
        String str = null == name ? "" : name;
        if (!Strings.isBlank(type)) {
            if (type.endsWith("*")) {
                str = type.substring(0, type.length() - 1) + " *" + str;
            } else if (Strings.isBlank(str)) {
                str = type;
            } else {
                str = type + " " + str;
            }
        }
        if (null != this.modifier) {
            return this.modifier.toLowerCase() + " " + str;
        }
        return str;
    }

    public String toSignature(boolean withType) {
        if (withType) {
            if (this.hasType()) {
                return this.toTypeName();
            }
        }
        return this.name;
    }

    public boolean equals(Object o) {
        if (o instanceof FnParam) {
            FnParam fp = (FnParam) o;

            if (!super.equals(fp)) {
                return false;
            }

            if (!Luats.isSame(this.name, fp.name))
                return false;

            return true;
        }
        return false;
    }

}
