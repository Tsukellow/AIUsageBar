#!/usr/bin/env python3
"""Use one pinned local signing identity; creation is an explicit one-time action."""
import argparse
import hashlib
import json
import os
import plistlib
import secrets
import shlex
import subprocess
import tempfile
from pathlib import Path

NAME = 'Tsukellow Local Code Signing'
ROOT = Path.home() / 'Library/Application Support/Tsukellow-Code-Signing'
KEYCHAIN = ROOT / 'identity.keychain-db'
PASSWORD = ROOT / 'keychain-password'
CERTIFICATE = ROOT / 'certificate.pem'
BACKUP = ROOT / 'identity.p12'
MANIFEST = ROOT / 'identity.json'
PIN = Path(__file__).resolve().parent / 'signing-identity.json'


def run(*args):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout + result.stderr


def security_input(*args):
    # security's interactive mode keeps passwords out of process arguments.
    command = ' '.join(shlex.quote(str(a)) for a in args) + '\n'
    result = subprocess.run(['/usr/bin/security', '-i'], input=command,
                            capture_output=True, text=True)
    errors = ('SecKeychain', 'SecItemImport', 'SecTrustSettings', 'CSSMERR', 'Error:')
    if result.returncode or any(error in result.stderr for error in errors):
        raise RuntimeError('Keychain operation failed; signing material was preserved.')


def certificate_identity():
    der = subprocess.check_output(['/usr/bin/openssl', 'x509', '-in', str(CERTIFICATE), '-outform', 'DER'])
    expiration = run('/usr/bin/openssl', 'x509', '-in', CERTIFICATE, '-enddate', '-noout').strip()
    return dict(name=NAME, sha1=hashlib.sha1(der).hexdigest().upper(),
                sha256=hashlib.sha256(der).hexdigest().upper(), expires=expiration.split('=', 1)[1])


def check_private(path, directory=False):
    if path.is_symlink() or not path.exists() or path.stat().st_uid != os.getuid():
        raise RuntimeError(f'Missing or unsafe signing path: {path}')
    if bool(path.is_dir()) != directory or path.stat().st_mode & 0o077:
        raise RuntimeError(f'Signing path must be owner-only: {path}')


def prepare():
    check_private(ROOT, directory=True)
    for path in (PASSWORD, KEYCHAIN, CERTIFICATE, MANIFEST):
        check_private(path)
    identity = json.loads(PIN.read_text())
    if identity != json.loads(MANIFEST.read_text()) or identity != certificate_identity():
        raise RuntimeError('Signing identity differs from the repository pin. Restore the original identity.')
    run('/usr/bin/openssl', 'x509', '-in', CERTIFICATE, '-checkend', '0', '-noout')
    override = os.environ.get('APPLE_SIGNING_IDENTITY')
    if override and override != identity['sha1']:
        raise RuntimeError('APPLE_SIGNING_IDENTITY conflicts with the fixed certificate.')
    password = PASSWORD.read_text().strip()
    if len(password) != 64 or any(c not in '0123456789abcdef' for c in password):
        raise RuntimeError('Invalid signing keychain password file.')
    security_input('unlock-keychain', '-p', password, KEYCHAIN)
    valid = run('/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning', KEYCHAIN)
    if identity['sha1'] not in valid:
        raise RuntimeError('The pinned identity is unavailable for code signing.')
    return identity


