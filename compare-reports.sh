#!/bin/bash

SKETCH_FAILED=0
FOUND_BOARD_IN_DATABASE=0
FOUND_SKETCH_IN_DATABASE=0
ERROR_SKETCH_NOT_IN_DATABASE=0
INDEX_I=0
INDEX_J=0
INDEX_K=0
INDEX_L=0

if [ "$#" -ne 1 ]; then
  echo "Missing SKETCHES_SOURCE_PATH"
  exit 1
fi

SKETCHES_SOURCE_PATH=$1
echo "$SKETCHES_SOURCE_PATH"

if test -f $SKETCHES_SOURCE_PATH/sketches-reports/full-sketches-report.json; then
    rm $SKETCHES_SOURCE_PATH/sketches-reports/full-sketches-report.json
fi

find $SKETCHES_SOURCE_PATH -maxdepth 1

echo "Merging the board-related json files from the last compilation into a single report"
jq -s '.[0].boards=([.[].boards]|flatten)|.[0]' $SKETCHES_SOURCE_PATH/sketches-reports/*.json >> $SKETCHES_SOURCE_PATH/sketches-reports/full-sketches-report.json

echo "Computing the total number of boards from full-sketches-report.json"
num_boards_sketches_report=$(jq '.boards | length' $SKETCHES_SOURCE_PATH/sketches-reports/full-sketches-report.json)
echo $num_boards_sketches_report

echo "Computing the total number of boards from full-database-report.json"
num_boards_database_report=$(jq '.boards | length' $SKETCHES_SOURCE_PATH/database-reports/full-database-report.json)
echo $num_boards_database_report


#First iteration over the number of boards used in the current compilation
while [ $INDEX_I -lt $num_boards_sketches_report ]; do
  #save the current board name
  board_name=$(cat $SKETCHES_SOURCE_PATH/sketches-reports/full-sketches-report.json | jq ".boards[$INDEX_I].board")
  echo "Current board name: $board_name"
  #compute and save the number of sketches compiled for that board
  num_sketches_per_board=$(jq ".boards[$INDEX_I].sketches | length" $SKETCHES_SOURCE_PATH/sketches-reports/full-sketches-report.json)
  echo "Number of sketches for current board: $num_sketches_per_board"

  #iterate over all the sketches of that board and check which compilations failed
  while [ $INDEX_J -lt $num_sketches_per_board ]; do
    compilation_status=$(cat $SKETCHES_SOURCE_PATH/sketches-reports/full-sketches-report.json | jq ".boards[$INDEX_I].sketches[$INDEX_J].compilation_success")
    if [ $compilation_status == "false" ]; then
      #reset the flags that checks if a board/sketch has been found in the database
      FOUND_BOARD_IN_DATABASE=0
      FOUND_SKETCH_IN_DATABASE=0
      #save the sketch name
      name_failed_sketch=$(cat $SKETCHES_SOURCE_PATH/sketches-reports/full-sketches-report.json | jq ".boards[$INDEX_I].sketches[$INDEX_J].name")

      #iterate over the available boards in the report util the current board is found
      while [ $INDEX_K -lt $num_boards_database_report ]; do
        database_board_name=$(cat $SKETCHES_SOURCE_PATH/database-reports/full-database-report.json | jq ".boards[$INDEX_K].board")
        if [ $database_board_name == $board_name ]; then
          FOUND_BOARD_IN_DATABASE=1
          #compute the number of available sketches in the database for the current board
          num_database_sketches_per_board=$(jq ".boards[$INDEX_K].sketches | length" $SKETCHES_SOURCE_PATH/database-reports/full-database-report.json)

          #iterate over all the database sketches of that board until the one that failed is found
          while [ $INDEX_L -lt $num_database_sketches_per_board ]; do
            database_sketch_name=$(cat $SKETCHES_SOURCE_PATH/database-reports/full-database-report.json | jq ".boards[$INDEX_K].sketches[$INDEX_L].name")
            if [ "$database_sketch_name" == "$name_failed_sketch" ]; then
              #set the related flag
              FOUND_SKETCH_IN_DATABASE=1
              database_compilation_status=$(cat $SKETCHES_SOURCE_PATH/database-reports/full-database-report.json | jq ".boards[$INDEX_K].sketches[$INDEX_L].compilation_success")
              #check the expected results
              if [ "$database_compilation_status" == "true" ]; then
                echo "COMPILATION FAILURE: compilation of sketch $database_sketch_name on board $database_board_name has EXPECTED result $database_compilation_status"
                #increment the number of sketch failed
                let SKETCH_FAILED=SKETCH_FAILED+1
              else
                for file_name in $SKETCHES_SOURCE_PATH/sketches-reports/*.json; do # Whitespace-safe but not recursive.
                  if [ $file_name == "$SKETCHES_SOURCE_PATH/sketches-reports/full-sketches-report.json" ]; then
                    continue
                  else
                    single_file_board_name=$(cat $file_name | jq ".boards[0].board")
                    if [ "$board_name" == "$single_file_board_name" ]; then
                      jq ".boards[0].sketches[$INDEX_J].compilation_success = "true"" $file_name >> $SKETCHES_SOURCE_PATH/sketches-reports/modified-report.json
                      mv $SKETCHES_SOURCE_PATH/sketches-reports/modified-report.json $file_name
                    fi
                  fi
                done
                echo "Ignore compilation failure: compilation of sketch $database_sketch_name on board $database_board_name has EXPECTED result $database_compilation_status"
              fi
              break
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
        let ERROR_SKETCH_NOT_IN_DATABASE=1
      fi

    fi
    let INDEX_J=INDEX_J+1
  done
  let INDEX_J=0
  let INDEX_I=INDEX_I+1
done

if [ $SKETCH_FAILED -ge 1 ]; then
  echo "$SKETCH_FAILED SKETCHES FAILED!"
  exit 1
elif [ $ERROR_SKETCH_NOT_IN_DATABASE == 1 ]; then
  echo "One or more sketches that failed are not present in the database."
  exit 1
else
  echo "Failure check completed successfully!"
  exit 0
fi
