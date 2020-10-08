#!/bin/bash

SKETCH_FAILED=0
FOUND_BOARD_IN_DATABASE=0
FOUND_SKETCH_IN_DATABASE=0
SKETCH_NOT_IN_DATABASE=0
INDEX_I=0
INDEX_J=0
INDEX_K=0
INDEX_L=0
SKETCH_FAILED=0
SKETCH_PASSED=0
SKETCH_UNDEFINED=0
REPORT_FAILED=0
REPORT_PASSED=0
REPORT_UNDEFINED=0

if [ "$#" -ne 2 ]; then
  echo "Usage: compare-reports.sh SKETCHES-REPORT-PATH EXPECTED-RESULTS-DATABASE"
  exit 1
fi

SKETCHES_SOURCE_PATH=$1
echo "Sketches reports source path: $SKETCHES_SOURCE_PATH"

DATABASE_SOURCE_PATH=$2
echo "Expected results database source path: $DATABASE_SOURCE_PATH"

if [ -d "$SKETCHES_SOURCE_PATH" ]; then
  # The sketches reports input directory exists
  echo "Sketches reports found in ${SKETCHES_SOURCE_PATH}:"
  find $SKETCHES_SOURCE_PATH -maxdepth 1
else
  # The sketches reports input directory DOESN'T exists
  echo "Sketches reports directory ${SKETCHES_SOURCE_PATH} DOESN'T exist!"
  exit 1
fi

FULL_SKETCHES_REPORT_PATH="/tmp/full-sketches-report.json"

if test -f "$FULL_SKETCHES_REPORT_PATH"; then
    rm "$FULL_SKETCHES_REPORT_PATH"
fi

