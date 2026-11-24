import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ApiService {
  // Base URL server Laravel lokal (pastikan sesuai IPv4 Wi-Fi laptop)
  static const String baseUrl = 'http://127.0.0.1:8000/api';

  // ==========================================
  // 1. IDENTITAS PERANGKAT & FCM (TANPA LOGIN)
  // ==========================================
  static Future<String> getDeviceUuid() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('sawitscan_device_uuid');
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString('sawitscan_device_uuid', deviceId);
    }
    return deviceId;
  }

  static Future<void> registerDevice(String? fcmToken) async {
    try {
      final uuid = await getDeviceUuid();
      await http
          .post(
            Uri.parse('$baseUrl/devices'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'device_uuid': uuid,
              'fcm_token': fcmToken,
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      // Abaikan jika perangkat sedang offline di area kebun
    }
  }

  // ==========================================
  // 2. CRUD RIWAYAT SCAN KEMATANGAN TBS
  // ==========================================

  // CREATE: Upload foto & simpan riwayat scan
  static Future<bool> uploadScan({
    File? imageFile,
    required String blokKebun,
    required String modelAi,
    required String hasilKelas,
    required double confidence,
    String? catatan,
  }) async {
    try {
      final uuid = await getDeviceUuid();
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/scans'));
      request.headers['Accept'] = 'application/json';

      request.fields['device_uuid'] = uuid;
      request.fields['block_name'] = blokKebun;
      request.fields['model_used'] = modelAi;
      request.fields['maturity_label'] = hasilKelas;
      request.fields['confidence'] = confidence.toString();

      if (catatan != null && catatan.isNotEmpty) {
        request.fields['notes'] = catatan;
      }

      if (imageFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('image', imageFile.path),
        );
      }

      var streamedResponse =
          await request.send().timeout(const Duration(seconds: 8));
      return streamedResponse.statusCode == 201 ||
          streamedResponse.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // READ: Ambil semua riwayat scan milik perangkat ini
  static Future<List<dynamic>> fetchScans() async {
    try {
      final uuid = await getDeviceUuid();
      final response = await http
          .get(
            Uri.parse('$baseUrl/scans?device_uuid=$uuid'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['data'] as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  // UPDATE: Edit blok atau catatan
  static Future<bool> updateScan(int id, String blokKebun, String catatan) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/scans/$id'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'block_name': blokKebun,
              'notes': catatan,
            }),
          )
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // DELETE: Hapus riwayat scan
  static Future<bool> deleteScan(int id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/scans/$id'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ==========================================
  // 3. KALENDER & ESTIMASI PANEN SEJAK TANAM
  // ==========================================

  // Cache lokal untuk akses instan & offline
  static Future<List<dynamic>> getCachedSchedules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_schedules');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        return jsonDecode(cachedJson) as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  // READ: Ambil daftar jadwal tanam & estimasi panen (cepat & offline-first)
  static Future<List<dynamic>> fetchSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedList = await getCachedSchedules();

    try {
      final uuid = await getDeviceUuid();
      final response = await http
          .get(
            Uri.parse('$baseUrl/schedules?device_uuid=$uuid'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = (body['data'] as List<dynamic>?) ?? [];
        await prefs.setString('cached_schedules', jsonEncode(data));
        return data;
      }
    } catch (_) {
      // Offline: langsung kembalikan cache lokal
    }

    return cachedList;
  }

  // CREATE: Simpan tanggal awal tanam & hitung estimasi panen (+30 bulan)
  static Future<Map<String, dynamic>> createSchedule({
    required String blockName,
    required String variety,
    required String plantingDate, // Format: YYYY-MM-DD
    int harvestIntervalDays = 14,
  }) async {
    final uuid = await getDeviceUuid();
    final prefs = await SharedPreferences.getInstance();

    final plantingDt = DateTime.tryParse(plantingDate) ?? DateTime.now();
    final firstHarvest =
        DateTime(plantingDt.year, plantingDt.month + 30, plantingDt.day);
    final firstHarvestStr =
        '${firstHarvest.year.toString().padLeft(4, '0')}-${firstHarvest.month.toString().padLeft(2, '0')}-${firstHarvest.day.toString().padLeft(2, '0')}';

    final localItem = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'device_uuid': uuid,
      'block_name': blockName,
      'variety': variety,
      'planting_date': plantingDate,
      'first_harvest_date': firstHarvestStr,
      'next_harvest_date': firstHarvestStr,
      'harvest_interval_days': harvestIntervalDays,
    };

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/schedules'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'device_uuid': uuid,
              'block_name': blockName,
              'variety': variety,
              'planting_date': plantingDate,
              'harvest_interval_days': harvestIntervalDays,
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 201 || response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final serverData = body['data'] ?? localItem;
        final cached = await getCachedSchedules();
        cached.removeWhere((c) => c['id'] == serverData['id']);
        cached.insert(0, serverData);
        await prefs.setString('cached_schedules', jsonEncode(cached));
        return body;
      }
    } catch (_) {
      // Offline fallback
    }

    // Simpan ke cache lokal offline
    final cached = await getCachedSchedules();
    cached.insert(0, localItem);
    await prefs.setString('cached_schedules', jsonEncode(cached));
    return {'data': localItem};
  }

  // DELETE: Hapus jadwal tanam
  static Future<bool> deleteSchedule(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = await getCachedSchedules();
    cached.removeWhere((item) => item['id'] == id);
    await prefs.setString('cached_schedules', jsonEncode(cached));

    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/schedules/$id'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return true; // Sukses di cache lokal
    }
  }
}