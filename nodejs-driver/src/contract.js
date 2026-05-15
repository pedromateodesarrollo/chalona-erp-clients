// Contrato que debe cumplir cualquier driver Node.js cargado por el loader:
//
//   class DriverV1 {
//     version = 'v1';
//     preValidar(comprobante) { return { ok, errores: [] }; }
//   }
//
// El motor (driver_src/driver-comprobantes.js) se sube tal cual a Postgres
// vía data.nodejs_cliente_driver y el loader lo carga con vm.Script en sandbox.

export {};