echo "Merging the board-related json files from the last compilation into a single report"
jq -s '.[0].boards=([.[].boards]|flatten)|.[0]' $SKETCHES_SOURCE_PATH/*.json >> "$FULL_SKETCHES_REPORT_PATH"

echo "Computing the total number of boards from full-sketches-report.json"
num_boards_sketches_report=$(jq '.boards | length' "$FULL_SKETCHES_REPORT_PATH")
echo $num_boards_sketches_report

echo "Computing the total number of boards from full-database-report.json"
num_boards_database_report=$(jq '.boards | length' $DATABASE_SOURCE_PATH)
echo $num_boards_database_report

for file_name in $SKETCHES_SOURCE_PATH/*.json; do # Whitespace-safe but not recursive.
  # Add expected_compilation_success and validation_result keys to each sketches report and set all of them to false
  jq '.boards[0].sketches[] += {"expected_compilation_success":"undefined"}' $file_name >> $SKETCHES_SOURCE_PATH/modified-report.json
  mv $SKETCHES_SOURCE_PATH/modified-report.json $file_name

  jq '.boards[0].sketches[] += {"validation_result":"undefined"}' $file_name >> $SKETCHES_SOURCE_PATH/modified-report.json
  mv $SKETCHES_SOURCE_PATH/modified-report.json $file_name
done


#First iteration over the number of boards used in the current compilation
while [ $INDEX_I -lt $num_boards_sketches_report ]; do
  #save the current board name
  board_name=$(cat "$FULL_SKETCHES_REPORT_PATH" | jq ".boards[$INDEX_I].board")
  echo "Current board name: $board_name"
  #compute and save the number of sketches compiled for that board
  num_sketches_per_board=$(jq ".boards[$INDEX_I].sketches | length" "$FULL_SKETCHES_REPORT_PATH")
  echo "Number of sketches for current board: $num_sketches_per_board"

  #iterate over all the sketches of that board and check which compilations failed
  while [ $INDEX_J -lt $num_sketches_per_board ]; do
    compilation_status=$(cat "$FULL_SKETCHES_REPORT_PATH" | jq ".boards[$INDEX_I].sketches[$INDEX_J].compilation_success")

    #reset the flags that checks if a board/sketch has been found in the database
    FOUND_BOARD_IN_DATABASE=0
    FOUND_SKETCH_IN_DATABASE=0
    #save the sketch name
    name_failed_sketch=$(cat "$FULL_SKETCHES_REPORT_PATH" | jq ".boards[$INDEX_I].sketches[$INDEX_J].name")

    #iterate over the available boards in the report util the current board is found
    while [ $INDEX_K -lt $num_boards_database_report ]; do
      database_board_name=$(cat $DATABASE_SOURCE_PATH | jq ".boards[$INDEX_K].board")
      if [ $database_board_name == $board_name ]; then
        FOUND_BOARD_IN_DATABASE=1
        #compute the number of available sketches in the database for the current board
        num_database_sketches_per_board=$(jq ".boards[$INDEX_K].sketches | length" $DATABASE_SOURCE_PATH)

        #iterate over all the database sketches of that board until the one that failed is found
        while [ $INDEX_L -lt $num_database_sketches_per_board ]; do
          database_sketch_name=$(cat $DATABASE_SOURCE_PATH | jq ".boards[$INDEX_K].sketches[$INDEX_L].name")
          if [ "$database_sketch_name" == "$name_failed_sketch" ]; then
            #set the related flag
            FOUND_SKETCH_IN_DATABASE=1
            database_compilation_status=$(cat $DATABASE_SOURCE_PATH | jq ".boards[$INDEX_K].sketches[$INDEX_L].compilation_success")

            for file_name in $SKETCHES_SOURCE_PATH/*.json; do
              single_file_board_name=$(cat $file_name | jq ".boards[0].board")
              if [ "$board_name" == "$single_file_board_name" ]; then
                #correct sketches-report found

                # update the expected_compilation_success key
                jq ".boards[0].sketches[$INDEX_J] += {"expected_compilation_success":"$database_compilation_status"}" $file_name >> $SKETCHES_SOURCE_PATH/modified-report.json
                mv $SKETCHES_SOURCE_PATH/modified-report.json $file_name

                #check the expected results
                if [ "$database_compilation_status" == "true" ]; then
                  if [ "$compilation_status" == "false" ]; then
                    # update the validation_result key with result "fail"
                    jq ".boards[0].sketches[$INDEX_J].validation_result = \"fail\"" $file_name >> $SKETCHES_SOURCE_PATH/modified-report.json
                    mv $SKETCHES_SOURCE_PATH/modified-report.json $file_name

                    echo "COMPILATION FAILURE: compilation of sketch $database_sketch_name on board $database_board_name has EXPECTED result $database_compilation_status"
                    #increment the number of sketch failed
                    let SKETCH_FAILED=SKETCH_FAILED+1
                    break
                  elif [ "$compilation_status" == "true" ]; then
                    # update the validation_result key with result "pass"
                    jq ".boards[0].sketches[$INDEX_J].validation_result = \"pass\"" $file_name >> $SKETCHES_SOURCE_PATH/modified-report.json
                    mv $SKETCHES_SOURCE_PATH/modified-report.json $file_name
                    break
                  else
                    echo "ERROR: invalid compilation_status value $compilation_status"
                    exit 1
                  fi
                elif [ "$database_compilation_status" == "false" ]; then
                  if [ "$compilation_status" == "false" ]; then
                    # update the validation_result key with result "pass"
                    jq ".boards[0].sketches[$INDEX_J] += {"validation_result":\"pass\"}" $file_name >> $SKETCHES_SOURCE_PATH/modified-report.json
                    mv $SKETCHES_SOURCE_PATH/modified-report.json $file_name

                    echo "Ignore compilation failure: compilation of sketch $database_sketch_name on board $database_board_name has EXPECTED result $database_compilation_status"
                    break
                  elif [ "$compilation_status" == "true" ]; then
                    # update the validation_result key with result "pass", but print ERROR message
                    jq ".boards[0].sketches[$INDEX_J].validation_result = \"pass\"" $file_name >> $SKETCHES_SOURCE_PATH/modified-report.json
                    mv $SKETCHES_SOURCE_PATH/modified-report.json $file_name

                    echo "ERROR: According to the database, compilation of sketch $filename with board $board_name should have failed!"
                    break
                  else
                    echo "ERROR: invalid compilation_status value $compilation_status"
                    exit 1
                  fi
                else
                  echo "ERROR: invalid database_compilation_status value $database_compilation_status"
                  exit 1
                fi
              fi

            done

          fi

          if [ $FOUND_SKETCH_IN_DATABASE == 0 ]; then
            let INDEX_L=INDEX_L+1
          else
            break
          fi

        done
        let INDEX_L=0

        #check if the sketch has been found or not
        if [ $FOUND_SKETCH_IN_DATABASE == 1 ]; then
          break
        fi

      fi
      if [ $FOUND_SKETCH_IN_DATABASE == 0 ]; then
        let INDEX_K=INDEX_K+1
      else
        break
      fi
    done
    let INDEX_K=0

    #check if the sketch has been found or not
    if [ $FOUND_SKETCH_IN_DATABASE == 0 ]; then
      echo "The expected compilation result of sketch $name_failed_sketch on board $board_name is NOT present in the database!"
      let SKETCH_NOT_IN_DATABASE+1
    fi

    let INDEX_J=INDEX_J+1
  done

  let INDEX_J=0
  let INDEX_I=INDEX_I+1

done

echo "Sketches compilation results validation against database completed"

let INDEX_I=0
let REPORT_FAILED=0
let REPORT_PASSED=0
let REPORT_UNDEFINED=0

for file_name in $SKETCHES_SOURCE_PATH/*.json; do
  let SKETCH_FAILED=0
  let SKETCH_PASSED=0
  let SKETCH_UNDEFINED=0

  # add validation_result key at board level per each sketches report and set its initial value to pass
  jq '.boards[0] += {"validation_result":"undefined"}' $file_name >> $SKETCHES_SOURCE_PATH/modified-report.json
  mv $SKETCHES_SOURCE_PATH/modified-report.json $file_name

  num_sketches_per_board=$(jq ".boards[0].sketches | length" "$file_name")
  echo "Num sketches per board = $num_sketches_per_board"

  #iterate over all the sketches of that board and check which compilations failed
  while [ $INDEX_I -lt $num_sketches_per_board ]; do
    sketch_validation_result=$(cat "$file_name" | jq ".boards[0].sketches[$INDEX_I].validation_result")

    if [ $sketch_validation_result == \"fail\" ]; then
      let SKETCH_FAILED+=1

    elif [ $sketch_validation_result == \"undefined\" ]; then
      let SKETCH_UNDEFINED+=1

    elif [ $sketch_validation_result == \"pass\" ]; then
      let SKETCH_PASSED+=1

    else
      echo "ERROR: Invalid sketch_validation_result $sketch_validation_result in $file_name"
      exit 1
    fi

  done

  echo "Validation report of $file_name:"
  echo "UNDEFINED sketches: $SKETCH_UNDEFINED/$num_sketches_per_board"
  echo "PASSED    sketches: $SKETCH_PASSED/$num_sketches_per_board"
  echo "FAILED    sketches: $SKETCH_FAILED/$num_sketches_per_board"

  if [ $SKETCH_UNDEFINED -ge 1 ]; then
    echo "Global validation status of $file_name is UNDEFINED"
    jq '.boards[0] += {"validation_result":"undefined"}' $file_name >> $SKETCHES_SOURCE_PATH/modified-report.json
    mv $SKETCHES_SOURCE_PATH/modified-report.json $file_name
    let REPORT_UNDEFINED+=1

  else
    if [ $SKETCH_PASSED == $num_sketches_per_board ]; then
      echo "Global validation status of $file_name is PASS"
      jq '.boards[0] += {"validation_result":"pass"}' $file_name >> $SKETCHES_SOURCE_PATH/modified-report.json
      mv $SKETCHES_SOURCE_PATH/modified-report.json $file_name
      let REPORT_PASSED+=1

    else
      echo "Global validation status of $file_name is FAIL"
      jq '.boards[0] += {"validation_result":"fail"}' $file_name >> $SKETCHES_SOURCE_PATH/modified-report.json
      mv $SKETCHES_SOURCE_PATH/modified-report.json $file_name
      let REPORT_FAILED+=1
    fi
  fi

done

echo "Updating validation results for $FULL_SKETCHES_REPORT_PATH..."

if test -f "$FULL_SKETCHES_REPORT_PATH"; then
    rm "$FULL_SKETCHES_REPORT_PATH"
fi

echo "Merging the modified board-related json files from the last compilation into a single report"
jq -s '.[0].boards=([.[].boards]|flatten)|.[0]' $SKETCHES_SOURCE_PATH/*.json >> "$FULL_SKETCHES_REPORT_PATH"

echo "Validation report of $FULL_SKETCHES_REPORT_PATH:"
echo "UNDEFINED sketches: $REPORT_UNDEFINED/$num_boards_sketches_report"
echo "PASSED    sketches: $REPORT_PASSED/$num_boards_sketches_report"
echo "FAILED    sketches: $REPORT_FAILED/$num_boards_sketches_report"

if [ $REPORT_UNDEFINED -ge 1 ]; then
  echo "Global validation status of $FULL_SKETCHES_REPORT_PATH is UNDEFINED"
  jq '. += {"validation_result":"undefined"}' $FULL_SKETCHES_REPORT_PATH >> $SKETCHES_SOURCE_PATH/modified-report.json
  mv $SKETCHES_SOURCE_PATH/modified-report.json $FULL_SKETCHES_REPORT_PATH

else
  if [ $REPORT_PASSED == $num_sketches_per_board ]; then
    echo "Global validation status of $FULL_SKETCHES_REPORT_PATH is PASS"
    jq '. += {"validation_result":"pass"}' $FULL_SKETCHES_REPORT_PATH >> $SKETCHES_SOURCE_PATH/modified-report.json
    mv $SKETCHES_SOURCE_PATH/modified-report.json $FULL_SKETCHES_REPORT_PATH

  else
    echo "Global validation status of $FULL_SKETCHES_REPORT_PATH is FAIL"
    jq '.boards[0] += {"validation_result":"fail"}' $FULL_SKETCHES_REPORT_PATH >> $SKETCHES_SOURCE_PATH/modified-report.json
    mv $SKETCHES_SOURCE_PATH/modified-report.json $FULL_SKETCHES_REPORT_PATH
  fi
fi

if [ $SKETCH_FAILED -ge 1 ]; then
  echo "" 
  echo "Total number of sketches that failed the validation against the database: $SKETCH_FAILED"
  exit 1
elif [ $SKETCH_NOT_IN_DATABASE -ge 1 ]; then
  echo "$SKETCH_NOT_IN_DATABASE sketches that failed are not present in the database."
  exit 1
else
  echo "Failure check completed successfully!"
  exit 0
fi
