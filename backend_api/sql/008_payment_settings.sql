-- Configuración de cobro: datos de la cuenta del negocio y la imagen del QR que generó el banco.
-- Es una sola fila (id = 1): la app la muestra en pantalla para que el cliente pague por QR.

CREATE TABLE payment_settings (
    id             integer     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    bank_name      text        CHECK (length(bank_name) <= 80),
    account_holder text        CHECK (length(account_holder) <= 120),
    account_number text        CHECK (length(account_number) <= 40),
    qr_image_path  text,
    updated_by     bigint      REFERENCES users (id) ON DELETE RESTRICT,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);
CALL add_updated_at_trigger('payment_settings');
CALL add_no_delete_trigger('payment_settings');
INSERT INTO payment_settings (id) VALUES (1) ON CONFLICT DO NOTHING;

INSERT INTO permissions (code, description) VALUES ('settings.manage', 'Configurar cobro (cuenta y QR)')
ON CONFLICT (code) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r JOIN permissions p ON p.code = 'settings.manage' WHERE r.code = 'ADMIN'
ON CONFLICT DO NOTHING;
