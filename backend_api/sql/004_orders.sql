-- Ventas: pedidos, ítems (con snapshot de nombre y precio) y pagos.

CREATE TABLE orders (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    business_date   date          NOT NULL,
    daily_number    integer       NOT NULL CHECK (daily_number > 0),
    channel         text          NOT NULL CHECK (channel IN ('WHATSAPP', 'LOCAL')),
    status          text          NOT NULL DEFAULT 'PENDIENTE'
                    CHECK (status IN ('PENDIENTE', 'EN_PREPARACION', 'LISTO', 'ENTREGADO', 'CANCELADO')),
    subtotal        numeric(12,2) NOT NULL CHECK (subtotal >= 0),
    discount        numeric(12,2) NOT NULL DEFAULT 0,
    total           numeric(12,2) NOT NULL,
    customer_name   text          CHECK (length(customer_name) <= 120),
    customer_phone  text          CHECK (length(customer_phone) <= 20),
    notes           text          CHECK (length(notes) <= 500),
    created_by      bigint        NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    cancelled_by    bigint        REFERENCES users (id) ON DELETE RESTRICT,
    cancelled_at    timestamptz,
    cancel_reason   text,
    idempotency_key uuid          UNIQUE,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    updated_at      timestamptz   NOT NULL DEFAULT now(),
    UNIQUE (business_date, daily_number),
    CONSTRAINT chk_orders_discount CHECK (discount >= 0 AND discount <= subtotal),
    CONSTRAINT chk_orders_total CHECK (total = subtotal - discount),
    CONSTRAINT chk_orders_cancellation CHECK (
        (status = 'CANCELADO') =
        (cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL AND cancel_reason IS NOT NULL)
    )
);
CREATE INDEX idx_orders_open ON orders (status) WHERE status IN ('PENDIENTE', 'EN_PREPARACION', 'LISTO');
CREATE INDEX idx_orders_created_by ON orders (created_by);
CALL add_updated_at_trigger('orders');
CALL add_no_delete_trigger('orders');

CREATE TABLE order_items (
    id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id              bigint        NOT NULL REFERENCES orders (id) ON DELETE RESTRICT,
    product_id            bigint        NOT NULL REFERENCES products (id) ON DELETE RESTRICT,
    product_name_snapshot text          NOT NULL,
    unit_price_snapshot   numeric(12,2) NOT NULL CHECK (unit_price_snapshot >= 0),
    quantity              integer       NOT NULL CHECK (quantity > 0),
    line_total            numeric(12,2) NOT NULL,
    created_at            timestamptz   NOT NULL DEFAULT now(),
    updated_at            timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT chk_order_items_line_total CHECK (line_total = unit_price_snapshot * quantity)
);
CREATE INDEX idx_order_items_order ON order_items (order_id);
CREATE INDEX idx_order_items_product ON order_items (product_id);
CALL add_updated_at_trigger('order_items');

CREATE TABLE payments (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id        bigint        NOT NULL REFERENCES orders (id) ON DELETE RESTRICT,
    method          text          NOT NULL CHECK (method IN ('EFECTIVO', 'QR')),
    amount          numeric(12,2) NOT NULL CHECK (amount > 0),
    status          text          NOT NULL DEFAULT 'CONFIRMADO' CHECK (status IN ('CONFIRMADO', 'ANULADO')),
    received_by     bigint        NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    voided_by       bigint        REFERENCES users (id) ON DELETE RESTRICT,
    voided_at       timestamptz,
    void_reason     text,
    idempotency_key uuid          UNIQUE,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    updated_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT chk_payments_void CHECK (
        (status = 'ANULADO') = (voided_at IS NOT NULL AND voided_by IS NOT NULL AND void_reason IS NOT NULL)
    )
);
CREATE INDEX idx_payments_order ON payments (order_id);
CALL add_updated_at_trigger('payments');
CALL add_no_delete_trigger('payments');

-- Los ítems solo pueden cambiar mientras el pedido está PENDIENTE y sin pagos; después,
-- el pedido es histórico y la corrección es cancelarlo y crear otro.
CREATE FUNCTION guard_order_items_change() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    target_order bigint := CASE WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;
BEGIN
    IF EXISTS (SELECT 1 FROM orders WHERE id = target_order AND status <> 'PENDIENTE')
       OR EXISTS (SELECT 1 FROM payments WHERE order_id = target_order AND status = 'CONFIRMADO') THEN
        RAISE EXCEPTION 'Los ítems del pedido % ya no se pueden modificar.', target_order
            USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN COALESCE(NEW, OLD);
END
$$;

CREATE TRIGGER trg_order_items_guard
    BEFORE INSERT OR UPDATE OR DELETE ON order_items
    FOR EACH ROW EXECUTE FUNCTION guard_order_items_change();
