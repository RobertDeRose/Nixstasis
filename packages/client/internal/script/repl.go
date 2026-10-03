// Package script/repl provides a read/eval/print loop for Starlark.
//
// It supports readline-style command editing,
// and interrupts through Control-C.
//
// If an input line can be parsed as an expression,
// the REPL parses and evaluates it and prints its result.
// Otherwise the REPL reads lines until a blank line,
// then tries again to parse the multi-line input as an
// expression. If the input still cannot be parsed as an expression,
// the REPL parses and executes it as a file (a list of statements),
// for side effects.
//
//	source: https://github.com/google/starlark-go/blob/master/repl/repl.go
//

package script

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"

	"github.com/chzyer/readline"
	"go.starlark.net/starlark"
	"go.starlark.net/syntax"
)

const (
	// ANSI Escape Codes.
	reset  = "\033[0m"
	bold   = "\033[1m"
	cyan   = "\033[36m"
	green  = "\033[32m"
	purple = "\033[35m"

	promptMain = bold + purple + "✨ " + cyan + "stary " + green + "» " + reset
	promptMult = bold + purple + "       ... " + reset
)

var (
	indent      = []rune("  ")
	interrupted = make(chan os.Signal, 1)
)

// REPLOptions executes a read, eval, print loop.
//
// Before evaluating each expression, it sets the Starlark thread local
// variable named "context" to a context.Context that is canceled by a
// SIGINT (Control-C). Client-supplied global functions may use this
// context to make long-running operations interruptible.
func REPLOptions(opts *syntax.FileOptions, thread *starlark.Thread, globals starlark.StringDict) {
	signal.Notify(interrupted, os.Interrupt)
	defer signal.Stop(interrupted)

	// 1. Setup History (XDG-compliant)
	baseDir, err := os.UserConfigDir()
	if err != nil {
		PrintError(fmt.Errorf("failed to resolve config dir: %w", err))
		baseDir = os.TempDir()
	}
	appDir := filepath.Join(baseDir, "nixstasis")
	if err := os.MkdirAll(appDir, 0o0750); err != nil {
		PrintError(fmt.Errorf("failed to create history dir: %w", err))
	}
	historyFile := filepath.Join(appDir, "repl.history")

	rl, err := readline.NewEx(&readline.Config{
		Prompt:            promptMain,
		HistoryFile:       historyFile,
		HistorySearchFold: true,
	})
	if err != nil {
		PrintError(err)
		return
	}
	defer func() {
		if err := rl.Close(); err != nil {
			PrintError(err)
		}
	}()
	rl.Config.SetListener(func(line []rune, pos int, key rune) (newLine []rune, newPos int, ok bool) {
		if key == readline.CharTab {
			// 2. IMPORTANT: 'line' includes the '\t' character already.
			// If you hit Tab at the end of the line, '\t' is at pos-1.
			// We remove it by slicing it out.

			// This assumes the tab was the last character typed:
			newPos := pos - 1
			indentSize := len(indent)
			cleanLine := make([]rune, 0, len(line)-1)
			cleanLine = append(cleanLine, line[:newPos]...)
			cleanLine = append(cleanLine, line[pos:]...)

			// 3. Rebuild the line with only spaces
			n := make([]rune, 0, len(cleanLine)+indentSize)
			n = append(n, cleanLine[:newPos]...)
			n = append(n, indent...)
			n = append(n, cleanLine[newPos:]...)

			// 4. Return 'true' to tell readline to overwrite its buffer
			return n, newPos + indentSize, true
		}
		return nil, 0, false
	})

	for {
		if err := rep(opts, rl, thread, globals); err != nil {
			if errors.Is(err, readline.ErrInterrupt) {
				fmt.Println(err)
				continue
			}
			break
		}
	}
}

// rep reads, evaluates, and prints one item.
//
// It returns an error (possibly readline.ErrInterrupt)
// only if readline failed. Starlark errors are printed.
func rep(opts *syntax.FileOptions, rl *readline.Instance, thread *starlark.Thread, globals starlark.StringDict) error {
	// Each item gets its own context,
	// which is canceled by a SIGINT.
	//
	// Note: during Readline calls, Control-C causes Readline to return
	// ErrInterrupt but does not generate a SIGINT.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() {
		select {
		case <-interrupted:
			cancel()
		case <-ctx.Done():
		}
	}()

	thread.SetLocal("context", ctx)

	eof := false

	// readline returns EOF, ErrInterrupted, or a line including "\n".
	rl.SetPrompt(promptMain)
	readLineFn := func() ([]byte, error) {
		line, err := rl.Readline()
		rl.SetPrompt(promptMult)
		if err != nil {
			if errors.Is(err, io.EOF) {
				eof = true
			}
			return nil, err
		}
		return []byte(line + "\n"), nil
	}

	// Treat load bindings as global (like they used to be) in the REPL.
	// Fixes github.com/google/starlark-go/issues/224.
	opts2 := *opts
	opts2.LoadBindsGlobally = true
	opts = &opts2

	// parse
	f, err := opts.ParseCompoundStmt("<stdin>", readLineFn)
	if err != nil {
		if eof {
			return io.EOF
		}
		PrintError(err)
		return nil
	}

	if expr := soleExpr(f); expr != nil {
		// eval
		v, err := starlark.EvalExprOptions(f.Options, thread, expr, globals)
		if err != nil {
			PrintError(err)
			return nil
		}

		// store the result in "_" variable to hold the value of last expression, similar to Python REPL
		globals["_"] = v

		// print
		if v != starlark.None {
			fmt.Println(v)
		}
	} else if err := starlark.ExecREPLChunk(f, thread, globals); err != nil {
		PrintError(err)
		return nil
	}

	return nil
}

func soleExpr(f *syntax.File) syntax.Expr {
	if len(f.Stmts) == 1 {
		if stmt, ok := f.Stmts[0].(*syntax.ExprStmt); ok {
			return stmt.X
		}
	}
	return nil
}

// PrintError prints the error to stderr,
// or its backtrace if it is a Starlark evaluation error.
func PrintError(err error) {
	evalErr := &starlark.EvalError{}
	if errors.As(err, &evalErr) {
		fmt.Fprintln(os.Stderr, evalErr.Backtrace())
	} else {
		fmt.Fprintln(os.Stderr, err)
	}
}

// MakeLoadOptions returns a simple sequential implementation of module loading
// suitable for use in the REPL.
// Each function returned by MakeLoadOptions accesses a distinct private cache.
func MakeLoadOptions(opts *syntax.FileOptions) func(thread *starlark.Thread, module string) (starlark.StringDict, error) {
	type entry struct {
		globals starlark.StringDict
		err     error
	}

	cache := make(map[string]*entry)

	return func(thread *starlark.Thread, module string) (starlark.StringDict, error) {
		e, ok := cache[module]
		if e == nil {
			if ok {
				// request for package whose loading is in progress
				return nil, fmt.Errorf("cycle in load graph")
			}

			// Add a placeholder to indicate "load in progress".
			cache[module] = nil

			// Load it.
			thread := &starlark.Thread{Name: "exec " + module, Load: thread.Load}
			globals, err := starlark.ExecFileOptions(opts, thread, module, nil, nil)
			e = &entry{globals, err}

			// Update the cache.
			cache[module] = e
		}
		return e.globals, e.err
	}
}
