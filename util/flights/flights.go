package flights

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/fluffle/goirc/logging"
)

const (
	apiBase = "https://aerodatabox.p.rapidapi.com/flights/number"
	rapidAPIHost = "aerodatabox.p.rapidapi.com"
)

var aerodataboxAPIKey = flag.String("aerodatabox_api_key", "",
	"API key for AeroDataBox (RapidAPI).")

func Enabled() bool {
	return *aerodataboxAPIKey != ""
}

// AeroDataBox API structs
type TimeInfo struct {
	Utc   string `json:"utc"`
	Local string `json:"local"`
}

type Airport struct {
	IATA string `json:"iata"`
	ICAO string `json:"icao"`
	Name string `json:"name"`
}

type FlightEndpoint struct {
	Airport       Airport  `json:"airport"`
	ScheduledTime TimeInfo `json:"scheduledTime"`
	RevisedTime   TimeInfo `json:"revisedTime"`
	Terminal      string   `json:"terminal"`
	Gate          string   `json:"gate"`
}

type Data struct {
	Status    string         `json:"status"`
	Departure FlightEndpoint `json:"departure"`
	Arrival   FlightEndpoint `json:"arrival"`
	Number    string         `json:"number"`
	Airline   struct {
		Name string `json:"name"`
	} `json:"airline"`
	Aircraft struct {
		Model string `json:"model"`
	} `json:"aircraft"`
}

func (data Data) String() string {
	b := &strings.Builder{}
	// United Airlines flight UA 2402 (Boeing 737 MAX 9)
	fmt.Fprintf(b, "%s flight %s", data.Airline.Name, data.Number)
	if data.Aircraft.Model != "" {
		fmt.Fprintf(b, " (%s)", data.Aircraft.Model)
	}

	// from Houston George Bush (IAH)
	fmt.Fprintf(b, " from %s (%s)", data.Departure.Airport.Name, data.Departure.Airport.IATA)
	if data.Departure.Terminal != "" {
		fmt.Fprintf(b, " terminal %s", data.Departure.Terminal)
	}
	if data.Departure.Gate != "" {
		fmt.Fprintf(b, " gate %s", data.Departure.Gate)
	}

	// to Newark Liberty (EWR)
	fmt.Fprintf(b, " to %s (%s)", data.Arrival.Airport.Name, data.Arrival.Airport.IATA)
	if data.Arrival.Terminal != "" {
		fmt.Fprintf(b, " terminal %s", data.Arrival.Terminal)
	}
	if data.Arrival.Gate != "" {
		fmt.Fprintf(b, " gate %s", data.Arrival.Gate)
	}

	fmt.Fprintf(b, " is %s.", data.Status)

	// Times and offsets
	depTime, depErr := time.Parse("2006-01-02 15:04Z", data.Departure.ScheduledTime.Utc)
	if depErr == nil {
		fmt.Fprintf(b, " Dep: %s", depTime.Format("15:04"))
		revDepTime, revDepErr := time.Parse("2006-01-02 15:04Z", data.Departure.RevisedTime.Utc)
		if revDepErr == nil && !revDepTime.Equal(depTime) {
			diff := revDepTime.Sub(depTime).Minutes()
			fmt.Fprintf(b, " (%+.0fm)", diff)
		}
	}

	arrTime, arrErr := time.Parse("2006-01-02 15:04Z", data.Arrival.ScheduledTime.Utc)
	if arrErr == nil {
		fmt.Fprintf(b, " Arr: %s", arrTime.Format("15:04"))
		revArrTime, revArrErr := time.Parse("2006-01-02 15:04Z", data.Arrival.RevisedTime.Utc)
		if revArrErr == nil && !revArrTime.Equal(arrTime) {
			diff := revArrTime.Sub(arrTime).Minutes()
			fmt.Fprintf(b, " (%+.0fm)", diff)
		}
	}

	return b.String()
}

func QueryAll(flights []string) map[string]*Data {
	if *aerodataboxAPIKey == "" {
		logging.Warn("flights.QueryAll: API key not set")
		return nil
	}
	results := make(map[string]*Data)
	for _, flight := range flights {
		data, err := QueryOne(flight)
		if err != nil {
			logging.Error("flights.QueryAll: %v", err)
		} else {
			results[flight] = data
		}
		// Don't send more than 1QPS to the API
		time.Sleep(time.Second)
	}
	return results
}

func QueryOne(flight string) (*Data, error) {
	if *aerodataboxAPIKey == "" {
		return nil, fmt.Errorf("querying for flight %q: API key not set", flight)
	}

	// Default to current date in UTC
	date := time.Now().UTC().Format("2006-01-02")

	data, err := doQuery(flight, date)
	if err != nil {
		return nil, fmt.Errorf("querying for flight %q: %w", flight, err)
	}

	return data, nil
}

func doQuery(flight, date string) (*Data, error) {
	url := fmt.Sprintf("%s/%s/%s", apiBase, strings.ReplaceAll(flight, " ", ""), date)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("x-rapidapi-host", rapidAPIHost)
	req.Header.Set("x-rapidapi-key", *aerodataboxAPIKey)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, fmt.Errorf("flight not found")
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned status %s", resp.Status)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var apiResp []Data
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, err
	}

	if len(apiResp) == 0 {
		return nil, fmt.Errorf("no results")
	}

	if len(apiResp) > 1 {
		return nil, fmt.Errorf("multiple flights returned for %s on %s", flight, date)
	}

	return &apiResp[0], nil
}
