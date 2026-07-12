package urldriver

import (
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"github.com/fluffle/sp0rkle/collections/urls"
	"github.com/fluffle/sp0rkle/db"
	"github.com/fluffle/sp0rkle/util"
	"github.com/fluffle/sp0rkle/util/bson"
)

func TestIsImgurURL(t *testing.T) {
	tests := []struct {
		url      string
		expected bool
	}{
		{"https://i.imgur.com/abc123.png", true},
		{"http://imgur.com/xyz789.jpg", true},
		{"https://m.imgur.com/123.gif", true},
		{"https://imgur.com/a/AwesomeAlbum", true},
		{"https://notimgur.com/image.png", false},
		{"imgur.com/xyz", true},
		{"http://not.imgur.com.example.com/foo", false},
	}

	for _, tc := range tests {
		actual := IsImgurURL(tc.url)
		if actual != tc.expected {
			t.Errorf("IsImgurURL(%q) = %v; expected %v", tc.url, actual, tc.expected)
		}
	}
}

func TestProxyImgurURL(t *testing.T) {
	tests := []struct {
		url         string
		expectedURL string
		expectError bool
	}{
		{
			url:         "https://i.imgur.com/abc123.png",
			expectedURL: "https://external-content.duckduckgo.com/iu/?u=https%3A%2F%2Fi.imgur.com%2Fabc123.png",
			expectError: false,
		},
		{
			url:         "http://imgur.com/xyz789.jpg",
			expectedURL: "https://external-content.duckduckgo.com/iu/?u=http%3A%2F%2Fimgur.com%2Fxyz789.jpg",
			expectError: false,
		},
		{
			url:         "https://imgur.com/a/AwesomeAlbum",
			expectError: true,
		},
		{
			url:         "https://i.imgur.com/123.gif",
			expectedURL: "https://external-content.duckduckgo.com/iu/?u=https%3A%2F%2Fi.imgur.com%2F123.gif",
			expectError: false,
		},
		{
			url:         "imgur.com/xyz",
			expectedURL: "https://external-content.duckduckgo.com/iu/?u=https%3A%2F%2Fimgur.com%2Fxyz",
			expectError: false,
		},
		{
			url:         "https://imgur.com/gallery/123",
			expectError: true,
		},
		{
			url:         "https://imgur.com/t/tagname",
			expectError: true,
		},
		{
			url:         "https://imgur.com/user/username",
			expectError: true,
		},
		{
			url:         "https://notimgur.com/image.png",
			expectError: true,
		},
	}

	for _, tc := range tests {
		actual, err := ProxyImgurURL(tc.url)
		if tc.expectError {
			if err == nil {
				t.Errorf("ProxyImgurURL(%q) expected error but got none", tc.url)
			}
		} else {
			if err != nil {
				t.Errorf("ProxyImgurURL(%q) returned unexpected error: %v", tc.url, err)
			}
			if actual != tc.expectedURL {
				t.Errorf("ProxyImgurURL(%q) = %q; expected %q", tc.url, actual, tc.expectedURL)
			}
		}
	}
}

type mockRoundTripper struct {
	handler http.Handler
}

func (m *mockRoundTripper) RoundTrip(req *http.Request) (*http.Response, error) {
	rec := httptest.NewRecorder()
	m.handler.ServeHTTP(rec, req)
	resp := rec.Result()
	resp.Request = req
	return resp, nil
}

type mockIndexedCollection struct {
	db.IndexedCollection[*urls.Url]
	urls map[string]*urls.Url
}

func (m *mockIndexedCollection) Get(k db.Key) (*urls.Url, error) {
	for _, u := range m.urls {
		for _, key := range u.Indexes() {
			if key.String() == k.String() {
				return u, nil
			}
		}
	}
	return nil, nil
}

func (m *mockIndexedCollection) Put(u *urls.Url) error {
	m.urls[u.Url] = u
	return nil
}

func (m *mockIndexedCollection) Del(u *urls.Url) error {
	delete(m.urls, u.Url)
	return nil
}

func TestCacheImgurProxy(t *testing.T) {
	// Set temporary cache directory
	tmpDir, err := os.MkdirTemp("", "url_cache_test")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tmpDir)

	oldCacheDir := *urlCacheDir
	*urlCacheDir = tmpDir
	defer func() { *urlCacheDir = oldCacheDir }()

	// Intercept HTTP requests
	var requestedURLs []string
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestedURLs = append(requestedURLs, r.URL.String())
		w.Header().Set("Content-Type", "image/png")
		w.Header().Set("Content-Length", "12")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("mock_content"))
	})

	oldTransport := http.DefaultClient.Transport
	http.DefaultClient.Transport = &mockRoundTripper{handler: handler}
	defer func() { http.DefaultClient.Transport = oldTransport }()

	mockCol := &mockIndexedCollection{urls: make(map[string]*urls.Url)}
	uc := urls.New(mockCol)
	d := &Driver{uc: uc, lastseen: make(map[string]bson.ObjectId)}

	// 1. Successful proxy cache
	u := urls.NewUrl("https://i.imgur.com/abc123.png", "nick", "chan")
	err = d.Cache(u)
	if err != nil {
		t.Fatalf("unexpected error caching: %v", err)
	}

	if len(requestedURLs) < 2 {
		t.Fatalf("expected at least 2 requests (HEAD and GET), got %d", len(requestedURLs))
	}

	// Verify that the requests were made to the proxied URL
	expectedProxyPrefix := "https://external-content.duckduckgo.com/iu/?u="
	for _, reqURL := range requestedURLs {
		if !strings.HasPrefix(reqURL, expectedProxyPrefix) {
			t.Errorf("expected request to be proxied, got: %q", reqURL)
		}
	}

	// Verify file content was saved
	savedFile := util.JoinPath(tmpDir, u.CachedAs)
	data, err := os.ReadFile(savedFile)
	if err != nil {
		t.Fatalf("failed to read saved file: %v", err)
	}
	if string(data) != "mock_content" {
		t.Errorf("saved file has wrong content: %q; expected %q", string(data), "mock_content")
	}

	// 2. Unsupported format check
	requestedURLs = nil
	u2 := urls.NewUrl("https://imgur.com/a/AwesomeAlbum", "nick", "chan")
	err = d.Cache(u2)
	if err != ErrUnsupportedFormat {
		t.Errorf("expected error %v, got %v", ErrUnsupportedFormat, err)
	}
	if len(requestedURLs) != 0 {
		t.Errorf("expected no HTTP requests for unsupported format, but got some: %v", requestedURLs)
	}
}
