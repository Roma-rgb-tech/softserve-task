// Package metrics exposes the fetcher's numbers in the Prometheus text format.
//
// The fetcher has a handful of counters and gauges and no use for the rest of
// a client library, so the format - a line per sample, with HELP and TYPE
// comments - is written out here directly and the module stays without a
// dependency it would only use for this.
package metrics

import (
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
)

type requestKey struct {
	handler string
	method  string
	status  string
}

// Metrics holds every value the fetcher reports. The zero value is not ready
// for use; call New.
type Metrics struct {
	mu sync.Mutex

	collections   map[string]uint64
	published     uint64
	lastSuccess   time.Time
	durationSum   float64
	durationCount uint64
	requests      map[requestKey]uint64

	running func() bool
}

// New returns empty metrics. running reports whether a collection is in
// progress at the moment of a scrape; it may be nil.
func New(running func() bool) *Metrics {
	return &Metrics{
		collections: map[string]uint64{"success": 0, "failure": 0},
		requests:    map[requestKey]uint64{},
		running:     running,
	}
}

// ObserveCollection records one finished collection: how long it took, how
// many observations it published, and whether it failed.
func (metrics *Metrics) ObserveCollection(took time.Duration, published int, err error) {
	metrics.mu.Lock()
	defer metrics.mu.Unlock()

	metrics.durationSum += took.Seconds()
	metrics.durationCount++

	if err != nil {
		metrics.collections["failure"]++
		return
	}

	metrics.collections["success"]++
	metrics.published += uint64(published)
	metrics.lastSuccess = time.Now()
}

// Instrument counts the requests a handler answers, labelled with the route
// pattern it was registered under rather than the raw path.
func (metrics *Metrics) Instrument(pattern string, handler http.HandlerFunc) http.HandlerFunc {
	route := pattern
	if _, path, found := strings.Cut(pattern, " "); found {
		route = path
	}

	return func(response http.ResponseWriter, request *http.Request) {
		recorder := &statusRecorder{ResponseWriter: response, status: http.StatusOK}
		handler(recorder, request)

		metrics.mu.Lock()
		metrics.requests[requestKey{
			handler: route,
			method:  request.Method,
			status:  fmt.Sprintf("%dxx", recorder.status/100),
		}]++
		metrics.mu.Unlock()
	}
}

// ServeHTTP writes every metric in the Prometheus text exposition format.
func (metrics *Metrics) ServeHTTP(response http.ResponseWriter, _ *http.Request) {
	response.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	metrics.write(response)
}

// write writes every metric in the Prometheus text exposition format.
func (metrics *Metrics) write(out io.Writer) {
	metrics.mu.Lock()
	defer metrics.mu.Unlock()

	header(out, "fetcher_collections_total", "counter", "Collections finished, by result.")
	for _, result := range []string{"failure", "success"} {
		fmt.Fprintf(out, "fetcher_collections_total{result=%q} %d\n", result, metrics.collections[result])
	}

	header(out, "fetcher_observations_published_total", "counter", "Observations published to the queue.")
	fmt.Fprintf(out, "fetcher_observations_published_total %d\n", metrics.published)

	header(out, "fetcher_collection_duration_seconds", "summary", "Time a collection took, fetch and publish together.")
	fmt.Fprintf(out, "fetcher_collection_duration_seconds_sum %g\n", metrics.durationSum)
	fmt.Fprintf(out, "fetcher_collection_duration_seconds_count %d\n", metrics.durationCount)

	header(out, "fetcher_last_success_timestamp_seconds", "gauge", "Unix time of the last successful collection, 0 before the first.")
	lastSuccess := 0.0
	if !metrics.lastSuccess.IsZero() {
		lastSuccess = float64(metrics.lastSuccess.UnixNano()) / 1e9
	}
	fmt.Fprintf(out, "fetcher_last_success_timestamp_seconds %g\n", lastSuccess)

	header(out, "fetcher_collection_running", "gauge", "1 while a collection is in progress.")
	running := 0
	if metrics.running != nil && metrics.running() {
		running = 1
	}
	fmt.Fprintf(out, "fetcher_collection_running %d\n", running)

	header(out, "http_requests_total", "counter", "HTTP requests handled, by route pattern, method and status class.")
	keys := make([]requestKey, 0, len(metrics.requests))
	for key := range metrics.requests {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		return fmt.Sprint(keys[i]) < fmt.Sprint(keys[j])
	})
	for _, key := range keys {
		fmt.Fprintf(
			out,
			"http_requests_total{handler=%q,method=%q,status=%q} %d\n",
			key.handler, key.method, key.status, metrics.requests[key],
		)
	}
}

func header(out io.Writer, name, kind, help string) {
	fmt.Fprintf(out, "# HELP %s %s\n# TYPE %s %s\n", name, help, name, kind)
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (recorder *statusRecorder) WriteHeader(status int) {
	recorder.status = status
	recorder.ResponseWriter.WriteHeader(status)
}
