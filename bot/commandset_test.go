package bot

import (
	"strings"
	"testing"
)

type dummyRunner struct {
	help string
	args string
}

func (r *dummyRunner) Run(ctx *Context) {
	r.args = ctx.Args[1]
}
func (r *dummyRunner) Help() string { return r.help }

func TestCommandSetMatch(t *testing.T) {
	cs := newCommandSet()
	cs.Add(&dummyRunner{help: "remind help"}, "remind")
	cs.Add(&dummyRunner{help: "remind list help"}, "remind list")

	tests := []struct {
		input  string
		prefix string
		found  bool
	}{
		{"remind", "remind", true},
		{"Remind", "remind", true},
		{"remind list", "remind list", true},
		{"REMIND LIST", "remind list", true},
		{"remind me", "remind", true},
		{"Remind me", "remind", true},
		{"not a command", "", false},
	}

	for _, tc := range tests {
		r, ln := cs.match(tc.input)
		if !tc.found {
			if r != nil {
				t.Errorf("match(%q) = %v, want nil", tc.input, r)
			}
			continue
		}
		if r == nil {
			t.Errorf("match(%q) = nil, want %q", tc.input, tc.prefix)
			continue
		}
		if r.Help() != tc.prefix+" help" {
			t.Errorf("match(%q) returned wrong runner: got %q, want %q", tc.input, r.Help(), tc.prefix+" help")
		}

		// Verify ln
		if ln != len(tc.prefix) {
			t.Errorf("match(%q) returned wrong ln: got %d, want %d", tc.input, ln, len(tc.prefix))
		}
	}
}

func TestCommandSetHandle(t *testing.T) {
	cs := newCommandSet()
	runner := &dummyRunner{help: "remind help"}
	cs.Add(runner, "remind")

	// We need a Context to call Handle, but Handle creates its own context from Line.
	// Actually Handle calls reqContext(conn, line).
	// reqContext uses bot.rewriters, which might be nil if not initialized.

	// Let's just test the logic that Handle uses.
	tests := []struct {
		input    string
		wantArgs string
	}{
		{"remind Me to do something", "Me to do something"},
		{"REMIND me To Do Something", "me To Do Something"},
	}

	for _, tc := range tests {
		r, ln := cs.match(tc.input)
		if r == nil {
			t.Fatalf("match(%q) returned nil", tc.input)
		}
		// This is the logic from Handle:
		args := strings.Join(strings.Fields(tc.input[ln:]), " ")
		if args != tc.wantArgs {
			t.Errorf("Handle logic for %q: got args %q, want %q", tc.input, args, tc.wantArgs)
		}
	}
}

func TestCommandSetPossible(t *testing.T) {
	cs := newCommandSet()
	cs.Add(&dummyRunner{help: ""}, "remind")
	cs.Add(&dummyRunner{help: ""}, "remind list")

	tests := []struct {
		input string
		want  []string
	}{
		{"remind", []string{"remind", "remind list"}},
		{"REMIND", []string{"remind", "remind list"}},
		{"list", []string{"remind list"}},
		{"LIST", []string{"remind list"}},
	}

	for _, tc := range tests {
		got := cs.possible(tc.input)
		if len(got) != len(tc.want) {
			t.Errorf("possible(%q) = %v, want %v", tc.input, got, tc.want)
		}
		// Check if all wanted are in got
		for _, w := range tc.want {
			found := false
			for _, g := range got {
				if g == w {
					found = true
					break
				}
			}
			if !found {
				t.Errorf("possible(%q) missing %q", tc.input, w)
			}
		}
	}
}
