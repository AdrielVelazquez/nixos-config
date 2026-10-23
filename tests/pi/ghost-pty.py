"""Real Pi PTY, an independent visual owner in both orders, no inference calls."""
import codecs
import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
import pyte

binary, entry, owner, word_list, output = sys.argv[1:]
vocabulary = [line.split('\t')[0] for line in Path(word_list).read_text(encoding='utf-8').splitlines()]
assert 'configuration' in vocabulary and 'kubectl' in vocabulary, 'vocabulary fixture must contain the cold completions'
out = Path(output); out.mkdir(parents=True, exist_ok=True)
requests = []
class Provider(BaseHTTPRequestHandler):
    def log_message(self, *_args): pass
    def do_POST(self):
        requests.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
        self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.end_headers()
        for delta, reason in [({'role':'assistant','content':'HEADLESS_OK'}, None), ({}, 'stop')]:
            chunk = {'id':'ghost-test','object':'chat.completion.chunk','created':1,'model':'unit',
                     'choices':[{'index':0,'delta':delta,'finish_reason':reason}]}
            self.wfile.write(('data: '+json.dumps(chunk)+'\n\n').encode())
        self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
server = ThreadingHTTPServer(('127.0.0.1',0), Provider)
thread = threading.Thread(target=server.serve_forever,daemon=True); thread.start()

def plain(value):
    return re.sub(r'\x1b\[[0-9;]*m', '', re.sub(r'\x1b_[^\x07]*\x07', '', value))

