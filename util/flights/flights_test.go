package flights

import (
	"encoding/json"
	"testing"
)

func TestData_String(t *testing.T) {
	tests := []struct {
		name     string
		data     Data
		expected string
	}{
		{
			name: "Full data with offsets",
			data: Data{
				Status: "Expected",
				Number: "UA 2402",
				Airline: struct {
					Name string `json:"name"`
				}{Name: "United Airlines"},
				Aircraft: struct {
					Model string `json:"model"`
				}{Model: "Boeing 737 MAX 9"},
				Departure: FlightEndpoint{
					Airport: Airport{Name: "Houston George Bush", IATA: "IAH"},
					ScheduledTime: TimeInfo{Utc: "2026-05-28 14:51Z"},
					RevisedTime:   TimeInfo{Utc: "2026-05-28 14:51Z"},
					Terminal:      "C",
				},
				Arrival: FlightEndpoint{
					Airport: Airport{Name: "Newark Liberty", IATA: "EWR"},
					ScheduledTime: TimeInfo{Utc: "2026-05-28 18:30Z"},
					RevisedTime:   TimeInfo{Utc: "2026-05-28 17:45Z"},
					Terminal:      "A",
				},
			},
			expected: "United Airlines flight UA 2402 (Boeing 737 MAX 9) from Houston George Bush (IAH) terminal C to Newark Liberty (EWR) terminal A is Expected. Dep: 14:51 Arr: 18:30 (-45m)",
		},
		{
			name: "No revised times",
			data: Data{
				Status: "Scheduled",
				Number: "BA 123",
				Airline: struct {
					Name string `json:"name"`
				}{Name: "British Airways"},
				Departure: FlightEndpoint{
					Airport: Airport{Name: "Heathrow", IATA: "LHR"},
					ScheduledTime: TimeInfo{Utc: "2026-05-28 10:00Z"},
				},
				Arrival: FlightEndpoint{
					Airport: Airport{Name: "JFK", IATA: "JFK"},
					ScheduledTime: TimeInfo{Utc: "2026-05-28 18:00Z"},
				},
			},
			expected: "British Airways flight BA 123 from Heathrow (LHR) to JFK (JFK) is Scheduled. Dep: 10:00 Arr: 18:00",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			actual := tt.data.String()
			if actual != tt.expected {
				t.Errorf("Expected:\n%s\nActual:\n%s", tt.expected, actual)
			}
		})
	}
}

func TestParsing(t *testing.T) {
	jsonData := `[{"status":"Expected","departure":{"airport":{"iata":"IAH","name":"Houston George Bush"},"scheduledTime":{"utc":"2026-05-28 14:51Z"},"revisedTime":{"utc":"2026-05-28 14:51Z"},"terminal":"C"},"arrival":{"airport":{"iata":"EWR","name":"Newark Liberty"},"scheduledTime":{"utc":"2026-05-28 18:30Z"},"revisedTime":{"utc":"2026-05-28 17:45Z"},"terminal":"A"},"number":"UA 2402","airline":{"name":"United Airlines"},"aircraft":{"model":"Boeing 737 MAX 9"}}]`
	var apiResp []Data
	if err := json.Unmarshal([]byte(jsonData), &apiResp); err != nil {
		t.Fatal(err)
	}
	if len(apiResp) != 1 {
		t.Fatalf("Expected 1 result, got %d", len(apiResp))
	}
	if apiResp[0].Number != "UA 2402" {
		t.Errorf("Expected UA 2402, got %s", apiResp[0].Number)
	}
}
