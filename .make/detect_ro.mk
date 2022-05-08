# Detect if our current filesystem is readonly
RO_TEST_FILE ?= .ro_test
PWD_IS_RO := $(shell (touch ${RO_TEST_FILE} && rm ${RO_TEST_FILE}) 2> /dev/null && echo "0" || echo "1")

ifeq (${PWD_IS_RO},0)
	WRITEABLE_PATH := ${CURDIR}
else
	WRITEABLE_PATH := /tmp
endif
