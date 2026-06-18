#!/usr/bin/env bash
# Bootstrap for CLI scripts. Sets ROOT and loads common helpers.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/lib/common.sh"
source "${ROOT}/lib/pg-format.sh"
