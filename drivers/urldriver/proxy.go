package urldriver

import (
	"errors"
	"net/url"
	"regexp"
	"strings"
)

const gateway = "https://external-content.duckduckgo.com/iu/?u="

// ErrUnsupportedFormat is returned when an imgur URL contains invalid path segments.
var ErrUnsupportedFormat = errors.New("unsupported format")

var invalidImgurRegex = regexp.MustCompile(`imgur\.com/(a|gallery|t|user)/`)
var imgurDomainRegex = regexp.MustCompile(`(^|\.)imgur\.com$`)

// IsImgurURL checks if the given URL is an Imgur URL.
func IsImgurURL(sourceURL string) bool {
	lowerURL := strings.ToLower(sourceURL)
	finalURL := sourceURL
	if !strings.HasPrefix(lowerURL, "http://") && !strings.HasPrefix(lowerURL, "https://") {
		finalURL = "https://" + finalURL
	}
	u, err := url.Parse(finalURL)
	if err != nil {
		return false
	}
	host := strings.ToLower(u.Host)
	if idx := strings.Index(host, ":"); idx != -1 {
		host = host[:idx]
	}
	return imgurDomainRegex.MatchString(host)
}

// ProxyImgurURL transforms an Imgur URL to route through the DuckDuckGo proxy.
func ProxyImgurURL(sourceURL string) (string, error) {
	lowerURL := strings.ToLower(sourceURL)
	if invalidImgurRegex.MatchString(lowerURL) {
		return "", ErrUnsupportedFormat
	}

	finalURL := sourceURL
	if !strings.HasPrefix(lowerURL, "http://") && !strings.HasPrefix(lowerURL, "https://") {
		finalURL = "https://" + finalURL
	}

	// Apply strict RFC 3986 percent-encoding on finalURL.
	encoded := url.QueryEscape(finalURL)
	encoded = strings.ReplaceAll(encoded, "+", "%20")

	return gateway + encoded, nil
}
