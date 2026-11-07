-- Usuarios, roles y permisos (RBAC), sesiones y auditoría.

CREATE TABLE roles (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code       text        NOT NULL UNIQUE CHECK (code ~ '^[A-Z_]{3,30}$'),
    name       text        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CALL add_updated_at_trigger('roles');

CREATE TABLE permissions (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        text        NOT NULL UNIQUE CHECK (code ~ '^[a-z_]+\.[a-z_]+$'),
    description text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CALL add_updated_at_trigger('permissions');

CREATE TABLE role_permissions (
    role_id       bigint      NOT NULL REFERENCES roles (id) ON DELETE CASCADE,
    permission_id bigint      NOT NULL REFERENCES permissions (id) ON DELETE CASCADE,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (role_id, permission_id)
);
CREATE INDEX idx_role_permissions_permission ON role_permissions (permission_id);
CALL add_updated_at_trigger('role_permissions');

CREATE TABLE users (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username      text        NOT NULL UNIQUE CHECK (username ~ '^[a-z0-9._-]{3,40}$'),
    phone         text        UNIQUE CHECK (phone ~ '^\+591[0-9]{8}$'),
    full_name     text        NOT NULL CHECK (length(full_name) BETWEEN 1 AND 120),
    password_hash text        NOT NULL,
    role_id       bigint      NOT NULL REFERENCES roles (id) ON DELETE RESTRICT,
    is_active     boolean     NOT NULL DEFAULT true,
    last_login_at timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_users_role ON users (role_id);
CALL add_updated_at_trigger('users');
-- Los usuarios se desactivan, no se borran: las operaciones históricas apuntan a ellos.
CALL add_no_delete_trigger('users');

CREATE TABLE refresh_tokens (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     bigint      NOT NULL REFERENCES users (id) ON DELETE RESTRICT,
    token_hash  text        NOT NULL UNIQUE,
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz,
    replaced_by bigint      REFERENCES refresh_tokens (id) ON DELETE RESTRICT,
    user_agent  text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_refresh_tokens_user_active ON refresh_tokens (user_id) WHERE revoked_at IS NULL;
CALL add_updated_at_trigger('refresh_tokens');

CREATE TABLE auth_attempts (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ip         inet        NOT NULL,
    identifier text        NOT NULL,
    success    boolean     NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_auth_attempts_identifier ON auth_attempts (identifier, created_at);
CREATE INDEX idx_auth_attempts_ip ON auth_attempts (ip, created_at);

CREATE TABLE audit_logs (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    bigint      REFERENCES users (id) ON DELETE RESTRICT,
    entity     text        NOT NULL,
    entity_id  bigint,
    action     text        NOT NULL,
    before     jsonb,
    after      jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_logs_entity ON audit_logs (entity, entity_id);
CREATE INDEX idx_audit_logs_created ON audit_logs (created_at);
CALL add_append_only_trigger('audit_logs');

-- Semilla: los roles y permisos son datos, así el ADMIN puede reasignarlos sin tocar código.
INSERT INTO roles (code, name) VALUES
    ('ADMIN',     'Administrador'),
    ('CAJERO',    'Cajero'),
    ('ENCARGADO', 'Encargado');

INSERT INTO permissions (code, description) VALUES
    ('users.manage',              'Administrar usuarios'),
    ('roles.manage',              'Administrar roles y permisos'),
    ('catalog.read',              'Consultar cartilla, productos y categorías'),
    ('catalog.manage',            'Administrar productos, precios y categorías'),
    ('products.availability',     'Cambiar disponibilidad de productos'),
    ('orders.create',             'Registrar pedidos'),
    ('orders.read',               'Consultar pedidos'),
    ('orders.update_status',      'Cambiar estado de pedidos'),
    ('orders.discount',           'Aplicar descuentos a pedidos'),
    ('orders.cancel',             'Cancelar pedidos'),
    ('payments.create',           'Registrar pagos'),
    ('payments.void',             'Anular pagos'),
    ('suppliers.manage',          'Administrar proveedores'),
    ('ingredients.read',          'Consultar insumos'),
    ('ingredients.manage',        'Administrar insumos'),
    ('purchases.create',          'Registrar compras'),
    ('purchases.read',            'Consultar compras'),
    ('purchases.void',            'Anular compras'),
    ('inventory.read',            'Consultar inventario y movimientos'),
    ('inventory.adjust',          'Registrar ajustes de inventario'),
    ('inventory.consume',         'Registrar salidas por consumo'),
    ('expenses.create',           'Registrar gastos'),
    ('expenses.read',             'Consultar gastos'),
    ('expenses.void',             'Anular gastos'),
    ('expense_categories.manage', 'Administrar categorías de gasto'),
    ('finance.read',              'Consultar movimientos financieros'),
    ('dashboard.read',            'Ver dashboard'),
    ('reports.read',              'Ver reportes');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r CROSS JOIN permissions p WHERE r.code = 'ADMIN';

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.code IN (
    'catalog.read', 'products.availability',
    'orders.create', 'orders.read', 'orders.update_status', 'orders.discount',
    'payments.create'
) WHERE r.code = 'CAJERO';

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.code IN (
    'catalog.read',
    'suppliers.manage', 'ingredients.read', 'ingredients.manage',
    'purchases.create', 'purchases.read', 'purchases.void',
    'inventory.read', 'inventory.adjust', 'inventory.consume',
    'expenses.create', 'expenses.read', 'expenses.void',
    'finance.read', 'dashboard.read', 'reports.read'
) WHERE r.code = 'ENCARGADO';
