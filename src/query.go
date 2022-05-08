// This code takes DB credentials and SQL code via environment variables, and
// executes it using the 'sqlplus' binary.
// https://stackoverflow.com/a/12797593
// Using sqlplus instead of a library we bypass a bunch of issues like
// - complications when using PL/SQL
// - complications when running multiple queries
// - complications when using line breaks or blank lines

package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/withmandala/go-log"
)

var (
	l                  = log.New(os.Stderr)
	LOGIN_TIMEOUT      = 20 * time.Second
	SQL_PROMPT_TIMEOUT = 20 * time.Second
)

func main() {
	// Set up basic logging (to stderr)
	l.Info("Starting")

	// Get our env variables
	db_host := os.Getenv("DBR_HOST")
	db_user := os.Getenv("DBR_USER")
	db_pass := os.Getenv("DBR_PASS")
	db_script := os.Getenv("DBR_QUERY")
	sqlplus_path := os.Getenv("DBR_SQLPLUS_PATH")
	if sqlplus_path == "" {
		sqlplus_path = "sqlplus"
	}

	// Validate env variables are set
	if db_host == "" {
		l.Fatal("DB Host unset")
	}
	if db_user == "" {
		l.Fatal("DB User unset")
	}
	if db_pass == "" {
		l.Fatal("DB Password unset")
	}
	if db_script == "" {
		l.Fatal("DB Query unset")
	}

	// Declare the sqlplus command to run later
	sqlplus := exec.Command(sqlplus_path, db_user+"@"+db_host)

	// Pass through the stderr/stdout stream to our own stderr/stdout,
	// But also keep a copy of the data. We need to inspect its output.
	var buf_output bytes.Buffer
	sqlplus.Stdout = io.MultiWriter(os.Stdout, &buf_output)
	sqlplus.Stderr = io.MultiWriter(os.Stderr, &buf_output)

	// Take control over the stdin buffer. Needed to send the db password.
	stdin, err := sqlplus.StdinPipe()
	if err != nil {
		l.Fatalf("sqlplus command stdin setup failed: %s\n", err)
	}

	// Start execution
	l.Infof("executing sqlplus command: %s", strings.Join(sqlplus.Args, " "))
	err = sqlplus.Start()
	if err != nil {
		l.Fatalf("sqlplus execution start failed: %s\n", err)
	}

	// Wait for the password prompt, or a timeout
	l.Infof("waiting for login prompt... (max %s)", LOGIN_TIMEOUT)
	err = wait_for_string(&buf_output, "Enter password:", LOGIN_TIMEOUT)
	if err != nil {
		write_empty_line()
		l.Fatalf("error while waiting for password prompt: %s\n", err)
	}
	write_empty_line()

	// Now that we have the password prompt, write the password
	_, _ = stdin.Write([]byte(db_pass + "\n"))

	// Wait for SQL prompt
	l.Infof("waiting for SQL prompt... (max %s)", SQL_PROMPT_TIMEOUT)
	err = wait_for_string(&buf_output, "SQL>", SQL_PROMPT_TIMEOUT)
	if err != nil {
		write_empty_line()
		l.Fatalf("error while waiting for SQL prompt: %s\n", err)
	}
	write_empty_line()

	// Insert SQL script and close the stream
	l.Info("executing SQL script:")
	for _, line := range strings.Split(db_script, "\n") {
		l.Infof("> %s", line)
	}
	_, _ = stdin.Write([]byte(db_script + "\n"))
	stdin.Close()

	// Wait for sqlplus to finish
	done := make(chan error)
	go func() { done <- sqlplus.Wait() }()
	select {
	case err = <-done:
		if err != nil {
			l.Fatalf("failed to gracefully stop sqlplus: %s\n", err)
		}
	case <-time.After(5 * time.Second):
		l.Fatal("time-out waiting for sqlplus to finish")
	}

	if count := check_for_errors(buf_output); count != 0 {
		s := "error"
		if count != 1 {
			s += "s"
		}
		l.Fatalf("%d %s occurred during SQL execution", count, s)
	}
	l.Info("finished")

}

// write a newline to stdout console so new log messages start at a new line
func write_empty_line() {
	_, _ = os.Stdout.Write([]byte("\n"))
}

func wait_for_string(hay *bytes.Buffer, needle string, timeout time.Duration) error {
	result := make(chan error, 1)
	go func() {
		for {
			line, err := hay.ReadString('\n')
			if err == io.EOF {
				time.Sleep(100 * time.Millisecond)
			} else if err != nil {
				result <- err
				return
			}
			if strings.HasPrefix(line, needle) {
				result <- nil
				return
			}
		}
	}()

	select {
	case e := <-result:
		return e
	case <-time.After(timeout):
		return fmt.Errorf("time-out waiting for '%s'", needle)
	}
}

func check_for_errors(buffer bytes.Buffer) uint {
	num_errors := uint(0)
	r := regexp.MustCompile("(ORA|SP2)-[0-9]+:")
	for {
		line, err := buffer.ReadString('\n')
		if err != nil && err != io.EOF {
			l.Fatalf("error while checking for errors: %s", err)
		}
		// check for database (ORA) and sqlplus (SP2) errors in logs
		if match := r.MatchString(line); match {
			num_errors += 1
		}
		// EOF error is returned when the last line has been read
		if err == io.EOF {
			break
		}
	}
	return num_errors
}
