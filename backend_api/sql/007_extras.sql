-- Extras de los productos (huevo, queso, jalapeño, tocino…): catálogo, categorías que los aceptan
-- y extras de cada ítem de pedido. Un extra puede descontar un insumo al registrar el pedido.

CREATE TABLE extras (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                text          NOT NULL CHECK (length(name) BETWEEN 1 AND 60),
    price               numeric(12,2) NOT NULL CHECK (price >= 0),
    ingredient_id       bigint        REFERENCES ingredients (id) ON DELETE RESTRICT,
    ingredient_quantity numeric(12,3),
    sort_order          integer       NOT NULL DEFAULT 0,
    is_active           boolean       NOT NULL DEFAULT true,
    is_available        boolean       NOT NULL DEFAULT true,
    created_at          timestamptz   NOT NULL DEFAULT now(),
    updated_at          timestamptz   NOT NULL DEFAULT now(),
    -- Con insumo, la cantidad es obligatoria y positiva; sin insumo, no hay cantidad.
    -- IS NULL / IS NOT NULL explícitos: con "=" un NULL haría pasar el CHECK.
    CONSTRAINT chk_extras_ingredient CHECK (
        (ingredient_id IS NULL AND ingredient_quantity IS NULL)
        OR (ingredient_id IS NOT NULL AND ingredient_quantity IS NOT NULL AND ingredient_quantity > 0)
    )
);
CREATE UNIQUE INDEX uq_extras_name ON extras (lower(name));
CALL add_updated_at_trigger('extras');
-- Los pedidos históricos apuntan a los extras: se desactivan, no se borran.
CALL add_no_delete_trigger('extras');

-- Qué categorías aceptan cada extra. Es configuración: se reemplaza el conjunto (auditado).
CREATE TABLE category_extras (
    category_id bigint      NOT NULL REFERENCES categories (id) ON DELETE RESTRICT,
    extra_id    bigint      NOT NULL REFERENCES extras (id) ON DELETE RESTRICT,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (category_id, extra_id)
);
CREATE INDEX idx_category_extras_extra ON category_extras (extra_id);

-- Ítems de pedido: nota por ítem y total de extras por unidad (snapshot, como el precio).
ALTER TABLE order_items
    ADD COLUMN notes text CHECK (length(notes) <= 200),
    ADD COLUMN extras_unit_total numeric(12,2) NOT NULL DEFAULT 0 CHECK (extras_unit_total >= 0),
    DROP CONSTRAINT chk_order_items_line_total,
    ADD CONSTRAINT chk_order_items_line_total CHECK (line_total = (unit_price_snapshot + extras_unit_total) * quantity);

-- Extras de cada ítem. Guarda nombre, precio e insumo del momento de la venta: así un cambio
-- posterior del extra no altera el pedido y el reverso devuelve exactamente lo descontado.
CREATE TABLE order_item_extras (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id            bigint        NOT NULL REFERENCES orders (id) ON DELETE RESTRICT,
    order_item_id       bigint        NOT NULL REFERENCES order_items (id) ON DELETE RESTRICT,
    extra_id            bigint        NOT NULL REFERENCES extras (id) ON DELETE RESTRICT,
    name_snapshot       text          NOT NULL,
    unit_price_snapshot numeric(12,2) NOT NULL CHECK (unit_price_snapshot >= 0),
    quantity            integer       NOT NULL CHECK (quantity BETWEEN 1 AND 5),
    ingredient_id       bigint        REFERENCES ingredients (id) ON DELETE RESTRICT,
    ingredient_quantity numeric(12,3),
    created_at          timestamptz   NOT NULL DEFAULT now(),
    updated_at          timestamptz   NOT NULL DEFAULT now(),
    UNIQUE (order_item_id, extra_id),
    CONSTRAINT chk_order_item_extras_ingredient CHECK (
        (ingredient_id IS NULL AND ingredient_quantity IS NULL)
        OR (ingredient_id IS NOT NULL AND ingredient_quantity IS NOT NULL AND ingredient_quantity > 0)
    )
);
CREATE INDEX idx_order_item_extras_order ON order_item_extras (order_id);
CREATE INDEX idx_order_item_extras_extra ON order_item_extras (extra_id);
CALL add_updated_at_trigger('order_item_extras');
-- Misma regla que los ítems: solo cambian con el pedido PENDIENTE y sin pagos.
CREATE TRIGGER trg_order_item_extras_guard
    BEFORE INSERT OR UPDATE OR DELETE ON order_item_extras
    FOR EACH ROW EXECUTE FUNCTION guard_order_items_change();

-- El consumo de un extra se registra con su propio origen (UNIQUE de origen: nunca dos veces).
ALTER TABLE inventory_movements
    DROP CONSTRAINT inventory_movements_source_type_check,
    ADD CONSTRAINT inventory_movements_source_type_check
        CHECK (source_type IN ('PURCHASE_ITEM', 'ORDER_ITEM', 'ORDER_ITEM_EXTRA'));
