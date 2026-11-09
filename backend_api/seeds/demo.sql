-- Cartilla, insumos, proveedor y categorías de gasto de demostración (solo dev y staging; seed.sh se niega a cargarlos en prod).
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

-- Insumos de demostración (Fase 6). Sin stock: el stock solo nace de movimientos, así que
-- para probar se registra una compra desde la API.
INSERT INTO ingredient_categories (name) VALUES
    ('Carnes'), ('Panadería'), ('Lácteos'), ('Verduras'), ('Bebidas'), ('Descartables')
ON CONFLICT ((lower(name))) DO NOTHING;

INSERT INTO ingredients (name, category_id, unit_id, min_stock)
SELECT v.name, c.id, u.id, v.min_stock
FROM (VALUES
    ('Carne molida de res',  'Carnes',       'kg',      5.000),
    ('Pechuga de pollo',     'Carnes',       'kg',      3.000),
    ('Tocino',               'Carnes',       'kg',      1.000),
    ('Pan de hamburguesa',   'Panadería',    'unidad', 40.000),
    ('Queso cheddar',        'Lácteos',      'kg',      1.000),
    ('Papa',                 'Verduras',     'kg',     10.000),
    ('Cebolla',              'Verduras',     'kg',      2.000),
    ('Gaseosa 2 l',          'Bebidas',      'unidad',  6.000),
    ('Vasos descartables',   'Descartables', 'paquete', 2.000)
) AS v(name, category, unit, min_stock)
JOIN ingredient_categories c ON lower(c.name) = lower(v.category)
JOIN units u ON u.code = v.unit
ON CONFLICT ((lower(name))) DO NOTHING;

INSERT INTO suppliers (name, phone, notes) VALUES
    ('Distribuidora de demostración', '+59170000001', 'Proveedor ficticio para pruebas.')
ON CONFLICT ((lower(name))) DO NOTHING;

-- Categorías de gasto de demostración (Fase 7). En producción el ADMIN crea las suyas.
INSERT INTO expense_categories (name) VALUES
    ('Alquiler'), ('Servicios básicos'), ('Sueldos'), ('Gas'), ('Mantenimiento'), ('Otros')
ON CONFLICT ((lower(name))) DO NOTHING;
