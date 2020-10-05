#!/bin/bash

echo "Merging the board-related json files from the database into a single report"
jq -s '.[0].boards=([.[].boards]|flatten)|.[0]' database-reports/*.json >> database-reports/full-database-report.json

echo "Merging the board-related json files from the last compilation into a single report"
jq -s '.[0].boards=([.[].boards]|flatten)|.[0]' sketches-reports/*.json >> sketches-reports/full-sketches-report.json

exit 0