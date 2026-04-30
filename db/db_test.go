package db

import (
	"bytes"
	"encoding/binary"
	"strings"
	"testing"
	"time"

	"github.com/fluffle/sp0rkle/util/datetime"
)

func serializeTime(name string, val time.Time) []byte {
	buf := bytes.NewBuffer(make([]byte, 0, len(name) + 9))
	buf.WriteString(name)
	buf.WriteByte(USEP)
	if err := binary.Write(buf, binary.BigEndian, uint64(val.UnixMilli())); err != nil {
		panic(err)
	}
	return buf.Bytes()
}

func TestTS_Bytes(t *testing.T) {
	tests := []struct {
		name    string
		ms      TS
		want    []byte
		wantPairName string
		wantPairVal  uint64
	}{
	{
			name: "truncates nanoseconds to milliseconds",
			ms:   TS{Name: "ts", Value: time.Date(2024, 7, 15, 12, 30, 45, 123456789, time.UTC)},
			want: serializeTime("ts", time.Date(2024, 7, 15, 12, 30, 45, 123000000, time.UTC)),
			wantPairName: "ts",
			wantPairVal:  uint64(time.Date(2024, 7, 15, 12, 30, 45, 123000000, time.UTC).UnixMilli()),
		},
		{
			name: "exact millisecond boundary (no truncation needed)",
			ms:   TS{Name: "ts", Value: time.Date(2024, 7, 15, 12, 30, 45, 555000000, time.UTC)},
			want: serializeTime("ts", time.Date(2024, 7, 15, 12, 30, 45, 555000000, time.UTC)),
			wantPairName: "ts",
			wantPairVal:  uint64(time.Date(2024, 7, 15, 12, 30, 45, 555000000, time.UTC).UnixMilli()),
		},
		{
			name: "epoch-precise timestamp",
			ms:   TS{Name: "ts", Value: time.Unix(0, 0).UTC()},
			want: serializeTime("ts", time.Unix(0, 0).UTC()),
			wantPairName: "ts",
			wantPairVal:  0,
		},
		{
			name: "zero time produces known timestamp",
			ms:   TS{Name: "created", Value: time.Time{}},
			want: serializeTime("created", time.Time{}),
			wantPairName: "created",
			wantPairVal:  uint64(18446681938112751616),
		},
		{
			name: "negative timestamps (before epoch)",
			ms:   TS{Name: "ts", Value: time.Date(1970, 1, 1, 0, 0, -1, 500000000, time.UTC)},
			want: serializeTime("ts", time.Date(1970, 1, 1, 0, 0, -1, 500000000, time.UTC)),
			wantPairName: "ts",
			wantPairVal:  uint64(time.Date(1970, 1, 1, 0, 0, -1, 500000000, time.UTC).UnixMilli()),
		},
	}

		for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.ms.Bytes()
			if !bytes.Equal(got, tt.want) {
				t.Errorf("MS.Bytes() = %q, want %q", got, tt.want)
			}
			name, val := tt.ms.Pair()
			if name != tt.wantPairName {
				t.Errorf("MS.Pair() name = %q, want %q", name, tt.wantPairName)
			}
			gotVal, ok := val.(uint64)
			if !ok {
				t.Errorf("MS.Pair() value type = %T, want uint64", val)
			}
			if gotVal != tt.wantPairVal {
				t.Errorf("MS.Pair() value = %v, want %v", val, tt.wantPairVal)
			}
		})
	}
}

func TestTS_String(t *testing.T) {
	ts := time.Date(2024, 7, 15, 12, 30, 45, 0, time.UTC)
	tests := []struct {
		name string
		ms   TS
		want string
	}{
		{
			name: "formats name and default datetime value",
			ms:   TS{Name: "ts", Value: ts},
			want: "ts: " + datetime.Format(ts.UTC()),
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := tt.ms.String()
			if got != tt.want {
				t.Errorf("MS.String() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestTS_BytesMatchesI(t *testing.T) {
	// Verify that TS produces the same bytes as I with manual UnixMilli truncation.
	// This is the key invariant: TS must be a drop-in replacement for I{UnixMilli}.
	tm := time.Date(2024, 7, 15, 12, 30, 45, 999999999, time.UTC)
	ts := TS{Name: "ts", Value: tm}
	i := I{Name: "ts", Value: uint64(tm.UnixMilli())}

	if !bytes.Equal(ts.Bytes(), i.Bytes()) {
		t.Errorf("TS.Bytes() = %q, but I.Bytes() = %q — they must match", ts.Bytes(), i.Bytes())
	}
}

func TestK_Valid(t *testing.T) {
	tests := []struct {
		name    string
		key     K
		wantErr bool
		errMsg  string
	}{
		{
			name:    "empty key is valid",
			key:     K{},
			wantErr: false,
		},
		{
			name:    "valid string elements",
			key:     K{S{"key", "value"}, S{"ns", "channel"}},
			wantErr: false,
		},
		{
			name:    "valid string with USEP in value",
			key:     K{S{"key", "val\x1fue"}},
			wantErr: false,
		},
		{
			name:    "valid integer element",
			key:     K{I{"count", 42}},
			wantErr: false,
		},
		{
			name:    "valid boolean element",
			key:     K{T{"flag", true}},
			wantErr: false,
		},
		{
			name:    "USEP in string name",
			key:     K{S{"na\x1fme", "value"}},
			wantErr: true,
			errMsg:  "name contains USEP",
		},
		{
			name:    "USEP in second element name",
			key:     K{S{"first", "ok"}, S{"sec\x1fond", "value"}},
			wantErr: true,
			errMsg:  "name contains USEP",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.key.Valid()
			if tt.wantErr {
				if err == nil {
					t.Errorf("K.Valid() expected error, got nil")
					return
				}
				if !strings.Contains(err.Error(), tt.errMsg) {
					t.Errorf("K.Valid() error = %q, want substring %q", err.Error(), tt.errMsg)
				}
			} else {
				if err != nil {
					t.Errorf("K.Valid() unexpected error: %v", err)
				}
			}
		})
	}
}
