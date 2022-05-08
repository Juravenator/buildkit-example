package main

import (
	"bytes"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestCheckForErrors(t *testing.T) {
	assert := assert.New(t)

	var tests = []struct {
		name  string
		input string
		want  uint
	}{
		{"", "empty input", 0},
		{"no errors", "no errors at all", 0},
		{"ORA error", "ORA-1234: some error", 1},
		{"SP2 error", "SP2-1234: some error", 1},
		{"multiple errors", "ORA-1234: some error\nSP2-0000: some other error", 2},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := check_for_errors(*bytes.NewBuffer([]byte(tt.input)))
			assert.Equal(tt.want, got, "error count should match")
		})
	}

}
