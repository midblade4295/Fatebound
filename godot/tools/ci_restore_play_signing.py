"""Reuse the established repository signing stage inside the authorized CI job.

Does not change the key or copy signing material into artifacts. Refuses to run
outside GitHub Actions; no private signing material is retrieved to the VM.
"""
from pathlib import Path
import os,subprocess,textwrap,re
assert os.environ.get('GITHUB_ACTIONS')=='true','Signing is only supported inside the established CI runner'
s=Path('.github/workflows/build-aab.yml').read_text()
start=s.index('      - name: Restore Play upload keystore')
stop=s.index('      - name: Build release AAB',start)
block=s[start:stop]
body=textwrap.dedent(block.split('        run: |\n',1)[1]).strip()
# Mask the old configuration values before executing the existing setup stage.
for value in re.findall(r'SIGNING_(?:STORE_PASSWORD|KEY_PASSWORD)=([^"\n]+)',body):
 print('::add-mask::'+value,flush=True)
subprocess.run(['bash','-eu','-c',body],check=True)
