"""Optional local-venv startup hook for standard benchmark runs only.

Install via a temporary .pth; CONFVAR_CAPTURE must be set. The profiler removes
itself at the first PeTTaChainer constructor return, after library loading, then
installs a Prolog wrapper which records unique calls without changing answers.
"""
import os
from pathlib import Path
import sys


def install():
    import janus_swi
    janus_swi.consult(str(Path(__file__).with_name('capture.pl').resolve()))


def loaded(frame, event, arg):
    if (event == 'return' and frame.f_code.co_name == '__init__'
            and frame.f_globals.get('__name__') == 'pettachainer.pettachainer'):
        sys.setprofile(None)
        install()


if os.environ.get('CONFVAR_CAPTURE'):
    sys.setprofile(loaded)
