import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Urutan HARUS sama dengan urutan kelas saat pelatihan model.
const List<String> kClassNames = [
  'Belum Matang',
  'Matang',
  'Lewat Matang',
];

/// Di bawah ambang ini hasil dianggap "tidak yakin".
const double kConfidenceThreshold = 0.60;

class ModelInfo {
  final String id;
  final String name;
  final String assetPath;
  final String architecture;
  final String description;
  final String latencyBadge;
  final int inputSize;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.assetPath,
    required this.architecture,
    required this.description,
    required this.latencyBadge,
    this.inputSize = 224,
  });
}

const List<ModelInfo> kAvailableModels = [
  ModelInfo(
    id: 'mobilenet_v2',
    name: 'MobileNetV2',
    assetPath: 'assets/models/sawit_mobilenetv2.tflite',
    architecture: 'Inverted Residuals + Linear Bottlenecks',
    description: 'Model efisien (~3.5M params). Cepat, hemat daya baterai, ideal untuk pemindaian di lapangan.',
    latencyBadge: '~15-25 ms (Super Ringan)',
    inputSize: 224,
  ),
  ModelInfo(
    id: 'resnet_v2',
    name: 'ResNetV2',
    assetPath: 'assets/models/sawit_resnetv2.tflite',
    architecture: 'Deep Residual Network (Identity Mappings)',
    description: 'Model berbobot ekstra (~25.6M params). Analisis tekstur serat & gradasi warna brondolan lebih dalam.',
    latencyBadge: '~45-65 ms (Fitur Mendalam)',
    inputSize: 224,
  ),
];

class Prediction {
  final String label;
  final double confidence;
  final bool uncertain;
  final List<String> warnings;
  final Map<String, double> scores;
  final String modelName;
  final int inferenceTimeMs;

  Prediction({
    required this.label,
    required this.confidence,
    required this.uncertain,
    required this.warnings,
    required this.scores,
    this.modelName = 'MobileNetV2',
    this.inferenceTimeMs = 0,
  });
}

class Classifier {
  Interpreter? _interpreter;
  int _size = 224;
  String? loadError;
  ModelInfo _currentModel = kAvailableModels.first;
  List<String> _labels = List.from(kClassNames);

  ModelInfo get currentModel => _currentModel;
  bool get ready => _interpreter != null;
  List<String> get labels => _labels;

  Future<bool> load([ModelInfo? targetModel]) async {
    final model = targetModel ?? _currentModel;
    _currentModel = model;
    _interpreter?.close();
    _interpreter = null;
    loadError = null;

    try {
      // Muat label dari assets/models/labels.txt jika tersedia
      try {
        final labelsStr =
            await rootBundle.loadString('assets/models/labels.txt');
        final lines = labelsStr
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (lines.isNotEmpty) {
          _labels = lines.map((l) {
            final cleaned = l.replaceAll('_', ' ').trim();
            return cleaned.split(' ').map((w) {
              if (w.isEmpty) return '';
              return '${w[0].toUpperCase()}${w.substring(1)}';
            }).join(' ');
          }).toList();
        }
      } catch (_) {
        _labels = List.from(kClassNames);
      }

      final ByteData data;
      try {
        data = await rootBundle.load(model.assetPath);
      } catch (e) {
        loadError = 'File ${model.assetPath} tidak ditemukan di assets: $e';
        return false;
      }

      if (data.lengthInBytes == 0) {
        loadError =
            'Model "${model.name}" (${model.assetPath}) masih kosong (0 byte). Masukkan file .tflite untuk menggunakan arsitektur ini.';
        return false;
      }

      final it = Interpreter.fromBuffer(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        options: InterpreterOptions()..threads = 2,
      );
      final shape = it.getInputTensor(0).shape; // [1, h, w, 3]
      if (shape.length == 4) _size = shape[1];
      _interpreter = it;
      return true;
    } catch (e) {
      loadError = 'Gagal memuat ${model.name}: $e';
      return false;
    }
  }

  Future<bool> switchModel(ModelInfo model) async {
    return await load(model);
  }

  Future<Prediction> predict(Uint8List bytes) async {
    final it = _interpreter;
    if (it == null) {
      throw StateError(
          'Model ${_currentModel.name} belum dimuat. ${loadError ?? "Pastikan file ${currentModel.assetPath} valid."}');
    }

    final stopwatch = Stopwatch()..start();

    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw StateError('Gambar tidak dapat dibaca.');

    final im = img.copyResize(img.bakeOrientation(decoded),
        width: _size, height: _size);
    final warnings = _quality(im);

    // Normalisasi: piksel ke rentang [-1, 1].
    final input = [
      List.generate(
        _size,
        (y) => List.generate(_size, (x) {
          final p = im.getPixel(x, y);
          return [
            (p.r / 127.5) - 1.0,
            (p.g / 127.5) - 1.0,
            (p.b / 127.5) - 1.0,
          ];
        }),
      ),
    ];

    final n = it.getOutputTensor(0).shape.last;
    final currentLabels = _labels.length == n ? _labels : kClassNames;
    if (n != currentLabels.length) {
      throw StateError(
          'Jumlah output model ($n) tidak sama dengan jumlah kelas (${currentLabels.length}).');
    }
    final output = [List<double>.filled(n, 0.0)];
    it.run(input, output);

    var probs = output[0];
    final sum = probs.fold<double>(0, (a, b) => a + b);
    if (probs.any((v) => v < 0) || sum > 1.01 || sum < 0.99) {
      probs = _softmax(probs);
    }

    var best = 0;
    for (var i = 1; i < probs.length; i++) {
      if (probs[i] > probs[best]) best = i;
    }
    final scores = <String, double>{
      for (var i = 0; i < n; i++) currentLabels[i]: probs[i],
    };

    stopwatch.stop();

    return Prediction(
      label: currentLabels[best],
      confidence: probs[best],
      uncertain: probs[best] < kConfidenceThreshold,
      warnings: warnings,
      scores: scores,
      modelName: _currentModel.name,
      inferenceTimeMs: stopwatch.elapsedMilliseconds,
    );
  }

  List<double> _softmax(List<double> v) {
    var m = v[0];
    for (final x in v) {
      if (x > m) m = x;
    }
    final e = v.map((x) => math.exp(x - m)).toList();
    final s = e.fold<double>(0, (a, b) => a + b);
    return e.map((x) => x / s).toList();
  }

  /// Peringatan kualitas gambar: gelap, terlalu terang, buram.
  List<String> _quality(img.Image im) {
    final w = im.width, h = im.height;
    final g = List<double>.filled(w * h, 0);
    var sum = 0.0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        g[y * w + x] = l;
        sum += l;
      }
    }
    final mean = sum / (w * h);

    var s = 0.0, s2 = 0.0;
    var c = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final v = 4 * g[i] - g[i - 1] - g[i + 1] - g[i - w] - g[i + w];
        s += v;
        s2 += v * v;
        c++;
      }
    }
    final variance = c == 0 ? 0 : (s2 / c) - (s / c) * (s / c);

    final out = <String>[];
    if (mean < 60) {
      out.add('Foto terlalu gelap. Cari cahaya lebih terang atau nyalakan senter.');
    }
    if (mean > 210) {
      out.add('Foto terlalu terang/silau. Hindari sinar matahari langsung ke kamera.');
    }
    if (variance < 30) {
      out.add('Foto tampak buram atau terlalu jauh. Dekatkan dan tahan kamera stabil.');
    }
    return out;
  }
}
