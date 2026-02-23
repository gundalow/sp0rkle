package seen

import (
	"fmt"
	"sort"
	"time"

	"github.com/fluffle/sp0rkle/bot"
	"github.com/fluffle/sp0rkle/db"
	"github.com/fluffle/sp0rkle/util"
	"github.com/fluffle/sp0rkle/util/datetime"
	"gopkg.in/mgo.v2/bson"
)

const COLLECTION string = "seen"

type Nick struct {
	Nick      bot.Nick
	Chan      bot.Chan
	OtherNick bot.Nick
	Timestamp time.Time
	Key       string
	Action    string
	Text      string
	Id_       bson.ObjectId `bson:"_id"`
}

var _ db.Indexer = (*Nick)(nil)

type seenMsg func(*Nick) string

var actionMap map[string]seenMsg = map[string]seenMsg{
	"PRIVMSG": func(n *Nick) string {
		return fmt.Sprintf("in %s, saying '%s'", n.Chan, n.Text)
	},
	"ACTION": func(n *Nick) string {
		return fmt.Sprintf("in %s, saying '%s %s'", n.Chan, n.Nick, n.Text)
	},
	"JOIN": func(n *Nick) string {
		return fmt.Sprintf("joining %s", n.Chan)
	},
	"PART": func(n *Nick) string {
		return fmt.Sprintf("parting %s with the message '%s'", n.Chan, n.Text)
	},
	"KICKING": func(n *Nick) string {
		return fmt.Sprintf("kicking %s from %s with the message '%s'",
			n.OtherNick, n.Chan, n.Text)
	},
	"KICKED": func(n *Nick) string {
		return fmt.Sprintf("being kicked from %s by %s with the message '%s'",
			n.Chan, n.OtherNick, n.Text)
	},
	"QUIT": func(n *Nick) string {
		return fmt.Sprintf("quitting with the message '%s'", n.Text)
	},
	"NICK": func(n *Nick) string {
		return fmt.Sprintf("changing their nick to '%s'", n.Text)
	},
	"SMOKE": func(n *Nick) string { return "going for a smoke." },
}

func SawNick(nick bot.Nick, ch bot.Chan, act, txt string) *Nick {
	return &Nick{
		Nick:      nick,
		Chan:      ch,
		OtherNick: "",
		Timestamp: time.Now(),
		Key:       nick.Lower(),
		Action:    act,
		Text:      txt,
		Id_:       bson.NewObjectId(),
	}
}

func (n *Nick) String() string {
	if act, ok := actionMap[n.Action]; ok {
		return fmt.Sprintf("I last saw %s on %s (%s ago), %s.",
			n.Nick, datetime.Format(n.Timestamp),
			util.TimeSince(n.Timestamp), act(n))
	}
	// No specific message format for the action seen.
	return fmt.Sprintf("I last saw %s at %s (%s ago).",
		n.Nick, datetime.Format(n.Timestamp),
		util.TimeSince(n.Timestamp))
}

func (n *Nick) Indexes() []db.Key {
	// Yes, this creates two buckets per nick, but then we don't have to worry
	// about the keys *in* the bucket. Using "nick" for both keys would mean an
	// All() lookup for "nick" would resolve both action and ts pointers.
	// This way either we look up nick + action or key (implicitly ordered by ts).
	//
	// This could *theoretically* be reduced to one bucket by taking into
	// account implementation details of All() and boltdb key ordering --
	// if the timestamp key sorts lexographically before the action key then
	// those pointers will be resolved first (in timestamp order), and
	// the action pointers *should* be deduped and ignored by All().
	// This means the results of All() would still be in timestamp order.
	return []db.Key{
		db.K{db.S{"nick", n.Nick.Lower()}, db.S{"action", n.Action}},
		db.K{db.S{"key", n.Nick.Lower()}, db.I{"ts", uint64(n.Timestamp.UnixNano())}},
	}
}

func (n *Nick) Id() bson.ObjectId {
	return n.Id_
}

func (n *Nick) Exists() bool {
	return n != nil && len(n.Id_) > 0
}

func (n *Nick) byNick() db.K {
	// Uses "key" not "nick" bucket, so that results are ordered by timestamp.
	return db.K{db.S{"key", n.Nick.Lower()}}
}

func (n *Nick) byNickAction() db.K {
	return db.K{db.S{"nick", n.Nick.Lower()}, db.S{"action", n.Action}}
}

type Nicks []*Nick

func (ns Nicks) Strings() []string {
	s := make([]string, len(ns))
	for i, n := range ns {
		s[i] = fmt.Sprintf("%#v", n)
	}
	return s
}

// Implement sort.Interface to sort by descending timestamp.
func (ns Nicks) Len() int           { return len(ns) }
func (ns Nicks) Swap(i, j int)      { ns[i], ns[j] = ns[j], ns[i] }
func (ns Nicks) Less(i, j int) bool { return ns[i].Timestamp.After(ns[j].Timestamp) }

type Collection struct {
	db.C
}

func Init() *Collection {
	sc := &Collection{}
	sc.Init(db.Bolt.Indexed(), COLLECTION, nil)
	return sc
}

func (sc *Collection) LastSeen(nick string) *Nick {
	var nicks Nicks
	n := &Nick{Nick: bot.Nick(nick)}
	if err := sc.All(n.byNick(), &nicks); err != nil {
		return nil
	}
	if len(nicks) == 0 {
		return nil
	}
	// BoltDB key ordering for timestamp (uint64 BigEndian) should
	// mean that the last element is the most recent.
	return nicks[len(nicks)-1]
}

func (sc *Collection) LastSeenDoing(nick, act string) *Nick {
	n := &Nick{Nick: bot.Nick(nick), Action: act}
	if err := sc.Get(n.byNickAction(), n); err == nil && n.Exists() {
		return n
	}
	return nil
}

func (sc *Collection) SeenAnyMatching(rx string) []string {
	var ns Nicks
	if err := sc.Match("Nick", rx, &ns); err != nil {
		return nil
	}
	sort.Sort(ns)
	seen := make(map[string]bool)
	res := make([]string, 0, len(ns))
	for _, n := range ns {
		if !seen[n.Nick.Lower()] {
			res = append(res, string(n.Nick))
			seen[n.Nick.Lower()] = true
		}
	}
	return res
}
