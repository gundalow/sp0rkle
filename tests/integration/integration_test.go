package integration

import (
	"context"
	"flag"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/fluffle/golog/logging"
	"github.com/fluffle/sp0rkle/bot"
	"github.com/fluffle/sp0rkle/db"
	"github.com/fluffle/sp0rkle/drivers/factdriver"
	"github.com/fluffle/sp0rkle/drivers/karmadriver"
	"github.com/fluffle/sp0rkle/drivers/reminddriver"
	"github.com/fluffle/sp0rkle/drivers/statsdriver"
	"github.com/fluffle/sp0rkle/util/datetime"
)

func TestIntegration(t *testing.T) {
	logging.InitFromFlags()
	// Increase flood limit for tests to avoid delays
	flag.Set("pause", "1s")

	// Set up temporary BoltDB
	tmpDir := t.TempDir()
	dbPath := filepath.Join(tmpDir, "test.boltdb")
	backupDir := filepath.Join(tmpDir, "backup")

	// Start mock IRC server
	ircd, err := NewMockIRCd()
	if err != nil {
		t.Fatalf("Failed to create mock IRCd: %v", err)
	}
	ircd.Start()
	defer ircd.Stop()

	// Set flags programmatically
	flag.Set("servers", ircd.Addr)
	flag.Set("nick", "testbot")
	flag.Set("channels", "#test")

	// Basic setup similar to main.go
	if err := datetime.SetTZ("UTC"); err != nil {
		t.Fatalf("Failed to set timezone: %v", err)
	}

	if err := db.Bolt.Init(dbPath, backupDir, 24*time.Hour); err != nil {
		t.Fatalf("Failed to init BoltDB: %v", err)
	}
	defer db.Bolt.Close()

	bot.Init(context.Background())

	// Initialize drivers we want to test
	karmadriver.Init()
	factdriver.Init()
	reminddriver.Init()
	statsdriver.Init()

	// Start bot connection
	bot.Connect()

	// 1. Verify connection and join
	joined := false
	timeout := time.After(10 * time.Second)
	for !joined {
		select {
		case msg := <-ircd.Messages:
			if strings.Contains(msg, "JOIN #test") {
				joined = true
			}
		case <-timeout:
			t.Fatal("Timeout waiting for JOIN #test")
		}
	}

	// 2. Test Karma driver
	// Send "test++" to #test
	ircd.SendMessage("user", "#test", "test++")

	// Wait for bot to potentially respond (karma doesn't always respond to ++ unless asked)
	// Actually karma responds with "test" has karma of 1... if it's the first time.

	// Wait a bit for processing
	time.Sleep(500 * time.Millisecond)

	// Ask for karma
	ircd.SendMessage("user", "#test", "testbot: karma test")

	foundResponse := false
	timeout = time.After(10 * time.Second)
	for !foundResponse {
		select {
		case msg := <-ircd.Messages:
			if strings.Contains(msg, "PRIVMSG #test") && strings.Contains(msg, "karma of 1") {
				foundResponse = true
			}
		case <-timeout:
			t.Fatal("Timeout waiting for karma response")
		}
	}

	// 3. Test Factoids
	ircd.SendMessage("user", "#test", "testbot: fact := value")

	// Wait for acknowledgment
	foundAck := false
	timeout = time.After(5 * time.Second)
	for !foundAck {
		select {
		case msg := <-ircd.Messages:
			t.Logf("Factoid Ack check: %s", msg)
			if strings.Contains(msg, "PRIVMSG #test") && strings.Contains(msg, "now know") {
				foundAck = true
			}
		case <-timeout:
			t.Fatal("Timeout waiting for factoid acknowledgment")
		}
	}

	ircd.SendMessage("user", "#test", "fact")

	foundResponse = false
	timeout = time.After(10 * time.Second)
	for !foundResponse {
		select {
		case msg := <-ircd.Messages:
			t.Logf("Factoid response check: %s", msg)
			// Factoid response should be "value"
			if strings.Contains(msg, "PRIVMSG #test") && strings.Contains(msg, "value") {
				foundResponse = true
			}
		case <-timeout:
			t.Fatal("Timeout waiting for factoid response")
		}
	}

	// 4. Test Reminders
	// "remind me to do thing in 1 second"
	ircd.SendMessage("user", "#test", "testbot: remind me to do thing in 1 second")

	// Wait for acknowledgment
	foundAck = false
	timeout = time.After(5 * time.Second)
	for !foundAck {
		select {
		case msg := <-ircd.Messages:
			t.Logf("Reminder Ack check: %s", msg)
			if strings.Contains(msg, "PRIVMSG #test") && strings.Contains(msg, "okay") {
				foundAck = true
			}
		case <-timeout:
			t.Fatal("Timeout waiting for reminder acknowledgment")
		}
	}

	// Wait for reminder
	foundReminder := false
	timeout = time.After(10 * time.Second)
	for !foundReminder {
		select {
		case msg := <-ircd.Messages:
			t.Logf("Reminder check: %s", msg)
			if strings.Contains(msg, "PRIVMSG #test") && strings.Contains(msg, "you asked me to remind you to do thing") {
				foundReminder = true
			}
		case <-timeout:
			t.Fatal("Timeout waiting for reminder")
		}
	}

	// 5. Test Stats
	// Bot should have seen "test++", "testbot: karma test", "testbot: fact := value", "fact", etc.
	// We'll send one more specific line.
	ircd.SendMessage("user", "#test", "stats are fun")
	time.Sleep(500 * time.Millisecond)
	ircd.SendMessage("user", "#test", "testbot: stats user")

	foundResponse = false
	timeout = time.After(10 * time.Second)
	for !foundResponse {
		select {
		case msg := <-ircd.Messages:
			t.Logf("Stats response check: %s", msg)
			if strings.Contains(msg, "PRIVMSG #test") && strings.Contains(msg, "words") && strings.Contains(msg, "lines") {
				foundResponse = true
			}
		case <-timeout:
			t.Fatal("Timeout waiting for stats response")
		}
	}
}
