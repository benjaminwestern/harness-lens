package main

import (
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
)

func hostWithoutPort(hostport string) string {
	host, _, err := net.SplitHostPort(hostport)
	if err != nil {
		host = hostport
	}
	return strings.Trim(strings.ToLower(host), "[]")
}

func isLoopbackHost(hostport string) bool {
	host := hostWithoutPort(hostport)
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

func sameHost(a, b string) bool {
	return hostWithoutPort(a) == hostWithoutPort(b)
}

func allowRemoteWrites() bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv("HARNESS_LENS_ALLOW_REMOTE_WRITES")))
	return v == "1" || v == stringTrue || v == "yes"
}

func rejectCrossOriginWrite(w http.ResponseWriter, r *http.Request) bool {
	if r.Method == http.MethodGet || r.Method == http.MethodHead || r.Method == http.MethodOptions {
		return false
	}
	if !allowRemoteWrites() && !isLoopbackHost(r.Host) {
		http.Error(w, "write endpoints are local-only by default", http.StatusForbidden)
		return true
	}
	if origin := r.Header.Get("Origin"); origin != "" {
		u, err := url.Parse(origin)
		if err != nil || !sameHost(u.Host, r.Host) {
			http.Error(w, "cross-origin write rejected", http.StatusForbidden)
			return true
		}
		return false
	}
	if ref := r.Header.Get("Referer"); ref != "" {
		u, err := url.Parse(ref)
		if err != nil || !sameHost(u.Host, r.Host) {
			http.Error(w, "cross-origin write rejected", http.StatusForbidden)
			return true
		}
	}
	return false
}
