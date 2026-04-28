package seen

import (
	"testing"
	"time"

	"github.com/fluffle/sp0rkle/bot"
	"github.com/fluffle/sp0rkle/db"
	"github.com/fluffle/sp0rkle/util/bson"
)

func TestNick_Indexes_BsonRoundtrip(t *testing.T) {
	original := time.Date(2024, 7, 15, 12, 30, 45, 123456789, time.UTC)

	tests := []struct {
		name string
		nick *Nick
	}{
		{
			name: "nanosecond precision timestamp survives bson roundtrip",
			nick: &Nick{
				Nick:      bot.Nick("testnick"),
				Chan:      bot.Chan("#test"),
				Timestamp: original,
				Key:       "testnick",
				Action:    "PRIVMSG",
				Text:      "hello world",
				Id_:       bson.NewObjectId(),
			},
		},
		{
			name: "zero timestamp",
			nick: &Nick{
				Nick:      bot.Nick("testnick"),
				Chan:      bot.Chan("#test"),
				Timestamp: time.Time{},
				Key:       "testnick",
				Action:    "JOIN",
				Text:      "",
				Id_:       bson.NewObjectId(),
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			originalKeys := tt.nick.Indexes()

			data, err := bson.Marshal(tt.nick)
			if err != nil {
				t.Fatalf("bson.Marshal: %v", err)
			}
			roundtripped := &Nick{Id_: tt.nick.Id_}
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
