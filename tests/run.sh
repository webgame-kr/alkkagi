#!/usr/bin/env bash
# 헤드리스 테스트. 스크립트 오류가 하나라도 나오면 실패로 본다.
# 사용: GODOT=/path/to/godot tests/run.sh
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
[ -d .godot ] || "$GODOT" --headless --path . --import >/dev/null 2>&1
out=$("$GODOT" --headless --path . -s res://tests/run_tests.gd 2>&1)
code=$?
echo "$out" | grep -v '^$'
if echo "$out" | grep -q "SCRIPT ERROR"; then
  echo "script errors found"; exit 1
fi
exit $code
