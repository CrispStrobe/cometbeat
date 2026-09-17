#!/usr/bin/env python3
"""Native profile run, preserving exact command, log, sandbox metrics, summary."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', help='Output directory (default /tmp/composition-profile-TIMESTAMP)')
    parser.add_argument('--editor', choices=['workshop', 'daw', 'loop_mixer', 'advanced_tracker'])
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    run_id = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    out = Path(args.output or f'/tmp/composition-profile-{run_id}').resolve()
    out.mkdir(parents=True, exist_ok=False)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    command = ['flutter', 'drive', '--profile', '-d', 'macos',
               '--driver=test_driver/composition_profile_driver.dart',
               '--target=integration_test/composition_profile_test.dart',
               f'--dart-define=PROFILE_RUN_ID={run_id}',
               f'--dart-define=PROFILE_REVISION={revision}']
    if args.editor:
        command.append(f'--dart-define=PROFILE_EDITOR={args.editor}')
    (out / 'source.diff').write_text(subprocess.check_output(['git', 'diff'], cwd=root, text=True))
    env = dict(os.environ, PATH='/usr/bin:' + os.environ['PATH'])
    for key in ('GEM_HOME', 'GEM_PATH', 'RUBYOPT'):
        env.pop(key, None)
    (out / 'command.json').write_text(json.dumps({'cwd': str(root), 'command': command,
        'environment': 'PATH=/usr/bin:$PATH env -u GEM_HOME -u GEM_PATH -u RUBYOPT',
        'revision': revision, 'run_id': run_id,
        'contention': 'Exploratory; do not use for before/after without uncontended rerun'}, indent=2))
    (out / 'processes-before.txt').write_text(subprocess.check_output(['ps', '-axo', 'pid,pcpu,comm'], text=True))
    artifacts = set()
    with (out / 'flutter-drive.log').open('w') as log:
        process = subprocess.Popen(command, cwd=root, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, bufsize=1)
        for line in process.stdout:
            log.write(line)
            log.flush()
            print(line, end='', flush=True)
            if 'COMPOSITION_PROFILE_ARTIFACT=' in line:
                artifacts.add(line.split('COMPOSITION_PROFILE_ARTIFACT=', 1)[1].strip())
        code = process.wait()
    for artifact in artifacts:
        shutil.copyfile(artifact, out / Path(artifact).name)
    (out / 'exit-code.txt').write_text(str(code) + '\n')
    metrics = out / 'metrics.json'
    if metrics.exists():
        data = json.loads(metrics.read_text())
        results = [{k: v for k, v in result.items() if k not in
                   ('frames', 'allocation_before', 'allocation_after')} for result in data['results']]
        for summary, result in zip(results, data['results']):
            summary['allocation_available'] = result['allocation_after']['available']
        (out / 'summary.json').write_text(json.dumps({'metadata': data['metadata'], 'results': results}, indent=2))
        editors = {r['editor'] for r in results if r['phase'] == 'playback'}
        expected = {args.editor} if args.editor else {'workshop', 'daw', 'loop_mixer', 'advanced_tracker'}
        print(f'Playback editors collected: {len(editors)}/{len(expected)}: {sorted(editors)}')
        if editors != expected or data['metadata']['failures']:
            code = code or 1
    else:
        print('BLOCKER: no metrics artifact was produced', file=sys.stderr)
        code = code or 1
    print(f'PROFILE_OUTPUT={out}')
    return code


if __name__ == '__main__':
    sys.exit(main())
