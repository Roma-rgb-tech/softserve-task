package service

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"oil-price-tracker/fetcher/internal/model"
	"oil-price-tracker/fetcher/internal/provider"
)

type Publisher interface {
	Publish(context.Context, []model.Observation) error
}

// Observer is told about every collection that ran: how long it took, how many
// observations it published, and the error that ended it, if any.
type Observer func(took time.Duration, published int, err error)

type Service struct {
	provider  provider.Provider
	publisher Publisher
	observe   Observer
	running   bool
	mu        sync.RWMutex
	last      *model.FetchResult
	lastErr   string
}

func New(priceProvider provider.Provider, publisher Publisher) *Service {
	return &Service{provider: priceProvider, publisher: publisher}
}

// Observe registers the function told about every collection that runs.
func (service *Service) Observe(observer Observer) {
	service.observe = observer
}

func (service *Service) Run(ctx context.Context, slot time.Time) (result model.FetchResult, err error) {
	service.mu.Lock()
	if service.running {
		service.mu.Unlock()
		return model.FetchResult{}, fmt.Errorf("collection is already running")
	}
	service.running = true
	service.mu.Unlock()
	started := time.Now()
	defer func() {
		if service.observe != nil {
			service.observe(time.Since(started), result.Published, err)
		}
	}()
	defer func() {
		service.mu.Lock()
		service.running = false
		service.mu.Unlock()
	}()

	slog.Info("starting collection", "scheduled_for", slot)
	observations, err := service.provider.Fetch(ctx, model.TrackedSeries, slot)
	if err != nil {
		service.recordError(err)
		return model.FetchResult{}, fmt.Errorf("fetch prices: %w", err)
	}

	if err := service.publisher.Publish(ctx, observations); err != nil {
		service.recordError(err)
		return model.FetchResult{}, fmt.Errorf("publish observations: %w", err)
	}
	result = model.FetchResult{
		ScheduledFor: slot.UTC(), FetchedAt: time.Now().UTC(), Observations: len(observations),
		Published: len(observations),
	}
	service.mu.Lock()
	service.last = &result
	service.lastErr = ""
	service.mu.Unlock()
	slog.Info("collection published", "observations", result.Published)
	return result, nil
}

func (service *Service) Status() (bool, *model.FetchResult, string) {
	service.mu.RLock()
	defer service.mu.RUnlock()
	var copied *model.FetchResult
	if service.last != nil {
		value := *service.last
		copied = &value
	}
	return service.running, copied, service.lastErr
}

func (service *Service) recordError(err error) {
	service.mu.Lock()
	service.lastErr = err.Error()
	service.mu.Unlock()
	slog.Error("collection failed", "error", err)
}
