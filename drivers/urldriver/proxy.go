package urldriver

import (
	"errors"
	"net/url"
	"regexp"
	"strings"
)

const gateway = "https://external-content.duckduckgo.com/iu/?u="

// ErrUnsupportedFormat is returned when an imgur URL contains invalid path segments or is not a valid Imgur URL.
var ErrUnsupportedFormat = errors.New("unsupported format")

var invalidImgurRegex = regexp.MustCompile(`imgur\.com/(a|gallery|t|user)/`)
var imgurDomainRegex = regexp.MustCompile(`(^|\.)imgur\.com$`)

// normalizeURL ensures the sourceURL contains a valid scheme, prepending https:// if missing.
func normalizeURL(sourceURL string) string {
	lowerURL := strings.ToLower(sourceURL)
	if !strings.HasPrefix(lowerURL, "http://") && !strings.HasPrefix(lowerURL, "https://") {
		return "https://" + sourceURL
	}
	return sourceURL
}

// IsImgurURL checks if the given URL is an Imgur URL.
func IsImgurURL(sourceURL string) bool {
	finalURL := normalizeURL(sourceURL)
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
	finalURL := normalizeURL(sourceURL)

	// Independently validate the normalized URL with the Imgur-domain check.
	if !IsImgurURL(finalURL) {
		return "", ErrUnsupportedFormat
	}

	lowerURL := strings.ToLower(finalURL)
	if invalidImgurRegex.MatchString(lowerURL) {
		return "", ErrUnsupportedFormat
	}

	// Apply strict RFC 3986 percent-encoding on finalURL.
	encoded := url.QueryEscape(finalURL)
	encoded = strings.ReplaceAll(encoded, "+", "%20")

	return gateway + encoded, nil
}
