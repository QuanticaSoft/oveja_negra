-- Modalidad de entrega del pedido (consumir en el local, recoger o delivery) y costo de envío.
-- El envío es parte del total que se cobra; el descuento sigue aplicando solo a los productos.

ALTER TABLE orders
    ADD COLUMN fulfillment         text          NOT NULL DEFAULT 'CONSUMO_LOCAL'
               CHECK (fulfillment IN ('CONSUMO_LOCAL', 'RECOGER', 'DELIVERY')),
    ADD COLUMN delivery_fee        numeric(12,2) NOT NULL DEFAULT 0 CHECK (delivery_fee >= 0),
    ADD COLUMN delivery_address    text          CHECK (length(delivery_address) BETWEEN 1 AND 300),
    ADD COLUMN delivery_references text          CHECK (length(delivery_references) BETWEEN 1 AND 300),
    ADD COLUMN delivery_lat        numeric(9,6)  CHECK (delivery_lat BETWEEN -90 AND 90),
    ADD COLUMN delivery_lng        numeric(9,6)  CHECK (delivery_lng BETWEEN -180 AND 180),
    DROP CONSTRAINT chk_orders_total,
    ADD CONSTRAINT chk_orders_total CHECK (total = subtotal - discount + delivery_fee),
    -- Delivery exige dirección; las otras modalidades no llevan envío ni datos de entrega.
    -- IS NULL / IS NOT NULL explícitos: con "=" un NULL haría pasar el CHECK.
    ADD CONSTRAINT chk_orders_delivery CHECK (
        (fulfillment = 'DELIVERY' AND delivery_address IS NOT NULL)
        OR (fulfillment <> 'DELIVERY' AND delivery_fee = 0 AND delivery_address IS NULL
            AND delivery_references IS NULL AND delivery_lat IS NULL AND delivery_lng IS NULL)
    ),
    ADD CONSTRAINT chk_orders_delivery_location CHECK ((delivery_lat IS NULL) = (delivery_lng IS NULL));
