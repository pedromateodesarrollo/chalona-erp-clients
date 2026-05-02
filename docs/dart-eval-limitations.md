# Limitaciones de `dart_eval`

`dart_eval` es un intérprete de bytecode Dart escrito en Dart puro. Implementa
**la mayor parte** del lenguaje pero no todo. Antes de meter lógica al driver,
verifica que tu código está dentro del subset soportado.

## Lo que funciona ✓

- Sintaxis Dart 3.x: clases, mixins, extension methods (parcial), generics
- `async` / `await` / `Future` / `Stream` (parcial)
- `dart:core` casi completo: `String`, `int`, `double`, `List`, `Map`, `Set`,
  `DateTime`, `Duration`, `RegExp`, `Iterable.where/map/forEach`
- `dart:async`, `dart:math`, `dart:convert` parcial
- Null safety
- Records y patterns (parcial — verificar caso por caso)
- `try/catch/finally`

## Lo que NO funciona ✗

- `dart:mirrors` (no existe en eval)
- `dart:ffi`
- `dart:io` directo (necesitas exponer servicios via `$Bridge`)
- Macros (Dart 3.x macros aún experimentales)
- Algunas combinaciones de generics F-bounded
- Code-gen runtime

## Gotchas reales encontrados

### `num.round()` no existe

```dart
// ✗ Falla
final entero = (v * 100).round();
```

```dart
// ✓ Workaround: redondeo manual con offset
final c = v * 100;
final entero = (c >= 0 ? c + 0.5 : c - 0.5).toInt();
```

### `num` como tipo de parámetro causa boxing inconsistente

```dart
// ✗ Trona en runtime con "type '$double' is not a subtype of type 'num'"
bool tolerancia(num a, num b, double tol) {
  return (a - b).abs() <= tol;
}
```

```dart
// ✓ Usa double específico, no num
bool tolerancia(double a, double b, double tol) {
  final d = a - b;
  return (d < 0 ? -d : d) <= tol;
}
```

`num` no es tratado como primitivo. `int` y `double` sí. Si necesitas
flexibilidad numérica en la API host, hace dispatch manual.

### Pasar argumentos primitivos a funciones eval

Cuando llamas una función eval desde el host:

- `int`, `double`, `bool`, `List` → primitivos directos: `[42, 3.14, true]`
- `String`, `Map`, `Set` → wrapping con `$String('hola')`, `$Map.wrap({...})`

Si el parámetro es `num`, fuerza con `$double(42.0)` o `$int(42)`.

### `String.replaceAll` con regex compleja

Falla en algunos casos. Si el escape solo necesita 1-2 caracteres, escribir
loop manual sale más confiable que pelear con la regex.

```dart
// ✗ A veces falla en eval
final esc = e.replaceAll('"', r'\"').replaceAll(r'\', r'\\');
```

```dart
// ✓ Loop char-by-char, siempre funciona
var safe = '';
for (var k = 0; k < e.length; k++) {
  final ch = e[k];
  if (ch == '"') safe += r'\"';
  else if (ch == r'\') safe += r'\\';
  else safe += ch;
}
```

### `Iterable.map().join()` puede fallar con tipos genéricos

Si el host pasa una `List<dynamic>` y el driver hace `.map((e) => ...).join(',')`,
a veces el bytecode revienta con cast inesperado. Loop manual es alternativa.

## Performance

`dart_eval` es ~5-20× más lento que Dart AOT. Implicaciones:

- ✓ **OK**: validación de comprobantes, transformación de datos, reglas de
  negocio. Una validación que tarda 50ms en AOT toma ~500ms en eval —
  imperceptible para el usuario.
- ✗ **Mal**: hot loops, render UI, parsing pesado, criptografía. Manten esto
  en el host AOT y exponlo al driver vía bridge.

## Estrategia recomendada

1. **Lógica de reglas** (validación, decisión) → driver eval. Cambia con
   frecuencia, vale el costo de boxing.
2. **Servicios primitivos** (HTTP, BD, archivos, crypto) → host AOT, expuestos
   al driver via `$Bridge`.
3. **Modelos compartidos** → en host con bridges generados (boilerplate, pero
   tipado).

## Antes de comprometerte

Haz un PoC chico con tu lógica candidata real. Compila con `dart_eval`,
ejecuta los casos extremos. Si pasa, full speed. Si truena en una feature
crítica, documenta el límite y decide si es bloqueador o se puede refactor.
