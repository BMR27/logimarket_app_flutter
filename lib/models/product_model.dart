class ProductModel {
  final int id;
  final String sku;
  final String descripcion;
  final String marca;
  final String modelo;
  final String color;
  final String cantidad;

  ProductModel({
    required this.id,
    required this.sku,
    required this.descripcion,
    required this.marca,
    required this.modelo,
    required this.color,
    required this.cantidad,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
        id: (json['Id'] ?? json['id'] ?? 0) as int,
        sku: json['SKU'] ?? json['sku'] ?? '',
        descripcion: json['Descripcion'] ?? json['descripcion'] ?? '',
        marca: json['Marca'] ?? json['marca'] ?? '',
        modelo: json['Modelo'] ?? json['modelo'] ?? '',
        color: json['Color'] ?? json['color'] ?? '',
        cantidad: json['Cantidad']?.toString() ?? json['cantidad']?.toString() ?? '0',
      );
}
