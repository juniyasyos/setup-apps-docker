#!/bin/bash
SCRIPT_DIR="$(pwd)"
source <(grep -E '^_has_frontend' -A 6 rsch)
source <(grep -E '^_get_fe_name' -A 4 rsch)
source <(grep -E '^_expand_app_services' -A 16 rsch)
echo "Output:"
_expand_app_services smsp true true
