package reminders

import (
	"testing"
	"time"

	"github.com/fluffle/sp0rkle/bot"
	"github.com/fluffle/sp0rkle/db"
	"github.com/fluffle/sp0rkle/util/bson"
)

func TestReminder_Indexes_BsonRoundtrip(t *testing.T) {
	originalRemindAt := time.Date(2024, 7, 15, 12, 30, 45, 123456789, time.UTC)
	originalCreated := time.Date(2024, 7, 15, 10, 0, 0, 987654321, time.UTC)

	tests := []struct {
		name     string
		reminder *Reminder
	}{
		{
			name: "normal reminder with nanosecond precision",
			reminder: &Reminder{
				Source:   bot.Nick("alice"),
				Target:   bot.Nick("bob"),
				Chan:     bot.Chan("#test"),
				From:     "alice",
				To:       "bob",
				Reminder: "buy milk",
				Created:  originalCreated,
				RemindAt: originalRemindAt,
				Tell:     false,
				Id_:      bson.NewObjectId(),
			},
		},
		{
			name: "tell uses Created timestamp",
			reminder: &Reminder{
				Source:   bot.Nick("alice"),
				Target:   bot.Nick("bob"),
				Chan:     bot.Chan("#test"),
				From:     "alice",
				To:       "bob",
				Reminder: "hello",
				Created:  originalCreated,
				RemindAt: time.Time{},
				Tell:     true,
				Id_:      bson.NewObjectId(),
			},
		},
		{
			name: "self-reminder",
			reminder: &Reminder{
				Source:   bot.Nick("alice"),
				Target:   bot.Nick("alice"),
				Chan:     bot.Chan("#test"),
				From:     "alice",
				To:       "alice",
				Reminder: "take vitamins",
				Created:  originalCreated,
				RemindAt: originalRemindAt,
				Tell:     false,
				Id_:      bson.NewObjectId(),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			originalKeys := tt.reminder.Indexes()

			data, err := bson.Marshal(tt.reminder)
			if err != nil {
				t.Fatalf("bson.Marshal: %v", err)
			}
			roundtripped := &Reminder{Id_: tt.reminder.Id_}
			if err := bson.Unmarshal(data, roundtripped); err != nil {
				t.Fatalf("bson.Unmarshal: %v", err)
			}

			roundtrippedKeys := roundtripped.Indexes()

			if len(originalKeys) != len(roundtrippedKeys) {
				t.Fatalf("key count mismatch: original=%d, roundtripped=%d",
					len(originalKeys), len(roundtrippedKeys))
			}
			for i := range originalKeys {
				origElems, origLast := originalKeys[i].(db.K).B()
				rtElems, rtLast := roundtrippedKeys[i].(db.K).B()
				// Build full key for comparison
				origFull := append(origElems, origLast)
				rtFull := append(rtElems, rtLast)
				for j := range origFull {
					if string(origFull[j]) != string(rtFull[j]) {
						t.Errorf("index key[%d] element[%d] mismatch after BSON roundtrip:\n  original:     %q\n  roundtripped: %q",
							i, j, origFull[j], rtFull[j])
					}
				}
			}
		})
	}
}
