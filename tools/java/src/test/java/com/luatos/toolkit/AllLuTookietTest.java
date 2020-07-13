package com.luatos.toolkit;

import org.junit.runner.RunWith;
import org.junit.runners.Suite;

import com.luatos.toolkit.bean.LuAllBeanTest;
import com.luatos.toolkit.impl.LuAllParserTest;

@RunWith(Suite.class)
@Suite.SuiteClasses({LuAllBeanTest.class, LuAllParserTest.class})
public class AllLuTookietTest {}
