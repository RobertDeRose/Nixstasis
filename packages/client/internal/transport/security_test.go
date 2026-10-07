package transport

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/RobertDeRose/Nixstasis/packages/client/internal/config"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/frp"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/identity"
	"github.com/RobertDeRose/Nixstasis/packages/client/internal/telemetry"
)

func TestNewClientURLPolicy(t *testing.T) {
	for _, tc := range []struct {
		url   string
		allow bool
		ok    bool
	}{
		{"https://api.example.com", false, true},
		{"https://127.0.0.1:4000", false, true},
		{"http://127.0.0.1:4000", false, false},
		{"http://127.0.0.1:4000", true, true},
		{"http://127.1.2.3:4000", true, true},
		{"http://[::1]:4000", true, true},
		{"http://localhost:4000", true, true},
		{"http://api.example.com", true, false},
		{"http://192.168.1.1", true, false},
		{"http://0.0.0.0", true, false},
		{"http://localhost.example.com", true, false},
		{"http://127.0.0.1.example.com", true, false},
		{"ftp://localhost", true, false},
		{"//localhost:4000", true, false},
		{"https://", false, false},
		{"https://user:secret@api.example.com", false, false},
		{"https://api.example.com?api_key=secret", false, false},
		{"https://api.example.com?", false, false},
		{"https://api.example.com#fragment", false, false},
		{"https://api.example.com:bad", false, false},
	} {
		t.Run(tc.url, func(t *testing.T) {
			_, err := NewClient(config.APIConfig{URL: tc.url, AllowLoopbackHTTP: tc.allow})
			if (err == nil) != tc.ok {
				t.Fatalf("NewClient() error = %v, want valid=%v", err, tc.ok)
			}
		})
	}
}

func TestHTTPRequiresExplicitLoopbackOptIn(t *testing.T) {
	var requests atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests.Add(1)
		w.WriteHeader(http.StatusCreated)
		_, _ = io.WriteString(w, `{"data":{"id":"device","api_token":"runtime-token"}}`)
	}))
	defer srv.Close()
	if _, err := NewClient(config.APIConfig{URL: srv.URL}); err == nil {
		t.Fatal("default client accepted HTTP")
	}
	if requests.Load() != 0 {
		t.Fatal("rejected URL sent a request")
	}
	client, err := NewClient(config.APIConfig{URL: strings.Replace(srv.URL, "127.0.0.1", "localhost", 1), AllowLoopbackHTTP: true})
	if err != nil {
		t.Fatal(err)
	}
	tr := client.httpClient.Transport.(*http.Transport)
	if tr.Proxy != nil {
		t.Fatal("loopback HTTP must bypass environment proxies")
	}
	if _, err := tr.DialContext(context.Background(), "tcp", "192.0.2.1:80"); err == nil {
		t.Fatal("loopback dialer accepted a remote address")
	}
	if _, err := client.RegisterDeviceCredentials(context.Background(), identity.DeviceIdentity{}, "proof", "replacement"); err != nil {
		t.Fatal(err)
	}
	if requests.Load() != 1 {
		t.Fatal("explicit loopback HTTP did not reach local server")
	}
}

func TestHTTPSCertificateVerification(t *testing.T) {
	var requests atomic.Int32
	srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests.Add(1)
		w.WriteHeader(http.StatusCreated)
		_, _ = io.WriteString(w, `{"data":{"id":"device","api_token":"runtime-token"}}`)
	}))
	srv.Config.ErrorLog = log.New(io.Discard, "", 0)
	srv.StartTLS()
	defer srv.Close()
	for _, tc := range []struct {
		name      string
		trusted   bool
		wrongHost bool
	}{
		{name: "untrusted certificate"},
		{name: "trusted certificate", trusted: true},
		{name: "wrong hostname", trusted: true, wrongHost: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			apiURL := srv.URL
			if tc.wrongHost {
				apiURL = strings.Replace(apiURL, "127.0.0.1", "wrong.invalid", 1)
			}
			client, err := NewClient(config.APIConfig{URL: apiURL})
			if err != nil {
				t.Fatal(err)
			}
			tr := client.httpClient.Transport.(*http.Transport)
			tr.Proxy = nil
			if tc.trusted {
				roots := x509.NewCertPool()
				roots.AddCert(srv.Certificate())
				tr.TLSClientConfig = &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12}
			}
			if tc.wrongHost {
				tr.DialContext = func(ctx context.Context, network, _ string) (net.Conn, error) {
					return (&net.Dialer{}).DialContext(ctx, network, srv.Listener.Addr().String())
				}
			}
			defer tr.CloseIdleConnections()
			before := requests.Load()
			_, err = client.RegisterDeviceCredentials(context.Background(), identity.DeviceIdentity{}, "proof", "replacement")
			wantSuccess := tc.trusted && !tc.wrongHost
			if (err == nil) != wantSuccess {
				t.Fatalf("register error = %v, want success=%v", err, wantSuccess)
			}
			if !wantSuccess && requests.Load() != before {
				t.Fatal("credentials reached a server with an invalid certificate")
			}
		})
	}
}

func TestAPIRedirectsNeverForwardCredentials(t *testing.T) {
	var forwarded atomic.Int32
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		forwarded.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer target.Close()
	tlsTarget := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		forwarded.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer tlsTarget.Close()
	for _, status := range []int{301, 302, 303, 307, 308} {
		for _, destination := range []string{"same origin", "HTTP downgrade", "foreign HTTPS"} {
			t.Run(http.StatusText(status)+"/"+destination, func(t *testing.T) {
				srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					if r.URL.Path == "/redirected" {
						forwarded.Add(1)
						return
					}
					location := target.URL
					switch destination {
					case "same origin":
						location = "/redirected"
					case "foreign HTTPS":
						location = tlsTarget.URL
					}
					w.Header().Set("Location", location)
					w.WriteHeader(status)
				}))
				defer srv.Close()
				client, err := NewClient(config.APIConfig{URL: srv.URL})
				if err != nil {
					t.Fatal(err)
				}
				roots := x509.NewCertPool()
				roots.AddCert(srv.Certificate())
				tr := client.httpClient.Transport.(*http.Transport)
				tr.TLSClientConfig = &tls.Config{RootCAs: roots, MinVersion: tls.VersionTLS12}
				defer tr.CloseIdleConnections()
				client.SetAPIKey("secret-runtime-token")
				_, registerErr := client.RegisterDeviceCredentials(context.Background(), identity.DeviceIdentity{}, "secret-proof", "secret-replacement")
				_, pollErr := client.Poll(context.Background(), "device", telemetry.Payload{}, frp.ConnectionStatus{})
				resultsErr := client.SendCommandResults(context.Background(), "device", nil)
				_, payloadErr := client.FetchCommandPayload(context.Background(), "device", "ref")
				for _, err := range []error{registerErr, pollErr, resultsErr, payloadErr} {
					if err == nil {
						t.Fatal("API redirect accepted as success")
					}
					if strings.Contains(err.Error(), "secret-") {
						t.Fatal("error exposed credentials")
					}
				}
				if forwarded.Load() != 0 {
					t.Fatal("API redirect forwarded credentials")
				}
			})
		}
	}
}
