#!/usr/bin/env python3
"""Report suspect shell waiters from a process snapshot; never signal them."""
import os
from pathlib import Path
import re
import subprocess

rows = subprocess.check_output(['ps', '-eo', 'pid=,ppid=,args='], text=True)
processes = {}
waiters = {}
for row in rows.splitlines():
    fields = row.strip().split(None, 2)
    if len(fields) != 3:
        continue
    pid, parent, command = fields
    processes[int(pid)] = (int(parent), command)
    if Path(command.split(None, 1)[0]).name not in ('sh', 'bash', 'dash', 'zsh', 'ksh'):
        continue
    # ps does not retain argv boundaries: the rest after -c is the script.
    match = re.search(r'\s-(?:[a-z]*c[a-z]*)\s+(.+)', command, re.S)
    if not match:
        continue
    script = match[1]
    if re.search(r'\b(?:until|while)\b', script) and re.search(r'\bsleep\s', script):
        waiters[int(pid)] = script

print('Leftover waiter loops (diagnostic only; no processes killed):')
found = False
for pid, script in waiters.items():
    condition = re.search(r'\b(?:until|while)\s+(.*?);?\s*do\b', script, re.S)
    if not condition:
        continue
    condition = condition[1]
    pattern = re.search(r'\bpgrep\s+-f\s+("[^"]+"|\x27[^\x27]+\x27|[^\s;|&]+)', condition)
    reason = None
    if pattern:
        pattern = pattern[1].strip("\"'")
        if '$' in pattern or '`' in pattern:
            continue
        try:
            live = any(re.search(pattern, cmd) for other, (_, cmd) in processes.items()
                       if other not in waiters and other != os.getpid()
                       and not re.match(r'^(?:\S*/)?(?:ps|sleep)\b', cmd))
        except re.error:
            continue
        if not live:
            reason = f'pgrep target {pattern!r} absent (waiting shells excluded)'
    elif re.search(r'\bgrep\b', condition):
        # A numeric PID guard provides evidence; an unguarded log loop can
        # only be suspected when no job remains under its parent shell.
        guard = re.search(r'\bkill\s+-0\s+(\d+)\b', condition)
        if guard:
            if int(guard[1]) not in processes:
                reason = f'log waiter target PID {guard[1]} absent'
        else:
            parent = processes[pid][0]
            live = any(other != pid and other not in waiters
                       and (p == pid or (parent > 1 and p == parent)) and not re.match(r'^(?:\S*/)?sleep\b', cmd)
                       for other, (p, cmd) in processes.items())
            if not live:
                reason = 'possible stale log waiter: no job under its parent; target PID unknown'
    if reason:
        print(f'  PID {pid} (PPID {processes[pid][0]}): {reason}\n    {script}')
        found = True
if not found:
    print('  none detected')
