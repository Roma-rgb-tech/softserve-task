package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"oil-price-tracker/fetcher/internal/model"
)

type stubProvider struct {
	observations []model.Observation
}

func (provider stubProvider) Fetch(
	context.Context,
	[]model.Series,
	time.Time,
) ([]model.Observation, error) {
	return provider.observations, nil
}

type stubPublisher struct {
	published int
}

func (publisher *stubPublisher) Publish(
	_ context.Context,
	observations []model.Observation,
) error {
	publisher.published += len(observations)
	return nil
}

func TestRunPublishesFetchedObservations(t *testing.T) {
	slot := time.Date(2026, 7, 27, 6, 0, 0, 0, time.UTC)
	publisher := &stubPublisher{}
	collector := New(
		stubProvider{observations: []model.Observation{
			{InstrumentCode: "WTI_USD_BBL", ScheduledFor: slot},
			{InstrumentCode: "BRENT_USD_BBL", ScheduledFor: slot},
		}},
		publisher,
	)

	result, err := collector.Run(context.Background(), slot)
	if err != nil {
		t.Fatalf("unexpected collection error: %v", err)
	}
	if result.Published != 2 || publisher.published != 2 {
		t.Fatalf("unexpected publish result: %+v, publisher=%d", result, publisher.published)
	}
}

type failingPublisher struct{}

func (failingPublisher) Publish(context.Context, []model.Observation) error {
	return errors.New("queue unavailable")
}

func TestObserverHearsEveryCollection(t *testing.T) {
	slot := time.Date(2026, 7, 27, 6, 0, 0, 0, time.UTC)
	observations := []model.Observation{{InstrumentCode: "WTI_USD_BBL", ScheduledFor: slot}}

	var published []int
	var failures int
	record := func(_ time.Duration, count int, err error) {
		published = append(published, count)
		if err != nil {
			failures++
		}
	}

	healthy := New(stubProvider{observations: observations}, &stubPublisher{})
	healthy.Observe(record)
	if _, err := healthy.Run(context.Background(), slot); err != nil {
		t.Fatalf("unexpected collection error: %v", err)
	}

	broken := New(stubProvider{observations: observations}, failingPublisher{})
	broken.Observe(record)
	if _, err := broken.Run(context.Background(), slot); err == nil {
		t.Fatal("expected the publish error to surface")
	}

	if len(published) != 2 || published[0] != 1 || published[1] != 0 || failures != 1 {
		t.Fatalf("observer saw published=%v failures=%d", published, failures)
	}
}
