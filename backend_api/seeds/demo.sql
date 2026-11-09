-- Cartilla de demostración (solo dev y staging; seed.sh se niega a cargarla en prod).
-- Idempotente: si una categoría o producto ya existe (mismo nombre), no se toca.
-- Las fotos son de seeds/media/ (ver seeds/media/CREDITS.md).

INSERT INTO categories (name, sort_order) VALUES
    ('Hamburguesas',     1),
    ('Acompañamientos',  2),
    ('Bebidas',          3)
ON CONFLICT ((lower(name))) DO NOTHING;

INSERT INTO products (category_id, name, description, price, image_path)
SELECT c.id, v.name, v.description, v.price, v.image_path
FROM (VALUES
    ('Hamburguesas',    'Clásica',          'Carne de res a la parrilla, lechuga y pan suave.',              25.00, 'demo/clasica.jpg'),
    ('Hamburguesas',    'Con queso',        'Carne de res, queso cheddar fundido, lechuga y pan con sésamo.', 28.00, 'demo/con-queso.jpg'),
    ('Hamburguesas',    'Bacon',            'Carne de res con tocino crocante.',                              32.00, 'demo/bacon.jpg'),
    ('Hamburguesas',    'Pollo crispy',     'Pollo apanado, tocino, queso, tomate y salsa de la casa.',       30.00, 'demo/pollo-crispy.jpg'),
    ('Acompañamientos', 'Papas fritas',     'Porción de papas fritas.',                                       12.00, 'demo/papas-fritas.jpg'),
    ('Acompañamientos', 'Aros de cebolla',  'Aros de cebolla apanados.',                                      14.00, 'demo/aros-de-cebolla.jpg'),
    ('Bebidas',         'Gaseosa',          'Vaso de gaseosa con hielo.',                                      8.00, 'demo/gaseosa.jpg'),
    ('Bebidas',         'Limonada',         'Limonada natural.',                                              10.00, 'demo/limonada.jpg')
) AS v(category, name, description, price, image_path)
JOIN categories c ON lower(c.name) = lower(v.category)
ON CONFLICT (category_id, (lower(name))) DO NOTHING;
