#!/usr/bin/env bats

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-mock/stub.bash

# We assume the query binary is already built at this point.
# Where to find it?
: ${QUERY_PATH:="query"}
[ -x ${QUERY_PATH} ] || (echo "no query binary found at '${QUERY_PATH}'" && exit 1)

@test 'missing input variables' {
    run ${QUERY_PATH}
    assert_equal $status 1
    assert_output --partial "DB Host unset"

    export DBR_HOST=a
    run ${QUERY_PATH}
    assert_equal $status 1
    assert_output --partial "DB User unset"

    export DBR_USER=a
    run ${QUERY_PATH}
    assert_equal $status 1
    assert_output --partial "DB Password unset"

    export DBR_PASS=a
    run ${QUERY_PATH}
    assert_equal $status 1
    assert_output --partial "DB Query unset"
}

@test 'missing sqlplus binary' {
    export DBR_HOST=a DBR_USER=a DBR_PASS=a DBR_QUERY=a
    run ${QUERY_PATH}
    assert_equal $status 1
    assert_output --partial '"sqlplus": executable file not found in $PATH'

    export DBR_SQLPLUS_PATH=fake
    run ${QUERY_PATH}
    assert_equal $status 1
    assert_output --partial '"fake": executable file not found in $PATH'
}

@test 'happy path' {
    export DBR_HOST=host DBR_USER=user DBR_PASS=pass DBR_QUERY=query
    stub sqlplus 'user@host : echo -e "Enter password:\nSQL>\ntotally worked"'
    run ${QUERY_PATH}
    assert_equal $status 0
    assert_output --partial '> query'
    assert_output --partial 'totally worked'
    unstub sqlplus
}

@test 'login timeout' {
    [ -z "${TEST_SLOW_PATH:-}" ] && skip "slow path disabled"
    export DBR_HOST=host DBR_USER=user DBR_PASS=pass DBR_QUERY=query
    stub sqlplus 'user@host : echo -e "nothing"'
    run ${QUERY_PATH}
    assert_equal $status 1
    assert_output --partial "time-out waiting for 'Enter password:'"
}

@test 'sql prompt timeout' {
    [ -z "${TEST_SLOW_PATH:-}" ] && skip "slow path disabled"
    export DBR_HOST=host DBR_USER=user DBR_PASS=pass DBR_QUERY=query
    stub sqlplus 'user@host : echo -e "Enter password:\n"'
    run ${QUERY_PATH}
    assert_equal $status 1
    assert_output --partial "time-out waiting for 'SQL>'"
}

@test 'captures error output' {
    export DBR_HOST=host DBR_USER=user DBR_PASS=pass DBR_QUERY=queryi
    stub sqlplus 'user@host : echo -e "Enter password:\nSQL>\nORA-0123: oopsie"'
    run ${QUERY_PATH}
    assert_equal $status 1
    assert_output --partial '1 error occurred during SQL execution'
    unstub sqlplus

    stub sqlplus 'user@host : echo -e "Enter password:\nSQL>\nSP2-0123: oopsie"'
    run ${QUERY_PATH}
    assert_equal $status 1
    assert_output --partial '1 error occurred during SQL execution'
    unstub sqlplus

    stub sqlplus 'user@host : echo -e "Enter password:\nSQL>\nORA-0123: oopsie\nSP2-0123: oopsie"'
    run ${QUERY_PATH}
    assert_equal $status 1
    assert_output --partial '2 errors occurred during SQL execution'
    unstub sqlplus
}
