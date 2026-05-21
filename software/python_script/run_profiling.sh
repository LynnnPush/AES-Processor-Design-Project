#!/usr/bin/env bash
# Run the merged CPI-stack + dynamic-profiling pipeline.
# Resolves its own location so it works regardless of caller cwd
# (e.g. when invoked from Vivado xsim via $system in zynq_tb.sv).
#
# Detaches from the calling process group via setsid so the python
# job survives even if the caller (xsim/vivado) exits before it
# finishes. The testbench backgrounds this script with '&', so we
# also nohup-ify to ignore SIGHUP from the parent shell.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

# Vivado 2024.2 exports PYTHONHOME and PYTHONPATH pointing at its own
# bundled python-3.8.3 install. If we invoke /usr/bin/python3 (3.9) with
# those still set, Python 3.9 looks for stdlib (encodings, etc.) inside
# Vivado's 3.8 tree under a 3.9 layout, fails to bootstrap, and aborts
# with "ModuleNotFoundError: No module named 'encodings'". Strip them.
unset PYTHONHOME PYTHONPATH

# Vivado also prepends its own libcrypto.so.3 / libssl.so.3 via
# LD_LIBRARY_PATH, which is older than the system libs that the system
# Python's _hashlib was built against. Result: matplotlib import fails
# with "OPENSSL_3.4.0 not found". Wipe LD_LIBRARY_PATH so the dynamic
# loader uses /lib64 where /usr/bin/python3 expects to find its deps.
unset LD_LIBRARY_PATH

# Vivado's $system subshell may also strip HOME, which prevents Python's
# user-site (~/.local/lib/python3.9/site-packages where matplotlib lives)
# from being added to sys.path. Restore it from /etc/passwd if missing.
: "${HOME:=$(getent passwd "$(id -un)" | cut -d: -f6)}"
export HOME
export PYTHONUSERBASE="${PYTHONUSERBASE:-$HOME/.local}"

# Pin to the system Python (3.9) where matplotlib was pip-installed.
# A bare `python3` would resolve to Vivado's broken 3.8 on PATH.
PYTHON_BIN="${PYTHON_BIN:-/usr/bin/python3}"

exec setsid nohup "$PYTHON_BIN" "$DIR/profile.py" </dev/null >>"${TMPDIR:-/tmp}/profile.log" 2>&1
