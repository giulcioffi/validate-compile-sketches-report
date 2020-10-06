#!/bin/bash

if test -f database-reports/full-database-report.json; then
    rm database-reports/full-database-report.json
fi

echo "Merging the board-related json files from the database into a single report"

jq -s '.[0].boards=([.[].boards]|flatten)|.[0]' database-reports/*.json >> database-reports/full-database-report.json

jq 'del(.boards[0].sketches[].sizes)' database-reports/full-database-report.json >> database-reports/modified-full-database-report.json

mv database-reports/modified-full-database-report.json database-reports/full-database-report.json

exit 0
