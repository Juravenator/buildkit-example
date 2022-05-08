#!/usr/bin/env bats

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-mock/stub.bash

@test 'empty query' {
    run src/assess.sh
    assert_equal $status 1
}

@test 'complex queries' {
    # complex queries to test for
    IFS=$'\n\t\v' complex_queries=(
        "AlTeR TaBlE employees aLtEr CoLuMn salary boolean",
        "select * from users;\nalter table employees;"
    )

    for q in ${complex_queries[@]}; do
        # expect query_is_complex to be set to 1
        stub set_octopusvariable "query_is_complex 1 : "
        
        DBR_QUERY="$q" run src/assess.sh
        assert_equal $status 0

        # check set_octopusvariable hasn't been called with any other args
        unstub set_octopusvariable
    done
}

@test 'violation queries' {
    # queries that should result in a non-zero exit code
    IFS=$'\n\t\v' violation_queries=(
        "drop table employees"
        "alter table employees drop salary"
    )

    for q in ${violation_queries[@]}; do
        # expect a call to set_octopusvariable
        stub set_octopusvariable ""

        DBR_QUERY="$q" run src/assess.sh
        assert_equal $status 1

        unstub set_octopusvariable
    done
}

@test 'not complex queries' {
    # other queries that should not get flagged
    IFS=$'\n\t\v' not_complex_queries=(
        "update employees set salary = 0"
        "select * from creditcards"
    )

    for q in ${not_complex_queries[@]}; do
        # expect query_is_complex to be set to 1
        stub set_octopusvariable "query_is_complex 0 : "
        
        DBR_QUERY="$q" run src/assess.sh
        assert_equal $status 0

        # check set_octopusvariable hasn't been called with any other args
        unstub set_octopusvariable
    done
}