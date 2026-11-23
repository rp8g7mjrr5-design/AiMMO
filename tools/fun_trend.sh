#!/usr/bin/env bash
# Fun-metric trend over recent main CI runs, one line per run (for the director's digest).
# Usage: tools/fun_trend.sh [--runs 10] [--branch main] [--json]   (see tools/fun_trend.py)
exec python3 "$(dirname "$0")/fun_trend.py" "$@"
