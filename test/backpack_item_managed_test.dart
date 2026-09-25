// Valida el reporte: un mensajero con 43 órdenes y 5 marcadas Exitosa veía
// "3/43 gestionadas" en Mochilas. Causa: isManaged exigía tanto el escaneo
// manual (isValidated) como el estatus, así que una orden Exitosa sin
// escanear no contaba. Ajuste confirmado con el usuario: Exitosa/Cancelada
// deben contar como gestionadas aunque no se haya escaneado.
import 'package:flutter_test/flutter_test.dart';
import 'package:logimarket_app/models/backpack_item_model.dart';

BackpackItemModel _item({
  required int idStatusOrden,
  required String statusName,
  required int validation,
}) {
  return BackpackItemModel(
    idBackpack: 1,
    idBackpackItem: 1,
    idOrdenVenta: 1,
    folioOrden: 'F1',
    idStatusOrden: idStatusOrden,
    statusName: statusName,
    nombreCliente: 'Cliente',
    validation: validation,
  );
}

void main() {
  test('Exitosa sin escanear SÍ cuenta como gestionada', () {
    final item =
        _item(idStatusOrden: 1, statusName: 'Exitosa', validation: 0);
    expect(item.isManaged, true);
  });

  test('Cancelada sin escanear SÍ cuenta como gestionada', () {
    final item =
        _item(idStatusOrden: 4, statusName: 'Cancelada', validation: 0);
    expect(item.isManaged, true);
  });

  test('Intento de Entrega (1) sin escanear NO cuenta (sigue pendiente de visitar)', () {
    final item = _item(
        idStatusOrden: 5, statusName: 'Intento de Entrega (1)', validation: 0);
    expect(item.isManaged, false);
  });

  test('Intento de Entrega (1) SÍ escaneado cuenta (comportamiento previo, sin cambios)', () {
    final item = _item(
        idStatusOrden: 5, statusName: 'Intento de Entrega (1)', validation: 1);
    expect(item.isManaged, true);
  });

  test('Asignada/On Delivery (aún no tocada) no cuenta como gestionada', () {
    final item =
        _item(idStatusOrden: 2, statusName: 'Asignada', validation: 0);
    expect(item.isManaged, false);
  });
}
