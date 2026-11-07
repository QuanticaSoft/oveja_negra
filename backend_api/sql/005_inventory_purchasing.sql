-- Compras de insumos e inventario.

CREATE TABLE suppliers (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       text        NOT NULL CHECK (length(name) BETWEEN 1 AND 120),
    phone      text        CHECK (length(phone) <= 20),
    notes      text        CHECK (length(notes) <= 500),
    is_active  boolean     NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_suppliers_name ON suppliers (lower(name));
CALL add_updated_at_trigger('suppliers');
CALL add_no_delete_trigger('suppliers');

CREATE TABLE units (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code       text        NOT NULL UNIQUE,
    name       text        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CALL add_updated_at_trigger('units');

INSERT INTO units (code, name) VALUES
    ('kg',      'Kilogramo'),
    ('g',       'Gramo'),
    ('l',       'Litro'),
    ('ml',      'Mililitro'),
    ('unidad',  'Unidad'),
    ('paquete', 'Paquete');

CREATE TABLE ingredient_categories (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       text        NOT NULL CHECK (length(name) BETWEEN 1 AND 60),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_ingredient_categories_name ON ingredient_categories (lower(name));
CALL add_updated_at_trigger('ingredient_categories');

CREATE TABLE ingredients (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          text          NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
    category_id   bigint        NOT NULL REFERENCES ingredient_categories (id) ON DELETE RESTRICT,
    unit_id       bigint        NOT NULL REFERENCES units (id) ON DELETE RESTRICT,
    -- Caché de SUM(inventory_movements.quantity); se actualiza en la misma transacción que el movimiento.
    current_stock numeric(12,3) NOT NULL DEFAULT 0 CHECK (current_stock >= 0),
    min_stock     numeric(12,3) NOT NULL DEFAULT 0 CHECK (min_stock >= 0),
    -- Promedio ponderado: base del costo real por hamburguesa en la Etapa 2 (recetas).
    avg_unit_cost numeric(12,4) NOT NULL DEFAULT 0 CHECK (avg_unit_cost >= 0),
    is_active     boolean       NOT NULL DEFAULT true,
    created_at    timestamptz   NOT NULL DEFAULT now(),
    updated_at    timestamptz   NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_ingredients_name ON ingredients (lower(name));
CREATE INDEX idx_ingredients_low_stock ON ingredients (id) WHERE is_active AND current_stock <= min_stock;
CALL add_updated_at_trigger('ingredients');
CALL add_no_delete_trigger('ingredients');

CREATE TABLE purchases (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purchase_date   date          NOT NULL,
    supplier_id     bigint        REFERENCES suppliers (id) ON DELETE RESTRICT,
    receipt_number  text          CHECK (length(receipt_number) <= 40),
    payment_method  text          NOT NULL CHECK (payment_method IN ('EFECTIVO', 'QR')),
    total           numeric(12,2) NOT NULL CHECK (total >= 0),
    status          text          NOT NULL DEFAULT 'CONFIRMADA' CHECK (status IN ('CONFIRMADA', 'ANULADA')),
    created_by      bigint        NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    voided_by       bigint        REFERENCES users (id) ON DELETE RESTRICT,
    voided_at       timestamptz,
    void_reason     text,
    idempotency_key uuid          UNIQUE,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    updated_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT chk_purchases_void CHECK (
        (status = 'ANULADA') = (voided_at IS NOT NULL AND voided_by IS NOT NULL AND void_reason IS NOT NULL)
    )
);
CREATE INDEX idx_purchases_date ON purchases (purchase_date);
CREATE INDEX idx_purchases_supplier ON purchases (supplier_id);
CALL add_updated_at_trigger('purchases');
CALL add_no_delete_trigger('purchases');

CREATE TABLE purchase_items (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purchase_id   bigint        NOT NULL REFERENCES purchases (id) ON DELETE RESTRICT,
    ingredient_id bigint        NOT NULL REFERENCES ingredients (id) ON DELETE RESTRICT,
    quantity      numeric(12,3) NOT NULL CHECK (quantity > 0),
    unit_price    numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    line_total    numeric(12,2) NOT NULL,
    created_at    timestamptz   NOT NULL DEFAULT now(),
    updated_at    timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT chk_purchase_items_line_total CHECK (line_total = round(quantity * unit_price, 2))
);
CREATE INDEX idx_purchase_items_purchase ON purchase_items (purchase_id);
CREATE INDEX idx_purchase_items_ingredient ON purchase_items (ingredient_id);
-- Una compra confirmada no se edita: se anula y se registra otra.
CALL add_append_only_trigger('purchase_items');

CREATE TABLE inventory_movements (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingredient_id bigint        NOT NULL REFERENCES ingredients (id) ON DELETE RESTRICT,
    type          text          NOT NULL CHECK (type IN ('ENTRADA_COMPRA', 'SALIDA_CONSUMO', 'AJUSTE', 'REVERSO')),
    quantity      numeric(12,3) NOT NULL CHECK (quantity <> 0),
    unit_cost     numeric(12,4) CHECK (unit_cost >= 0),
    stock_after   numeric(12,3) NOT NULL CHECK (stock_after >= 0),
    -- PURCHASE_ITEM: entrada o reverso de una compra. ORDER_ITEM: consumo por receta (Etapa 2).
    source_type   text          CHECK (source_type IN ('PURCHASE_ITEM', 'ORDER_ITEM')),
    source_id     bigint,
    reason        text          CHECK (length(reason) <= 300),
    created_by    bigint        NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    created_at    timestamptz   NOT NULL DEFAULT now(),
    updated_at    timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT chk_movements_source CHECK ((source_type IS NULL) = (source_id IS NULL)),
    CONSTRAINT chk_movements_sign CHECK (
        (type = 'ENTRADA_COMPRA' AND quantity > 0) OR
        (type = 'SALIDA_CONSUMO' AND quantity < 0) OR
        type IN ('AJUSTE', 'REVERSO')
    ),
    -- IS NOT DISTINCT FROM: con "=" un source_type NULL daría NULL y el CHECK lo dejaría pasar.
    CONSTRAINT chk_movements_purchase_source CHECK (
        type <> 'ENTRADA_COMPRA' OR source_type IS NOT DISTINCT FROM 'PURCHASE_ITEM'
    ),
    CONSTRAINT chk_movements_adjust_reason CHECK (type <> 'AJUSTE' OR reason IS NOT NULL)
);
CREATE UNIQUE INDEX uq_movements_source ON inventory_movements (source_type, source_id, type)
    WHERE source_id IS NOT NULL;
CREATE INDEX idx_movements_ingredient ON inventory_movements (ingredient_id, created_at);
CALL add_append_only_trigger('inventory_movements');