def initialize():
    os.umask(0o077)
    if MANIFEST.exists():
        identity = json.loads(MANIFEST.read_text())
        if PIN.exists() and json.loads(PIN.read_text()) != identity:
            raise RuntimeError('Refusing to replace the existing repository pin.')
        if identity != certificate_identity():
            raise RuntimeError('Local certificate and manifest differ.')
    else:
        if PIN.exists() or (ROOT.exists() and any(ROOT.iterdir())):
            raise RuntimeError('Signing material is missing or incomplete. Restore it; do not create a replacement.')
        ROOT.mkdir(parents=True, mode=0o700, exist_ok=True)
        ROOT.chmod(0o700)
        password = secrets.token_hex(32)
        PASSWORD.write_text(password + '\n')
        with tempfile.TemporaryDirectory(prefix='create-', dir=ROOT) as temporary:
            temporary = Path(temporary)
            config, private = temporary / 'openssl.cnf', temporary / 'key.pem'
            config.write_text('[req]\nprompt=no\ndistinguished_name=subject\nx509_extensions=codesign\n'
                              f'[subject]\nCN={NAME}\n[codesign]\nbasicConstraints=critical,CA:false\n'
                              'keyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n'
                              'subjectKeyIdentifier=hash\n')
            run('/usr/bin/openssl', 'req', '-new', '-x509', '-newkey', 'rsa:3072', '-nodes', '-sha256',
                '-days', '3650', '-config', config, '-keyout', private, '-out', CERTIFICATE)
            run('/usr/bin/openssl', 'pkcs12', '-export', '-inkey', private, '-in', CERTIFICATE,
                '-name', NAME, '-out', BACKUP, '-passout', 'file:' + str(PASSWORD))
        security_input('create-keychain', '-p', password, KEYCHAIN)
        security_input('unlock-keychain', '-p', password, KEYCHAIN)
        run('/usr/bin/security', 'set-keychain-settings', '-lut', '3600', KEYCHAIN)
        security_input('import', BACKUP, '-k', KEYCHAIN, '-f', 'pkcs12', '-P', password,
                       '-T', '/usr/bin/codesign')
        security_input('set-key-partition-list', '-S', 'apple-tool:,apple:', '-s', '-k', password, KEYCHAIN)
        # User-domain trust for code signing only; default keychain and TLS trust stay unchanged.
        run('/usr/bin/security', 'add-trusted-cert', '-r', 'trustRoot', '-p', 'codeSign',
            '-k', KEYCHAIN, CERTIFICATE)
        identity = certificate_identity()
        MANIFEST.write_text(json.dumps(identity, indent=2) + '\n')
        for path in (PASSWORD, KEYCHAIN, CERTIFICATE, BACKUP, MANIFEST):
            path.chmod(0o600)
    PIN.write_text(json.dumps(identity, indent=2) + '\n')
    PIN.chmod(0o644)
    prepare()
    print(f"Pinned {NAME}: {identity['sha1']}")


def verify(app, identifier, identity):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        if plistlib.load(stream)['CFBundleIdentifier'] != identifier:
            raise RuntimeError('Unexpected application bundle identifier.')
    requirement = f'=identifier "{identifier}" and certificate leaf = H"{identity["sha1"]}"'
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', '-R', requirement, app)
    output = run('/usr/bin/codesign', '-d', '-r-', app)
    designated = next((line for line in output.splitlines() if line.startswith('designated =>')), '')
    if identity['sha1'].lower() not in designated.lower() or 'cdhash' in designated.lower():
        raise RuntimeError('Designated requirement is not bound to the pinned certificate.')
    print(designated)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['init', 'prepare', 'sign', 'verify'])
    parser.add_argument('app', nargs='?', type=Path)
    parser.add_argument('identifier', nargs='?')
    args = parser.parse_args()
    if args.action == 'init':
        initialize()
    elif args.action == 'prepare':
        print(prepare()['sha1'])
    else:
        if not args.app or not args.identifier:
            parser.error('sign and verify require an application path and bundle identifier')
        identity = json.loads(PIN.read_text())
        if args.action == 'sign':
            identity = prepare()
            with (args.app / 'Contents/Info.plist').open('rb') as stream:
                if plistlib.load(stream)['CFBundleIdentifier'] != args.identifier:
                    raise RuntimeError('Unexpected application bundle identifier.')
            run('/usr/bin/codesign', '--force', '--sign', identity['sha1'], '--keychain', KEYCHAIN,
                '--identifier', args.identifier, '--options', 'runtime', '--timestamp=none', args.app)
        verify(args.app, args.identifier, identity)


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.SubprocessError) as error:
        raise SystemExit(f'Local signing: {error}')
