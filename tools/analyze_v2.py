#!/usr/bin/env python3
import os
import re
import sys
from glob import glob

results_dir = sys.argv[1] if len(sys.argv) > 1 else sorted(glob('pc_test_results_*'), reverse=True)[0]
runlog = sys.argv[2] if len(sys.argv) > 2 else 'pc_test_run_v2.log'

pass_log = []
fail_log = []
missing_log = []
crash_log = []
timeout_log = []
unknown_log = []
reasons = []

def log_name_to_file(name):
    return os.path.join(results_dir, name.replace('/', '__').replace('\\', '__') + '.log')

def classify_log(name):
    path = log_name_to_file(name)
    if not os.path.exists(path):
        return 'UNKNOWN', 'log file not found'
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        text = f.read()
    if "module '" in text and "not found" in text:
        m = re.search(r"module '([^']+)' not found", text)
        detail = m.group(0) if m else 'module not found'
        return 'MISSING', detail
    if '### OVERALL_PASS ###' in text:
        return 'PASS', ''
    if re.search(r'^I/user\.[^ ]+ PASS$', text, re.M):
        return 'PASS', ''
    if re.search(r'Total: \d+ passed, 0 failed', text):
        return 'PASS', ''
    if '### OVERALL_FAIL ###' in text:
        return 'FAIL', 'OVERALL_FAIL'
    if re.search(r'Total: \d+ passed, [1-9]\d* failed', text):
        m = re.search(r'Failed testcases: (.+)', text)
        detail = m.group(1) if m else 'some tests failed'
        return 'FAIL', detail
    return None, None

name = None
status = None
exitcode = None

with open(runlog, 'r', encoding='utf-8', errors='ignore') as f:
    for line in f:
        line = line.rstrip('\n').rstrip('\r')
        m = re.match(r'^\[\d+/\d+\] Running (.+)\.\.\.\s*$', line)
        if m:
            name = m.group(1).strip()
            status = None
            exitcode = None
            continue
        m = re.match(r'^(PASS|FAIL|TIMEOUT|CRASH|UNKNOWN)\b(?!:)', line)
        if m and name:
            status = m.group(1)
            me = re.search(r'exit=(\d+)', line)
            exitcode = me.group(1) if me else None

            real_status, detail = classify_log(name)
            if real_status is None:
                real_status = status

            entry = name
            if exitcode:
                entry += f' (exit={exitcode})'
            if detail:
                entry += f' [{detail}]'

            item = {'name': name, 'entry': entry}
            if real_status == 'PASS':
                pass_log.append(item)
            elif real_status == 'FAIL':
                fail_log.append(item)
            elif real_status == 'MISSING':
                missing_log.append(item)
            elif real_status == 'CRASH':
                crash_log.append(item)
            elif real_status == 'TIMEOUT':
                timeout_log.append(item)
            else:
                unknown_log.append(item)

# Collect reasons
def tail(path, n=10):
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    return ''.join(lines[-n:])

reasons.append('===== Detailed Reasons =====\n')

reasons.append('\n--- CRASH (segfault exit=139) ---\n')
for item in crash_log:
    name, entry = item['name'], item['entry']
    ec = re.search(r'exit=(\d+)', entry)
    if ec and ec.group(1) == '139':
        reasons.append(f'{name}:\n')
        reasons.append(tail(log_name_to_file(name), 8).rstrip() + '\n\n')

reasons.append('\n--- OTHER CRASH/ABNORMAL EXIT (exit!=139) ---\n')
for item in crash_log:
    name, entry = item['name'], item['entry']
    ec = re.search(r'exit=(\d+)', entry)
    if ec and ec.group(1) != '139':
        reasons.append(f'{entry}:\n')
        reasons.append(tail(log_name_to_file(name), 15).rstrip() + '\n\n')

reasons.append('\n--- TIMEOUT ---\n')
for item in timeout_log:
    reasons.append(item['entry'] + '\n')

reasons.append('\n--- MISSING_DEP ---\n')
for item in missing_log:
    reasons.append(item['entry'] + '\n')

reasons.append('\n--- FAIL (assertion/test failure) ---\n')
for item in fail_log:
    name, entry = item['name'], item['entry']
    reasons.append(f'{entry}:\n')
    path = log_name_to_file(name)
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    # find last failed test or error lines
    selected = []
    for ln in reversed(lines):
        if '✗' in ln or 'E/main' in ln or 'failed:' in ln or 'assert' in ln:
            selected.append(ln.rstrip())
        if len(selected) >= 4:
            break
    for ln in reversed(selected):
        reasons.append('  ' + ln + '\n')
    reasons.append('\n')

reasons.append('\n--- UNKNOWN (needs manual check) ---\n')
for item in unknown_log:
    name, entry = item['name'], item['entry']
    reasons.append(f'{entry}:\n')
    reasons.append(tail(log_name_to_file(name), 8).rstrip() + '\n\n')

reasons_text = ''.join(reasons)
with open(os.path.join(results_dir, 'reasons_v2.txt'), 'w', encoding='utf-8') as f:
    f.write(reasons_text)
print(reasons_text)

summary = f"""
===== Refined Summary V2 =====
Total: {len(pass_log) + len(fail_log) + len(missing_log) + len(crash_log) + len(timeout_log) + len(unknown_log)}
PASS: {len(pass_log)}
FAIL: {len(fail_log)}
MISSING_DEP: {len(missing_log)}
CRASH (segfault exit=139): {sum(1 for item in crash_log if 'exit=139' in item['entry'])}
CRASH/ABNORMAL (other exit): {sum(1 for item in crash_log if 'exit=139' not in item['entry'])}
TIMEOUT: {len(timeout_log)}
UNKNOWN: {len(unknown_log)}
"""
print(summary)
with open(os.path.join(results_dir, 'summary_v2.txt'), 'w', encoding='utf-8') as f:
    f.write(summary)

# Also write list files
for fname, data in [
    ('pass_v2.txt', pass_log),
    ('fail_v2.txt', fail_log),
    ('missing_v2.txt', missing_log),
    ('crash_v2.txt', crash_log),
    ('timeout_v2.txt', timeout_log),
    ('unknown_v2.txt', unknown_log),
]:
    with open(os.path.join(results_dir, fname), 'w', encoding='utf-8') as f:
        f.write('\n'.join(item['entry'] for item in data) + '\n')
