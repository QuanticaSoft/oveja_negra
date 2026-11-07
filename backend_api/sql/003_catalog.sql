-- Cartilla: categorías, productos e historial de precios.

CREATE TABLE categories (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       text        NOT NULL CHECK (length(name) BETWEEN 1 AND 60),
    sort_order integer     NOT NULL DEFAULT 0,
    is_active  boolean     NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_categories_name ON categories (lower(name));
CALL add_updated_at_trigger('categories');
CALL add_no_delete_trigger('categories');

CREATE TABLE products (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id  bigint        NOT NULL REFERENCES categories (id) ON DELETE RESTRICT,
    name         text          NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
    description  text          CHECK (length(description) <= 500),
    price        numeric(12,2) NOT NULL CHECK (price >= 0),
    image_path   text,
    is_active    boolean       NOT NULL DEFAULT true,
    is_available boolean       NOT NULL DEFAULT true,
    created_at   timestamptz   NOT NULL DEFAULT now(),
    updated_at   timestamptz   NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_products_category_name ON products (category_id, lower(name));
CALL add_updated_at_trigger('products');
-- Los pedidos históricos apuntan a los productos: se desactivan, no se borran.
CALL add_no_delete_trigger('products');

CREATE TABLE product_price_history (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id bigint        NOT NULL REFERENCES products (id) ON DELETE RESTRICT,
    old_price  numeric(12,2) NOT NULL CHECK (old_price >= 0),
    new_price  numeric(12,2) NOT NULL CHECK (new_price >= 0),
    changed_by bigint        NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    created_at timestamptz   NOT NULL DEFAULT now(),
    updated_at timestamptz   NOT NULL DEFAULT now()
);
CREATE INDEX idx_price_history_product ON product_price_history (product_id, created_at);
CALL add_append_only_trigger('product_price_history');
