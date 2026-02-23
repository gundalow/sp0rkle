package quotes

import (
	"fmt"
	"math/rand/v2"
	"time"

	"github.com/fluffle/golog/logging"
	"github.com/fluffle/sp0rkle/bot"
	"github.com/fluffle/sp0rkle/db"
	"github.com/fluffle/sp0rkle/util/datetime"
	"gopkg.in/mgo.v2/bson"
)

const COLLECTION string = "quotes"

type Quote struct {
	Quote     string
	QID       int
	Nick      bot.Nick
	Chan      bot.Chan
	Accessed  int
	Timestamp time.Time
	Id_       bson.ObjectId `bson:"_id,omitempty"`
}

var _ db.Indexer = (*Quote)(nil)

func NewQuote(q string, n bot.Nick, c bot.Chan) *Quote {
	return &Quote{q, 0, n, c, 0, time.Now(), bson.NewObjectId()}
}

func (q *Quote) Indexes() []db.Key {
	return []db.Key{
		db.K{db.I{"qid", uint64(q.QID)}},
	}
}

func (q *Quote) Id() bson.ObjectId {
	return q.Id_
}

func (q *Quote) byQID() db.K {
	return db.K{db.I{"qid", uint64(q.QID)}}
}

type Quotes []*Quote

func (qs Quotes) Strings() []string {
	s := make([]string, len(qs))
	for i, q := range qs {
		// Explicitly omit QID here since QIDs come from the bucket sequence.
		s[i] = fmt.Sprintf("%s <%s:%s> %s (%d)", datetime.Format(q.Timestamp),
			q.Nick, q.Chan, q.Quote, q.Accessed)
	}
	return s
}

type Collection struct {
	db.C

	// Cache of ObjectId's for PseudoRand
	seen map[string]map[bson.ObjectId]bool
}

func Init() *Collection {
	qc := &Collection{
		seen: make(map[string]map[bson.ObjectId]bool),
	}
	qc.Init(db.Bolt.Indexed(), COLLECTION, nil)
	return qc
}

func (qc *Collection) GetByQID(qid int) *Quote {
	res := &Quote{QID: qid}
	if err := qc.Get(res.byQID(), res); err == nil {
		return res
	}
	return nil
}

func (qc *Collection) NewQID() (int, error) {
	return qc.Next(db.K{})
}

func (qc *Collection) GetPseudoRand(regex string) *Quote {
	// TODO(fluffle): This implementation of GetPseudoRand is inefficient.
	// There are 3 steps: fetch all quotes matching the regex, filter out
	// already-seen ObjectIds, and return a result while updating the filters.

	quotes := Quotes{}
	if regex == "" {
		if err := qc.All(db.K{}, &quotes); err != nil {
			logging.Warn("Quote All() failed: %s", err)
			return nil
		}
	} else {
		if err := qc.Match("Quote", regex, &quotes); err != nil {
			logging.Warn("Quote Match(%q) failed: %s", regex, err)
			return nil
		}
	}

	filtered := Quotes{}
	ids, ok := qc.seen[regex]
	if ok && len(ids) > 0 {
		logging.Debug("Looked for quotes matching %q before, %d stored id's",
			regex, len(ids))
		for _, quote := range quotes {
			if !ids[quote.Id_] {
				filtered = append(filtered, quote)
			}
		}
	} else {
		filtered = quotes
	}

	count := len(filtered)
	switch count {
	case 0:
		if ok {
			// Looked for this regex before, but nothing matches now
			delete(qc.seen, regex)
		}
		return nil
	case 1:
		if ok {
			// if the count of results is 1 and we're storing seen data for regex
			// then we've exhausted the possible results and should wipe it
			logging.Debug("Zeroing seen data for regex %q.", regex)
			delete(qc.seen, regex)
		}
		return filtered[0]
	}
	// case count > 1:
	if !ok {
		// only store seen for regex that match more than one quote
		logging.Debug("Creating seen data for regex %q.", regex)
		qc.seen[regex] = map[bson.ObjectId]bool{}
	}
	res := filtered[rand.IntN(count)]
	logging.Debug("Storing id %v for regex %q.", res.Id_, regex)
	qc.seen[regex][res.Id_] = true
	return res
}
