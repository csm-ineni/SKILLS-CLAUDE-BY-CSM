#!/usr/bin/env bash
# Shared helpers for the plugin's golden-input tests.
# Sourced by every *.test.sh file; never executed on its own.

fail=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then
    echo "PASS $1"
  else
    echo "FAIL $1 expected=$2 got=$3"
    fail=1
  fi
}

check_contains() { # name needle haystack
  case "$3" in
    *"$2"*) echo "PASS $1" ;;
    *) echo "FAIL $1 (missing '$2')"; fail=1 ;;
  esac
}

check_lacks() { # name needle haystack
  case "$3" in
    *"$2"*) echo "FAIL $1 (unexpected '$2')"; fail=1 ;;
    *) echo "PASS $1" ;;
  esac
}

# A throwaway git repo, so branch-dependent tests never touch the real one.
make_repo() { # dir branch
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name Test
  git -C "$1" checkout -q -b "$2"
  echo seed > "$1/seed.txt"
  git -C "$1" add seed.txt
  git -C "$1" commit -q -m "chore: seed"
}

report() { # suite-name
  [ "$fail" -eq 0 ] && echo "ALL TESTS PASSED ($1)" || echo "SOME TESTS FAILED ($1)"
  return "$fail"
}
