BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_available_extensions
        WHERE name = 'pgmq'
    ) THEN
        RAISE NOTICE 'pgmq is not available on this server; the deployment is expected to carry a broker instead';
        RETURN;
    END IF;

    EXECUTE 'CREATE EXTENSION IF NOT EXISTS pgmq';

    IF NOT EXISTS (
        SELECT 1
        FROM pgmq.list_queues()
        WHERE queue_name = 'price_observations'
    ) THEN
        PERFORM pgmq.create('price_observations');
    END IF;
END
$$;

COMMIT;
