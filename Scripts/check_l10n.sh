#!/bin/bash
# Fails if a user-facing Korean string literal is still hard-coded in a view or
# a model, instead of going through `L` in Model/Localization.swift.
#
# `--selftest` walks everything enumerable (enum labels, the whole Help book),
# but the individual `L` members can't be reflected over — this is the static
# half of that check. Run it before shipping a UI change.
set -uo pipefail

cd "$(dirname "$0")/.."

# Localization.swift and HelpBook.swift *are* the translations; SelfTest and
# Snapshot print to a developer's terminal, not to the interface.
EXCLUDE='Sources/SFTPManager/Model/Localization.swift
Sources/SFTPManager/Views/HelpBook.swift
Sources/SFTPManager/SelfTest.swift
Sources/SFTPManager/Snapshot.swift'

found=0
while IFS= read -r file; do
    case "$EXCLUDE" in *"$file"*) continue ;; esac
    # A Korean string literal, on a line that is not a comment.
    hits=$(grep -n '"[^"]*[가-힣][^"]*"' "$file" | grep -v '^[0-9]*:[[:space:]]*//' || true)
    if [ -n "$hits" ]; then
        echo "▸ $file"
        echo "$hits" | sed 's/^/    /'
        found=$((found + 1))
    fi
done < <(find Sources -name '*.swift' | sort)

if [ "$found" -ne 0 ]; then
    echo
    echo "✗ 번역되지 않은 문자열이 ${found}개 파일에 있습니다 — L.<이름>으로 옮기세요."
    exit 1
fi

echo "✓ 하드코딩된 한글 문자열 없음"
