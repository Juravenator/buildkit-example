#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
IFS=$'\n\t\v'

if [[ -z "${DBR_QUERY:-}" ]]; then
    >&2 echo "ERROR: DB Query is empty"
    exit 1
fi

if <<< "${DBR_QUERY}" grep -qi \
    -e "ALTER TABLE " \
    -e "ALTER COLUMN "
then
    echo "complex query"
    set_octopusvariable "query_is_complex" "1"
else
    echo "not a complex query"
    set_octopusvariable "query_is_complex" "0"
fi

if <<< "${DBR_QUERY}" grep -qi -e "DROP "; then
    >&2 echo "VIOLATION: This query contains a DROP statement, which is not allowed. Exiting..."
    exit 1
fi