import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteService {
  static Future<List<LatLng>> getRoute(LatLng start, LatLng end) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);

    final coords =
        data['routes'][0]['geometry']['coordinates'] as List<dynamic>;

    final polyline = coords
        .map((point) => LatLng(point[1].toDouble(), point[0].toDouble()))
        .toList();

    return polyline;
  }
}
