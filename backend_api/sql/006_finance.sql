-- Gastos operativos y libro de movimientos financieros.

CREATE TABLE expense_categories (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name       text        NOT NULL CHECK (length(name) BETWEEN 1 AND 60),
    is_active  boolean     NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_expense_categories_name ON expense_categories (lower(name));
CALL add_updated_at_trigger('expense_categories');
CALL add_no_delete_trigger('expense_categories');

CREATE TABLE expenses (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    expense_date    date          NOT NULL,
    category_id     bigint        NOT NULL REFERENCES expense_categories (id) ON DELETE RESTRICT,
    description     text          NOT NULL CHECK (length(description) BETWEEN 1 AND 300),
    amount          numeric(12,2) NOT NULL CHECK (amount > 0),
    payment_method  text          NOT NULL CHECK (payment_method IN ('EFECTIVO', 'QR')),
    status          text          NOT NULL DEFAULT 'CONFIRMADO' CHECK (status IN ('CONFIRMADO', 'ANULADO')),
    created_by      bigint        NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    voided_by       bigint        REFERENCES users (id) ON DELETE RESTRICT,
    voided_at       timestamptz,
    void_reason     text,
    idempotency_key uuid          UNIQUE,
    created_at      timestamptz   NOT NULL DEFAULT now(),
    updated_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT chk_expenses_void CHECK (
        (status = 'ANULADO') = (voided_at IS NOT NULL AND voided_by IS NOT NULL AND void_reason IS NOT NULL)
    )
);
CREATE INDEX idx_expenses_date ON expenses (expense_date);
CREATE INDEX idx_expenses_category ON expenses (category_id);
CALL add_updated_at_trigger('expenses');
CALL add_no_delete_trigger('expenses');

-- Cada fila nace de una operación (pago, compra o gasto). El UNIQUE de origen impide
-- duplicar un ingreso/egreso aunque la API reintente; la anulación es una fila de reverso.
CREATE TABLE financial_transactions (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type          text          NOT NULL CHECK (type IN ('INGRESO', 'EGRESO')),
    category      text          NOT NULL,
    description   text          NOT NULL,
    amount        numeric(12,2) NOT NULL CHECK (amount > 0),
    occurred_at   timestamptz   NOT NULL DEFAULT now(),
    business_date date          NOT NULL,
    source_type   text          NOT NULL CHECK (source_type IN ('PAYMENT', 'PURCHASE', 'EXPENSE')),
    source_id     bigint        NOT NULL,
    is_reversal   boolean       NOT NULL DEFAULT false,
    reverses_id   bigint        REFERENCES financial_transactions (id) ON DELETE RESTRICT,
    created_by    bigint        NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    created_at    timestamptz   NOT NULL DEFAULT now(),
    updated_at    timestamptz   NOT NULL DEFAULT now(),
    UNIQUE (source_type, source_id, is_reversal),
    CONSTRAINT chk_transactions_reversal CHECK (is_reversal = (reverses_id IS NOT NULL))
);
CREATE INDEX idx_transactions_date_type ON financial_transactions (business_date, type);
CREATE INDEX idx_transactions_category ON financial_transactions (category, business_date);
CALL add_append_only_trigger('financial_transactions');
