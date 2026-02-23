package markov

import (
	"encoding/binary"
	"fmt"
	"strings"

	"github.com/fluffle/golog/logging"
	"github.com/fluffle/sp0rkle/db"
	"github.com/fluffle/sp0rkle/util"
	"github.com/fluffle/sp0rkle/util/markov"
	bolt "go.etcd.io/bbolt"
	"gopkg.in/mgo.v2/bson"
)

const COLLECTION = "markov"

type MarkovLink struct {
	Source, Dest string
	Uses         int
	uses         []byte
	Tag          string
	Id_          bson.ObjectId `bson:"_id,omitempty"`
}

var _ db.Indexer = (*MarkovLink)(nil)

func New(source, dest, tag string) *MarkovLink {
	return &MarkovLink{
		Source: source,
		Dest:   dest,
		Tag:    strings.ToLower(tag),
		Id_:    bson.NewObjectId(),
	}
}

func (ml *MarkovLink) String() string {
	return fmt.Sprintf("%s(%q->%q):%d", ml.Tag, ml.Source, ml.Dest, ml.Uses)
}

func (ml *MarkovLink) Indexes() []db.Key {
	return []db.Key{
		db.K{db.S{"tag", ml.Tag}, db.S{"source", ml.Source}, db.S{"dest", ml.Dest}},
	}
}

func (ml *MarkovLink) Id() bson.ObjectId {
	return ml.Id_
}

func (ml *MarkovLink) byTagSrcDest() db.Key {
	return db.K{db.S{"tag", ml.Tag}, db.S{"source", ml.Source}, db.S{"dest", ml.Dest}}
}

func (ml *MarkovLink) byTagSrc() db.Key {
	return db.K{db.S{"tag", ml.Tag}, db.S{"source", ml.Source}}
}

func (ml *MarkovLink) encodeUses() {
	ml.uses = make([]byte, binary.MaxVarintLen64)
	n := binary.PutUvarint(ml.uses, uint64(ml.Uses))
	ml.uses = ml.uses[:n]
}

func (ml *MarkovLink) decodeUses() {
}

type MarkovLinks []*MarkovLink

func (mls MarkovLinks) Strings() []string {
	s := make([]string, len(mls))
	for i, ml := range mls {
		s[i] = ml.String()
	}
	return s
}

type Collection struct {
	// Markov is a bit special. Because of the quantity of data
	// stored, it is desirable to be able to use the boltdb key
	// for storage too -- something that the standard Collection
	// interface does not provide for, in the possibly misguided
	// name of API simplicity. So instead of hacking this in, we
	// skip the entire db layer and deal with it here instead.
	bolt *bolt.DB
}

// Wrapper to get hold of a factoid collection handle
func Init() *Collection {
	mc := &Collection{}
	mc.bolt = db.Bolt.DB()

	err := mc.bolt.Update(func(tx *bolt.Tx) error {
		_, err := tx.CreateBucketIfNotExists([]byte(COLLECTION))
		return err
	})
	if err != nil {
		logging.Fatal("Creating Markov BoltDB bucket failed: %v", err)
	}
	return mc
}

func (mc *Collection) incUses(source, dest, tag string) {
	if util.LooksURLish(source) || util.LooksURLish(dest) {
		// Skip URLs entirely.
		return
	}
	link := New(source, dest, tag)
	mc.bolt.View(func(tx *bolt.Tx) error {
		return mc.getUsesTx(tx, link)
	})
	link.Uses++
	// Increment and write new value.
	err := mc.bolt.Update(func(tx *bolt.Tx) error {
		return mc.putUsesTx(tx, link)
	})
	if err != nil {
		logging.Error("Failed to insert Bolt MarkovLink %s(%q->%q): %v",
			tag, source, dest, err)
	}
}

func (mc *Collection) getUsesTx(tx *bolt.Tx, link *MarkovLink) error {
	mb := tx.Bucket([]byte(COLLECTION))
	tb := mb.Bucket([]byte(link.Tag))
	if tb == nil {
		return fmt.Errorf("couldn't find bucket representing tag %q", link.Tag)
	}
	sb := tb.Bucket([]byte(link.Source))
	if sb == nil {
		return fmt.Errorf("couldn't find bucket representing source %q", link.Source)
	}
	v := sb.Get([]byte(link.Dest))
	if v == nil {
		return fmt.Errorf("couldn't find key representing dest %q", link.Dest)
	}
	uses, _ := binary.Uvarint(v)
	link.Uses = int(uses)
	return nil
}

func (mc *Collection) putUsesTx(tx *bolt.Tx, link *MarkovLink) error {
	mb := tx.Bucket([]byte(COLLECTION))
	tb, err := mb.CreateBucketIfNotExists([]byte(link.Tag))
	if err != nil {
		return err
	}
	sb, err := tb.CreateBucketIfNotExists([]byte(link.Source))
	if err != nil {
		return err
	}
	link.encodeUses()
	return sb.Put([]byte(link.Dest), link.uses)
}

func (mc *Collection) AddAction(action, tag string) {
	mc.Add(markov.ACTION_START, action, tag)
}

func (mc *Collection) AddSentence(sentence, tag string) {
	mc.Add(markov.SENTENCE_START, sentence, tag)
}

func (mc *Collection) Add(source, data, tag string) {
	for _, dest := range strings.Fields(data) {
		mc.incUses(source, dest, tag)
		source = dest
	}
	mc.incUses(source, markov.SENTENCE_END, tag)
}

func (mc *Collection) ClearTag(tag string) error {
	err := mc.bolt.Update(func(tx *bolt.Tx) error {
		mb := tx.Bucket([]byte(COLLECTION))
		return mb.DeleteBucket([]byte(tag))
	})
	if err != nil {
		return fmt.Errorf("clearing markov tag %q: %v", tag, err)
	}
	return nil
}

type MarkovSource struct {
	*Collection
	tag string
}

func (mc *Collection) Source(tag string) markov.Source {
	return &MarkovSource{mc, tag}
}

func (ms *MarkovSource) GetLinks(source string) (markov.Links, error) {
	links := markov.Links{}
	// Read from bolt.
	err := ms.bolt.View(func(tx *bolt.Tx) error {
		return ms.getLinksTx(tx, []byte(ms.tag), []byte(source), &links)
	})
	if err != nil {
		return nil, fmt.Errorf("markov getlinks(%q, %q): %v", ms.tag, source, err)
	}
	return links, nil
}

func (ms *MarkovSource) getLinksTx(tx *bolt.Tx, tag, source []byte, blinks *markov.Links) error {
	mb := tx.Bucket([]byte(COLLECTION))
	tb := mb.Bucket(tag)
	if tb == nil {
		return fmt.Errorf("couldn't find bucket representing tag %q", tag)
	}
	sb := tb.Bucket(source)
	if sb == nil {
		return fmt.Errorf("couldn't find bucket representing source %q", source)
	}
	return sb.ForEach(func(k, v []byte) error {
		uses, _ := binary.Uvarint(v)
		*blinks = append(*blinks, markov.Link{string(k), int(uses)})
		return nil
	})
}
