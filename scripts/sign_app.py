#!/usr/bin/env python3
"""Sign embedded Mach-O code inside-out before sealing the app bundle."""
import pathlib
import subprocess
import sys
import base64
import csv
import hashlib
import io
import tempfile
import zipfile

app = pathlib.Path(sys.argv[1]).resolve()
identity = sys.argv[2]
entitlements = pathlib.Path(sys.argv[3]).resolve()
python_entitlements = pathlib.Path(__file__).resolve().parent.parent / 'Resources/Python.entitlements'
magic = {bytes.fromhex(v) for v in ('feedface', 'feedfacf', 'cefaedfe', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}

def sign(path, entitlement=None):
    command = ['codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', identity]
    if entitlement:
        command += ['--entitlements', str(entitlement)]
    subprocess.run(command + [str(path)], check=True)

# The notary service also inspects native code inside wheel ZIP archives.
# Rebuild RECORD after signing; source wheelhouse remains untouched.
for wheel in sorted(app.rglob('*.whl')):
    with zipfile.ZipFile(wheel) as archive:
        entries = [(item, archive.read(item)) for item in archive.infolist()]
    if not any(data[:4] in magic for _, data in entries):
        continue
    updated = []
    with tempfile.TemporaryDirectory(prefix='gzwhisper-sign-wheel-') as directory:
        for index, (item, data) in enumerate(entries):
            if data[:4] in magic:
                binary = pathlib.Path(directory) / str(index)
                binary.write_bytes(data)
                sign(binary)
                data = binary.read_bytes()
            updated.append((item, data))
    records = [item.filename for item, _ in updated if item.filename.endswith('.dist-info/RECORD')]
    if len(records) != 1:
        raise RuntimeError(f'Expected one wheel RECORD: {wheel}')
    record = records[0]
    output = io.StringIO(newline='')
    writer = csv.writer(output, lineterminator='\n')
    for item, data in updated:
        if item.is_dir():
            continue
        if item.filename == record:
            writer.writerow([record, '', ''])
        else:
            digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b'=').decode()
            writer.writerow([item.filename, 'sha256=' + digest, str(len(data))])
    temporary = wheel.with_suffix('.whl.tmp')
    with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for item, data in updated:
            archive.writestr(item, output.getvalue().encode() if item.filename == record else data)
    temporary.replace(wheel)

for path in sorted(app.rglob('*')):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open('rb') as source:
        if source.read(4) not in magic:
            continue
    # Python loads third-party native wheels installed outside the signed bundle.
    sign(path, python_entitlements if path.name.startswith('python') or path.name == 'Python' else None)

for path in sorted(app.rglob('*'), key=lambda p: len(p.parts), reverse=True):
    if path.is_dir() and not path.is_symlink() and path.suffix in ('.framework', '.app', '.xpc'):
        sign(path, python_entitlements if 'Python' in path.name else None)
sign(app, entitlements)
subprocess.run(['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(app)], check=True)
