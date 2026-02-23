package integration

import (
	"bufio"
	"fmt"
	"net"
	"strings"
	"sync"
)

type MockIRCd struct {
	Addr     string
	ln       net.Listener
	clients  map[string]net.Conn
	mu       sync.Mutex
	Messages chan string
	Quit     chan struct{}
}

func NewMockIRCd() (*MockIRCd, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	return &MockIRCd{
		Addr:     ln.Addr().String(),
		ln:       ln,
		clients:  make(map[string]net.Conn),
		Messages: make(chan string, 100),
		Quit:     make(chan struct{}),
	}, nil
}

func (m *MockIRCd) Start() {
	go func() {
		for {
			conn, err := m.ln.Accept()
			if err != nil {
				select {
				case <-m.Quit:
					return
				default:
					fmt.Printf("MockIRCd accept error: %v\n", err)
					return
				}
			}
			go m.handleClient(conn)
		}
	}()
}

func (m *MockIRCd) Stop() {
	close(m.Quit)
	m.ln.Close()
}

func (m *MockIRCd) handleClient(conn net.Conn) {
	scanner := bufio.NewScanner(conn)
	var nick string
	for scanner.Scan() {
		line := scanner.Text()
		m.Messages <- line
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}

		cmd := strings.ToUpper(fields[0])
		switch cmd {
		case "NICK":
			nick = fields[1]
			m.mu.Lock()
			m.clients[nick] = conn
			m.mu.Unlock()
		case "USER":
			fmt.Fprintf(conn, ":mockirc 001 %s :Welcome to the mock IRC server\r\n", nick)
		case "JOIN":
			channel := fields[1]
			fmt.Fprintf(conn, ":%s!user@host JOIN %s\r\n", nick, channel)
		case "PRIVMSG":
			// Just acknowledge for now
		}
	}
}

func (m *MockIRCd) SendMessage(from, target, message string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for _, conn := range m.clients {
		fmt.Fprintf(conn, ":%s!user@host PRIVMSG %s :%s\r\n", from, target, message)
	}
}
