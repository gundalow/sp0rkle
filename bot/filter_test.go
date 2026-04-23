package bot

import (
	"strings"
	"testing"
	"github.com/fluffle/goirc/client"
)

func TestFilterPipeline(t *testing.T) {
	p := &FilterPipeline{}
	p.AddFunc(
		func (line *client.Line) bool {
			return strings.Contains(line.Raw, "PRIVMSG")
		},
		func (line *client.Line) bool {
			return strings.Contains(line.Raw, "hello")
		},
	)

	tests := []struct {
		line string
		want bool
	} {
		{"", false},
		{"neither", false},
		{"PRIVMSG :only one", false},
		{"OTHER :hello", false},
		{"PRIVMSG #channel :hello", true},
	}

	for _, test := range tests {
		got := p.ShouldProcess(&client.Line{Raw: test.line})
		if got != test.want {
			t.Errorf("ShouldProcess(%q) = %t, want %t", test.line, got, test.want)
		}
	}
}
