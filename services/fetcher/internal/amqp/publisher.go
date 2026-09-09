package amqp

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"oil-price-tracker/fetcher/internal/model"
	"oil-price-tracker/fetcher/internal/provider"
	"oil-price-tracker/fetcher/internal/queue"
)

type Publisher struct {
	DB        *sql.DB
	URL       string
	QueueName string
	Timeout   time.Duration
}

func (publisher Publisher) Publish(
	ctx context.Context,
	observations []model.Observation,
) error {
	eventKey, body, err := queue.Encode(observations)
	if err != nil {
		return err
	}

	return provider.Retry(
		ctx,
		5,
		time.Second,
		func() error {
			return publisher.publishOnce(ctx, eventKey, body)
		},
	)
}

func (publisher Publisher) publishOnce(
	ctx context.Context,
	eventKey string,
	body []byte,
) error {
	claimed, err := publisher.claim(ctx, eventKey)
	if err != nil {
		return err
	}

	if !claimed {
		return nil
	}

	if err := publisher.send(ctx, eventKey, body); err != nil {
		publisher.release(ctx, eventKey)

		return err
	}

	return nil
}

func (publisher Publisher) claim(
	ctx context.Context,
	eventKey string,
) (bool, error) {
	var claimedEventKey string

	err := publisher.DB.QueryRowContext(
		ctx,
		`
		INSERT INTO published_queue_events (
			event_key
		)
		VALUES ($1)
		ON CONFLICT (event_key) DO NOTHING
		RETURNING event_key
		`,
		eventKey,
	).Scan(&claimedEventKey)

	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}

	if err != nil {
		return false, fmt.Errorf(
			"claim event key: %w",
			err,
		)
	}

	return true, nil
}

func (publisher Publisher) release(
	ctx context.Context,
	eventKey string,
) {
	_, _ = publisher.DB.ExecContext(
		ctx,
		`
		DELETE FROM published_queue_events
		WHERE event_key = $1
		`,
		eventKey,
	)
}

func (publisher Publisher) send(
	ctx context.Context,
	eventKey string,
	body []byte,
) error {
	connection, err := amqp.Dial(publisher.URL)
	if err != nil {
		return fmt.Errorf(
			"connect to the broker: %w",
			err,
		)
	}
	defer connection.Close()

	channel, err := connection.Channel()
	if err != nil {
		return fmt.Errorf(
			"open a broker channel: %w",
			err,
		)
	}
	defer channel.Close()

	if err := channel.Confirm(false); err != nil {
		return fmt.Errorf(
			"ask the broker for publish confirmations: %w",
			err,
		)
	}

	if _, err := channel.QueueDeclare(
		publisher.QueueName,
		true,
		false,
		false,
		false,
		nil,
	); err != nil {
		return fmt.Errorf(
			"declare queue %q: %w",
			publisher.QueueName,
			err,
		)
	}

	publishContext, cancel := context.WithTimeout(ctx, publisher.timeout())
	defer cancel()

	confirmation, err := channel.PublishWithDeferredConfirmWithContext(
		publishContext,
		"",
		publisher.QueueName,
		true,
		false,
		amqp.Publishing{
			ContentType:  "application/json",
			DeliveryMode: amqp.Persistent,
			MessageId:    eventKey,
			Timestamp:    time.Now().UTC(),
			Body:         body,
		},
	)
	if err != nil {
		return fmt.Errorf(
			"publish observation event: %w",
			err,
		)
	}

	acknowledged, err := confirmation.WaitContext(publishContext)
	if err != nil {
		return fmt.Errorf(
			"wait for the broker to confirm: %w",
			err,
		)
	}

	if !acknowledged {
		return fmt.Errorf(
			"the broker refused observation event %s",
			eventKey,
		)
	}

	return nil
}

func (publisher Publisher) timeout() time.Duration {
	if publisher.Timeout > 0 {
		return publisher.Timeout
	}

	return 15 * time.Second
}
