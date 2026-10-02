package metrics

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func scrape(t *testing.T, metrics *Metrics) string {
	t.Helper()

	recorder := httptest.NewRecorder()
	metrics.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/metrics", nil))

	if got := recorder.Header().Get("Content-Type"); !strings.HasPrefix(got, "text/plain; version=0.0.4") {
		t.Fatalf("content type %q is not the Prometheus text format", got)
	}

	return recorder.Body.String()
}

func TestCollectionsAreCountedByResult(t *testing.T) {
	metrics := New(nil)

	metrics.ObserveCollection(2*time.Second, 7, nil)
	metrics.ObserveCollection(time.Second, 0, errors.New("provider down"))

	body := scrape(t, metrics)

	for _, line := range []string{
		`fetcher_collections_total{result="success"} 1`,
		`fetcher_collections_total{result="failure"} 1`,
		`fetcher_observations_published_total 7`,
		`fetcher_collection_duration_seconds_sum 3`,
		`fetcher_collection_duration_seconds_count 2`,
	} {
		if !strings.Contains(body, line+"\n") {
			t.Errorf("missing %q in:\n%s", line, body)
		}
	}

	if strings.Contains(body, "fetcher_last_success_timestamp_seconds 0\n") {
		t.Error("the last success time stayed at zero after a success")
	}
}

func TestRequestsAreLabelledWithThePattern(t *testing.T) {
	metrics := New(func() bool { return true })

	handler := metrics.Instrument("POST /v1/fetch", func(response http.ResponseWriter, _ *http.Request) {
		response.WriteHeader(http.StatusConflict)
	})
	handler(httptest.NewRecorder(), httptest.NewRequest(http.MethodPost, "/v1/fetch", nil))

	body := scrape(t, metrics)

	if !strings.Contains(body, `http_requests_total{handler="/v1/fetch",method="POST",status="4xx"} 1`+"\n") {
		t.Errorf("the request was not counted under its pattern:\n%s", body)
	}

	if !strings.Contains(body, "fetcher_collection_running 1\n") {
		t.Errorf("the running gauge did not follow the callback:\n%s", body)
	}
}
