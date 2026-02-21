package datetime

import (
	"testing"
	"time"
)

func TestFutureBias(t *testing.T) {
	// Base date: Wed 20th March 2024
	now := time.Date(2024, 3, 20, 12, 0, 0, 0, time.UTC)

	tests := []struct {
		in  string
		exp time.Time
	}{
		// Past date this year should be next year
		{"March 1st", time.Date(2025, 3, 1, 12, 0, 0, 0, time.UTC)},
		{"1st January", time.Date(2025, 1, 1, 12, 0, 0, 0, time.UTC)},
		{"15/3", time.Date(2025, 3, 15, 12, 0, 0, 0, time.UTC)},

		// Future date this year should stay this year
		{"March 25th", time.Date(2024, 3, 25, 12, 0, 0, 0, time.UTC)},
		{"December 25th", time.Date(2024, 12, 25, 12, 0, 0, 0, time.UTC)},

		// Absolute months
		{"January", time.Date(2025, 1, 20, 12, 0, 0, 0, time.UTC)},
		{"December", time.Date(2024, 12, 20, 12, 0, 0, 0, time.UTC)},

		// Specified year should NOT be biased
		{"1st March 2024", time.Date(2024, 3, 1, 12, 0, 0, 0, time.UTC)},
		{"March 1st, 2024", time.Date(2024, 3, 1, 12, 0, 0, 0, time.UTC)},

		// Times in the past should NOT be biased by the parser (driver handles it)
		{"10:00", time.Date(2024, 3, 20, 10, 0, 0, 0, time.UTC)},

		// 3rd Tuesday of the month (past this month)
		// Base date: March 20th 2024 (Wed)
		// 1st Tue: Mar 5, 2nd Tue: Mar 12, 3rd Tue: Mar 19 (passed)
		{"3rd Tuesday", time.Date(2025, 3, 18, 12, 0, 0, 0, time.UTC)},
	}

	for _, test := range tests {
		res, err := parseX(test.in, now)
		got := res.Time
		if err != nil {
			t.Errorf("parse(%q) error: %v", test.in, err)
			continue
		}
		if !got.Equal(test.exp) {
			t.Errorf("parse(%q) = %v, want %v", test.in, got, test.exp)
		}
	}
}
