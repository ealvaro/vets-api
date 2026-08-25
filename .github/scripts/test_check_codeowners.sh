#!/bin/bash

# Validates check_in_codeowners behavior for dotfiles and regular files.
# Run from repo root: bash .github/scripts/test_check_codeowners.sh

check_in_codeowners() {
    local file="$1"
    local escaped_file
    while [[ "$file" != '.' && "$file" != '/' ]]; do
        escaped_file=$(printf '%s\n' "$file" | sed 's/\./\\./g')
        if grep -qE "^[[:space:]]*${escaped_file}(/)?([[:space:]]|\$)" .github/CODEOWNERS; then
            return 0
        fi
        if grep -qE "^[[:space:]]*${escaped_file}/\*([[:space:]]|\$)" .github/CODEOWNERS; then
            return 0
        fi
        file=$(dirname "$file")
    done
    return 1
}

pass=0
fail=0

assert_found() {
    local file="$1"
    if check_in_codeowners "$file"; then
        echo "PASS (found):     $file"
        pass=$((pass + 1))
    else
        echo "FAIL (not found): $file — expected a CODEOWNERS entry"
        fail=$((fail + 1))
    fi
}

assert_not_found() {
    local file="$1"
    if check_in_codeowners "$file"; then
        echo "FAIL (found):     $file — expected no CODEOWNERS entry"
        fail=$((fail + 1))
    else
        echo "PASS (not found): $file"
        pass=$((pass + 1))
    fi
}

echo "=== Dotfiles: should be found ==="
assert_found ".gitignore"
assert_found ".gitattributes"
assert_found ".rubocop.yml"
assert_found ".rubocop_todo.yml"
assert_found ".rubocop_openstruct.yml"
assert_found ".rubocop_explicit_enables.yml"
assert_found ".reek.yml"
assert_found ".rspec"
assert_found ".rspec_parallel"
assert_found ".ruby-version"
assert_found ".irbrc"
assert_found ".undercover"
assert_found ".yardopts"

echo ""
echo "=== Dotfiles: should NOT be found ==="
assert_not_found ".nonexistent_dotfile"
assert_not_found ".env.local"

echo ""
echo "=== Regular files: should be found via direct or parent match ==="
assert_found "app/concerns/rated_disabilities_fetch_concern.rb"
assert_found ".github/workflows/watch_engineers_review_gate.yml"
assert_found ".github/CODEOWNERS"

echo ""
echo "=== Regular files: should NOT be found ==="
assert_not_found "some/completely/unowned/file.rb"

echo ""
echo "Results: ${pass} passed, ${fail} failed"
[[ $fail -eq 0 ]]
