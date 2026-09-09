package queue

import (
	"encoding/json"
	"fmt"
	"time"

	"oil-price-tracker/fetcher/internal/model"
)

type BatchMessage struct {
	SchemaVersion int                 `json:"schema_version"`
	EventKey      string              `json:"event_key"`
	Observations  []model.Observation `json:"observations"`
}

func Encode(observations []model.Observation) (string, []byte, error) {
	if len(observations) == 0 {
		return "", nil, fmt.Errorf(
			"cannot publish an empty observation event",
		)
	}

	eventKey := "oil-prices:" +
		observations[0].
			ScheduledFor.
			UTC().
			Format(time.RFC3339)

	body, err := json.Marshal(
		BatchMessage{
			SchemaVersion: 1,
			EventKey:      eventKey,
			Observations:  observations,
		},
	)
	if err != nil {
		return "", nil, fmt.Errorf(
			"encode observation event: %w",
			err,
		)
	}

	return eventKey, body, nil
}