try:
    for order in ['ghost-first', 'owner-first']:
        root = Path(tempfile.mkdtemp(prefix='pi-ghost-'))
        agent, cwd = root/'agent', root/'project'; agent.mkdir(); cwd.mkdir()
        events = root/'events.jsonl'
        extensions = [entry, owner] if order == 'ghost-first' else [owner, entry]
        settings = root/'settings.json'
        settings.write_text(json.dumps({'extensions':extensions,'quietStartup':True,'theme':'dark','checkForUpdates':False}))
        (agent/'settings.json').symlink_to(settings)
        env = {key:os.environ[key] for key in ['PATH','SHELL'] if key in os.environ}
        env.update(HOME=str(root), TMPDIR=str(root), XDG_CONFIG_HOME=str(root/'config'), XDG_CACHE_HOME=str(root/'cache'),
                   PI_CODING_AGENT_DIR=str(agent), PI_OFFLINE='1', PI_TELEMETRY='0', USER='fixture',
                   TERM='xterm-256color', COLORTERM='truecolor', LANG='C.UTF-8',
                   PI_GHOST_EVENTS=str(events), PI_GHOST_BASE_URL=f'http://127.0.0.1:{server.server_port}/v1')
        args = [binary,'--offline','--no-approve','--no-context-files','--no-skills','--no-prompt-templates',
                '--no-mcp','--tui-mode','fullscreen','--model','fixture/unit']
        pid, master = pty.fork()
        if pid == 0:
            os.chdir(cwd); os.execve(binary,args,env)
        rows=36; screen=pyte.Screen(80,rows); stream=pyte.Stream(screen)
        decoder=codecs.getincrementaldecoder('utf8')('replace'); raw=bytearray(); exited=None
        def records():
            return [json.loads(line) for line in events.read_text().splitlines()] if events.exists() else []
        def pump():
            global exited
            if select.select([master],[],[],.05)[0]:
                try:
                    data=os.read(master,65536); raw.extend(data); stream.feed(decoder.decode(data))
                except OSError: pass
            if exited is None:
                done,status=os.waitpid(pid,os.WNOHANG)
                if done: exited=os.waitstatus_to_exitcode(status)
        def wait(predicate,label):
            deadline=time.monotonic()+20
            while time.monotonic()<deadline:
                pump()
                if predicate(): return
                assert exited is None, f'Pi exited {exited}: {label}'
            raise AssertionError(f'{order}: {label}\n'+ '\n'.join(screen.display))
        def settle():
            deadline=time.monotonic()+.25
            while time.monotonic()<deadline: pump()
        def send(value): os.write(master,value if isinstance(value,bytes) else value.encode())
        def capture():
            count=len(records()); send(b'\x1bg')
            wait(lambda:len(records())>count,'buffer witness')
            value=records()[-1]
            assert all(width<=value['width'] for width in value['widths']),value
            return value
        def draft(text):
            send(b'\x1bz'); settle()
            send(b'\x1b[200~'+text.encode()+b'\x1b[201~'); settle()
            return capture()
        def suffix(text='configurat'):
            value=draft(text)
            assert value['text']==text,value
            assert 'configuration' in plain('\n'.join(value['lines'])),value
            wait(lambda:'configuration' in '\n'.join(screen.display),'suffix visible in real terminal')
            assert sum('VISUAL OWNER' in line for line in screen.display)==1
            return value
        def resize(width):
            fcntl.ioctl(master,termios.TIOCSWINSZ,struct.pack('HHHH',rows,width,0,0))
            screen.resize(rows,width); os.kill(pid,signal.SIGWINCH); settle()
        try:
            resize(80)
            wait(lambda:any(r.get('startup') for r in records()),'startup')
            wait(lambda:'VISUAL OWNER' in '\n'.join(screen.display),'visual owner installed')
            settle()
            value=suffix()
            painted='\n'.join(value['lines'])
            assert re.search(r'configurat\x1b_pi:c\x07.*?i',painted),value
            send('\t'); settle(); assert capture()['text']=='configuration '
            suffix(); send(b'\x1b[C'); settle(); assert capture()['text']=='configuration'
            suffix(); send(b'\x1b'); settle()
            value=capture(); assert value['text']=='configurat'
            assert 'configuration' not in plain('\n'.join(value['lines']))
            # A tool name no English dictionary carries completes from the package-name prior.
            value=draft('kubec'); assert 'kubectl' in plain('\n'.join(value['lines'])),value
            # Every prose gate is observed on the actual wrapped editor.
            gates=['/mo','@src/','```\nconfigurat','~~~\nconfigurat','`configurat','<code>configurat</code>',
                   '<code>\nconfigurat','<div>\n<span>\nconfigurat','<!-- configurat','fooConfigurat','foo_configurat','x=configurat','x:configurat',
                   '{configurat','}configurat','[configurat',']configurat','<configurat','>configurat',
                   'x\\configurat','x/configurat','2configurat','-> configurat','=> configurat',
                   'x'*1001,'x\n'*10001+'configurat']
            for text in gates:
                value=draft(text)
                assert value['text']==text,(text,value)
                assert 'configuration' not in plain('\n'.join(value['lines'])),(text,value)
            draft('configurat'); send(b'\x1b[D'); settle(); value=capture()
            assert value['cursor']['col']==9,value
            assert 'configuration' not in plain('\n'.join(value['lines'])),value
            # Native command autocomplete keeps Tab, not a ghost.
            draft('/mo'); send('\t'); settle()
            assert capture()['text'] != '/moion '
            resize(40)
            suffix('😀 界 configurat'); send('\t'); settle()
            assert capture()['text']=='😀 界 configuration '
            (out/(order+'-40.txt')).write_text('\n'.join(screen.display))
            resize(80)
            for count in [2,3]:
                draft('/reload'); send('\r')
                wait(lambda:sum(r.get('startup',False) for r in records())==count,'reload')
                settle(); suffix(); send('\t'); settle()
                assert capture()['text']=='configuration '
            draft('/new'); send('\r')
            wait(lambda:sum(r.get('startup',False) for r in records())==4,'new session')
            settle(); suffix(); send('\t'); settle(); assert capture()['text']=='configuration '
            draft('/quit'); send('\r'); wait(lambda:exited is not None,'quit')
            assert exited==0
            assert len(requests)==0,requests
            assert (agent/'settings.json').is_symlink()
            state=agent/'ghost-text-state.json'
            assert state.stat().st_mode & 0o777 == 0o600
            assert not list(agent.glob('ghost-text-state.json.*.tmp'))
            for bad in ['Extension error','Failed to load extension','Unhandled']:
                assert bad not in raw.decode(errors='replace'),bad
        finally:
            (out/(order+'-raw.ansi')).write_bytes(raw)
            (out/(order+'-events.json')).write_text(json.dumps(records(),indent=2))
            if exited is None:
                try: os.killpg(pid,signal.SIGTERM); os.waitpid(pid,0)
                except (ProcessLookupError,ChildProcessError): pass
            os.close(master)
        # The extension must be a quiet no-op in both non-interactive modes.
        headless = root/'headless'; headless.mkdir()
        env['PI_CODING_AGENT_DIR']=str(headless)
        for mode in [[],['--mode','json']]:
            result=subprocess.run([binary,'--offline','--no-approve','--no-context-files','--no-skills','--no-mcp',
                                   '-e',entry,'-e',owner,'--model','fixture/unit',*mode,'-p','HEADLESS'],
                                  cwd=cwd,env=env,text=True,capture_output=True,timeout=30)
            assert result.returncode==0,(result.stdout,result.stderr)
            assert result.stderr=='',result.stderr
            assert 'HEADLESS_OK' in result.stdout,result.stdout
            assert not (headless/'ghost-text-state.json').exists()
        # Headless smoke requests are separate from completion: exactly one per invocation.
        assert len(requests)==2,requests
        requests.clear()
    print('PASS: both owner orders, painted suffix/real buffer, Tab/Right/Esc, every prose gate, native popup, 40 columns/CJK/emoji, two reloads/new, zero completion requests, quiet headless modes')
finally:
    (out/'requests.json').write_text(json.dumps(requests,indent=2))
    server.shutdown(); server.server_close(); thread.join(timeout=2)
