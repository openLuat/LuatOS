#!/usr/bin/env python3
# AI-MANAGED: true
# SPDX-License-Identifier: MIT
"""真实Router认证/拒绝、认证后的二进制收发及关闭重连；只用本机17447。"""
import argparse, hashlib, json, os, secrets, signal, socket, subprocess, tempfile, time
from pathlib import Path

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def wait_listen(proc):
    until=time.monotonic()+5
    while time.monotonic()<until and proc.poll() is None:
        try:
            with socket.create_connection(('127.0.0.1',17447),.1):return
        except OSError:time.sleep(.04)
    raise RuntimeError('router did not listen')
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--build-dir',type=Path,required=True);ap.add_argument('--router',type=Path,required=True);ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
    here=Path(__file__).resolve().parent;host=a.build_dir/'zenoh_host_test';peer=a.build_dir/'zenoh_peer'
    manifest=a.build_dir/'build_inputs.json'; frozen=json.loads(manifest.read_text())
    for path,digest in frozen['inputs'].items():
        if sha(Path(path))!=digest:raise RuntimeError('source drift: '+path)
    for binary in (host,peer):
        if sha(binary)!=frozen['binaries'][binary.name]:raise RuntimeError('binary drift: '+str(binary))
    version=subprocess.check_output([str(a.router),'--version'],text=True).strip()
    if not version.startswith('zenohd v1.9.0 '):raise RuntimeError('fixed Router 1.9.0 required')
    os.umask(0o077);a.out.mkdir(parents=True,exist_ok=False)
    result={'build_manifest_sha256':sha(manifest),'scope':'host Lua5.3/64 real SDK/authenticated Router; not target firmware','router_version':version,'sha256':{str(p):sha(p) for p in [host,peer,a.router,here/'host_auth_test.lua',Path(__file__).resolve()]},'cases':[]}
    for name in ['anonymous','correct','maximum','wrong_user','wrong_password','missing_credentials','missing_challenge']:
        case=a.out/name;case.mkdir();record={'case':name};procs=[];files=[]
        try:
            with socket.socket() as probe:
                probe.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);probe.bind(('127.0.0.1',17447))
            with tempfile.TemporaryDirectory(prefix='zenoh-auth-test-') as temp:
                private=Path(temp);user='test_'+secrets.token_hex(8);password=secrets.token_hex(24)
                if name=='maximum':user='u'*128;password='p'*128
                dictionary=private/'users';dictionary.write_text(user+':'+password+'\n')
                cfg={'mode':'router','listen':{'endpoints':['tcp/127.0.0.1:17447']},'connect':{'endpoints':[]},'plugins':{},'scouting':{'multicast':{'enabled':False},'gossip':{'enabled':False}}}
                if name not in ['anonymous','missing_challenge']:cfg['transport']={'auth':{'usrpwd':{'dictionary_file':str(dictionary)}}}
                config=private/'router.json';config.write_text(json.dumps(cfg))
                env=dict(os.environ,RUST_LOG='warn',ASAN_OPTIONS='detect_leaks=0:halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
                def spawn(label,args,environment):
                    f=(case/(label+'.log')).open('xb');files.append(f)
                    p=subprocess.Popen(list(map(str,args)),stdout=f,stderr=subprocess.STDOUT,env=environment,start_new_session=True);procs.append((label,p));return p
                router=spawn('router',[a.router,'-c',config,'--adminspace-permissions','none'],env);wait_listen(router)
                endpoint='tcp/127.0.0.1:17447';prefix='test/auth/'+name
                positive=name in ['anonymous','correct','maximum']
                if positive:
                    pe=env.copy()
                    if name!='anonymous':pe.update(ZENOH_TEST_USER=user,ZENOH_TEST_PASSWORD=password)
                    other=spawn('peer',[peer,endpoint,prefix],pe)
                    until=time.monotonic()+5
                    while 'READY' not in (case/'peer.log').read_text():
                        if other.poll() is not None or time.monotonic()>until:raise RuntimeError('peer did not open')
                        time.sleep(.04)
                ce=dict(env,ZENOH_AUTH_CASE=name,ZENOH_TEST_USER=user,ZENOH_TEST_PASSWORD=password)
                if name=='wrong_user':ce['ZENOH_TEST_USER']='unknown_'+user
                if name=='wrong_password':ce['ZENOH_TEST_PASSWORD']='wrong_'+password
                client=spawn('host',[host,here/'host_auth_test.lua',endpoint,prefix],ce)
                record['host_exit']=client.wait(timeout=60)
                record['pass_marker']='AUTH_CASE_PASS '+name in (case/'host.log').read_text()
                if positive:record['peer_exit']=other.wait(timeout=6)
        except Exception as exc:record['error']=type(exc).__name__+': '+str(exc)
        finally:
            record['cleanup']=[]
            for label,proc in reversed(procs):
                stopped=proc.poll() is None;forced=False
                if stopped:
                    os.killpg(proc.pid,signal.SIGTERM)
                    try:proc.wait(timeout=3)
                    except subprocess.TimeoutExpired:forced=True;os.killpg(proc.pid,signal.SIGKILL);proc.wait(timeout=3)
                record['cleanup'].append({'process':label,'exit':proc.returncode,'owner_terminated':stopped,'forced':forced})
            for f in files:f.close()
        record['sanitizer_error']=any('AddressSanitizer' in p.read_text() or 'runtime error:' in p.read_text() for p in case.glob('*.log'))
        record['passed']=not record.get('error') and record.get('host_exit')==0 and record.get('pass_marker') and record.get('peer_exit',0)==0 and not record['sanitizer_error'] and not any(x['forced'] for x in record['cleanup'])
        result['cases'].append(record);(case/'actual.json').write_text(json.dumps(record,indent=2)+'\n')
        print(name,record['passed'],flush=True)
        if not record['passed']:break
    result['passed']=len(result['cases'])==7 and all(c['passed'] for c in result['cases'])
    (a.out/'actual.json').write_text(json.dumps(result,indent=2)+'\n');return 0 if result['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
