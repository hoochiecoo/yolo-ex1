// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ultralytics_yolo/models/yolo_result.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/utils/error_handler.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import '../../models/models.dart';
import '../../services/model_manager.dart';

/// Controller that manages the state and business logic for camera inference
class CameraInferenceController extends ChangeNotifier {
  // Elbow angles (degrees), computed for pose task
  double? _leftElbowAngle;
  double? _rightElbowAngle;
  int? _debugKeypointCount;

  // Detection state
  int _detectionCount = 0;
  double _currentFps = 0.0;
  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  // Threshold state
  double _confidenceThreshold = 0.5;
  double _iouThreshold = 0.45;
  int _numItemsThreshold = 30;
  SliderType _activeSlider = SliderType.none;

  // Model state
  ModelType _selectedModel = ModelType.detect;
  bool _isModelLoading = false;
  String? _modelPath;
  String _loadingMessage = '';
  double _downloadProgress = 0.0;

  // Camera state
  double _currentZoomLevel = 1.0;
  LensFacing _lensFacing = LensFacing.front;
  bool _isFrontCamera = false;

  // Controllers
  final _yoloController = YOLOViewController();
  late final ModelManager _modelManager;

  // Performance optimization
  bool _isDisposed = false;
  Future<void>? _loadingFuture;

  // Getters
  int get detectionCount => _detectionCount;
  double get currentFps => _currentFps;
  double get confidenceThreshold => _confidenceThreshold;
  double get iouThreshold => _iouThreshold;
  int get numItemsThreshold => _numItemsThreshold;
  SliderType get activeSlider => _activeSlider;
  ModelType get selectedModel => _selectedModel;
  bool get isModelLoading => _isModelLoading;
  String? get modelPath => _modelPath;
  String get loadingMessage => _loadingMessage;
  double get downloadProgress => _downloadProgress;
  double get currentZoomLevel => _currentZoomLevel;
  bool get isFrontCamera => _isFrontCamera;
  LensFacing get lensFacing => _lensFacing;
  YOLOViewController get yoloController => _yoloController;

  CameraInferenceController() {
    _isFrontCamera = _lensFacing == LensFacing.front;

    _modelManager = ModelManager(
      onDownloadProgress: (progress) {
        _downloadProgress = progress;
        notifyListeners();
      },
      onStatusUpdate: (message) {
        _loadingMessage = message;
        notifyListeners();
      },
    );
  }

  /// Initialize the controller
  Future<void> initialize() async {
    await _loadModelForPlatform();
    _yoloController.setThresholds(
      confidenceThreshold: _confidenceThreshold,
      iouThreshold: _iouThreshold,
      numItemsThreshold: _numItemsThreshold,
    );
  }

  /// Handle detection results and calculate FPS
  void onDetectionResults(List<YOLOResult> results) {
    if (_selectedModel == ModelType.pose) {
      _updateElbowAnglesFromPose(results);
    }

    if (_isDisposed) return;

    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastFpsUpdate).inMilliseconds;

    if (elapsed >= 1000) {
      _currentFps = _frameCount * 1000 / elapsed;
      _frameCount = 0;
      _lastFpsUpdate = now;
    }

    if (_detectionCount != results.length) {
      _detectionCount = results.length;
      notifyListeners();
    }
  }

  /// Handle performance metrics
  void onPerformanceMetrics(double fps) {
    if (_isDisposed) return;

    if ((_currentFps - fps).abs() > 0.1) {
      _currentFps = fps;
      notifyListeners();
    }
  }

  void onZoomChanged(double zoomLevel) {
    if (_isDisposed) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      notifyListeners();
    }
  }

  void toggleSlider(SliderType type) {
    if (_isDisposed) return;

    if (_activeSlider != type) {
      _activeSlider = _activeSlider == type ? SliderType.none : type;
      notifyListeners();
    }
  }

  void updateSliderValue(double value) {
    if (_isDisposed) return;

    bool changed = false;
    switch (_activeSlider) {
      case SliderType.numItems:
        final newValue = value.toInt();
        if (_numItemsThreshold != newValue) {
          _numItemsThreshold = newValue;
          _yoloController.setNumItemsThreshold(_numItemsThreshold);
          changed = true;
        }
        break;
      case SliderType.confidence:
        if ((_confidenceThreshold - value).abs() > 0.01) {
          _confidenceThreshold = value;
          _yoloController.setConfidenceThreshold(value);
          changed = true;
        }
        break;
      case SliderType.iou:
        if ((_iouThreshold - value).abs() > 0.01) {
          _iouThreshold = value;
          _yoloController.setIoUThreshold(value);
          changed = true;
        }
        break;
      default:
        break;
    }

    if (changed) {
      notifyListeners();
    }
  }

  void setZoomLevel(double zoomLevel) {
    if (_isDisposed) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      _yoloController.setZoomLevel(zoomLevel);
      notifyListeners();
    }
  }

  void flipCamera() {
    if (_isDisposed) return;

    _isFrontCamera = !_isFrontCamera;
    _lensFacing = _isFrontCamera ? LensFacing.front : LensFacing.back;
    if (_isFrontCamera) _currentZoomLevel = 1.0;
    _yoloController.switchCamera();
    notifyListeners();
  }

  void setLensFacing(LensFacing facing) {
    if (_isDisposed) return;

    if (_lensFacing != facing) {
      _lensFacing = facing;
      _isFrontCamera = facing == LensFacing.front;

      _yoloController.switchCamera();

      if (_isFrontCamera) {
        _currentZoomLevel = 1.0;
      }

      notifyListeners();
    }
  }

  void changeModel(ModelType model) {
    if (_isDisposed) return;

    if (!_isModelLoading && model != _selectedModel) {
      _selectedModel = model;
      _loadModelForPlatform();
    }
  }

  Future<void> _loadModelForPlatform() async {
    if (_isDisposed) return;

    if (_loadingFuture != null) {
      await _loadingFuture;
      return;
    }

    _loadingFuture = _performModelLoading();
    try {
      await _loadingFuture;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<void> _performModelLoading() async {
    if (_isDisposed) return;

    _isModelLoading = true;
    _loadingMessage = 'Loading ${_selectedModel.modelName} model...';
    _downloadProgress = 0.0;
    _detectionCount = 0;
    _currentFps = 0.0;
    notifyListeners();

    try {
      final modelPath = await _modelManager.getModelPath(_selectedModel);

      if (_isDisposed) return;

      _modelPath = modelPath;
      _isModelLoading = false;
      _loadingMessage = '';
      _downloadProgress = 0.0;
      notifyListeners();

      if (modelPath == null) {
        throw Exception('Failed to load ${_selectedModel.modelName} model');
      }
    } catch (e) {
      if (_isDisposed) return;

      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load model ${_selectedModel.modelName} for task ${_selectedModel.task.name}',
      );

      _isModelLoading = false;
      _loadingMessage = 'Failed to load model: ${error.message}';
      _downloadProgress = 0.0;
      notifyListeners();
      rethrow;
    }
  }

  // Compute elbow angles from pose keypoints in results
 void _updateElbowAnglesFromPose(List<YOLOResult> results) {
   double? left;
   double? right;

   try {
     // Take the first detected person
     final first = results.isNotEmpty ? results.first : null;
     if (first != null) {
       final kps = _extractKeypointList(first);
       _debugKeypointCount = kps?.length;
       if (kps != null && kps.isNotEmpty) {
         // Common COCO indices: 5=left shoulder, 7=left elbow, 9=left wrist
         // 6=right shoulder, 8=right elbow, 10=right wrist
         final ls = _getKeypointXY(kps, 5);
         final le = _getKeypointXY(kps, 7);
         final lw = _getKeypointXY(kps, 9);
         final rs = _getKeypointXY(kps, 6);
         final re = _getKeypointXY(kps, 8);
         final rw = _getKeypointXY(kps, 10);

         if (ls != null && le != null && lw != null) {
           left = _angleAtB(ls, le, lw);
         }
         if (rs != null && re != null && rw != null) {
           right = _angleAtB(rs, re, rw);
         }
       }
     }
   } catch (e) {
     // ignore parsing errors, keep angles null but log once to help debugging
     // debugPrint('Pose parsing error: $e');
   }

   bool changed = (left != _leftElbowAngle) || (right != _rightElbowAngle);
   _leftElbowAngle = left;
   _rightElbowAngle = right;
   // If no keypoints extracted, ensure debug flag null
   if (left == null && right == null) {
     _debugKeypointCount ??= 0;
   }

   if (changed && !_isDisposed) {
     notifyListeners();
   }
 }

 // Try to extract a flat list of keypoints from various possible structures
 List<dynamic>? _extractKeypointList(dynamic firstResult) {
   dynamic container;
   // Attempt common property names
   try { container = firstResult.keypoints; } catch (_) {}
   if (container == null) {
     try { container = firstResult.kpts; } catch (_) {}
   }
   if (container == null) {
     try { container = firstResult.pose; } catch (_) {}
   }

   List<dynamic>? asList = _asList(container);
   if (asList != null) return asList;

   // If container is an object with nested properties like points/xy/data/keypoints
   final nestedKeys = ['points', 'xy', 'data', 'keypoints', 'kpts', 'joints', 'normalizedKeypoints'];
   for (final key in nestedKeys) {
     final nested = _getProp(container, key);
     asList = _asList(nested);
     if (asList != null) return asList;
   }

   // Some plugins wrap as {"keypoints": [...]}
   if (container is Map) {
     for (final key in nestedKeys) {
       final nested = container[key];
       asList = _asList(nested);
       if (asList != null) return asList;
     }
   }

   return null;
 }

 // Safe dynamic property access
 dynamic _getProp(dynamic obj, String name) {
   if (obj == null) return null;
   if (obj is Map) return obj[name];
   try { return obj.__proto__; } catch (_) {}
   try { return obj.noSuchMethod; } catch (_) {}
   try { return obj.toString; } catch (_) {}
   try {
     // Attempt via dynamic getter
     switch (name) {
       case 'points':
         return obj.points;
       case 'xy':
         return obj.xy;
       case 'data':
         return obj.data;
       case 'keypoints':
         return obj.keypoints;
       case 'kpts':
         return obj.kpts;
     }
   } catch (_) {}
   return null;
 }

 List<dynamic>? _asList(dynamic v) {
   if (v == null) return null;
   if (v is List) return v;
   if (v is Float32List || v is Float64List || v is Int32List || v is Int16List || v is Int8List || v is Uint8List || v is Uint16List || v is Uint32List) {
     return (v as Iterable).toList();
   }
   if (v is Iterable) return v.toList();
   return null;
 }

 // Helper to get (x,y) from keypoints list that may be flat list, List<List>, List<Map>, or objects
 Offset? _getKeypointXY(List<dynamic> keypoints, int index) {
   if (index < 0) return null;
   if (keypoints.isEmpty) return null;

   final first = keypoints.first;
   // Case 1: flattened list of numbers of length 17*k (k >= 2)
   if (first is num) {
     final flat = keypoints.cast<num>();
     if (flat.isEmpty) return null;
     final n = flat.length;
     // infer keypoint count ~17 (Ultralytics/COCO)
     const kptCount = 17;
     if (n % kptCount == 0) {
       final stride = (n / kptCount).round();
       if (stride >= 2 && index * stride + 1 < flat.length) {
         final x = flat[index * stride + 0].toDouble();
         final y = flat[index * stride + 1].toDouble();
         return Offset(x, y);
       }
     }
     return null;
   }

   // Case 2: list of lists [[x,y,(score)], ...]
   if (index >= keypoints.length) return null;
   final kp = keypoints[index];
   if (kp == null) return null;
   if (kp is List && kp.length >= 2) {
     final x = (kp[0] as num?)?.toDouble();
     final y = (kp[1] as num?)?.toDouble();
     if (x == null || y == null) return null;
     return Offset(x, y);
   }

   // Case 3: list of maps [{x:.., y:..}, ...]
   if (kp is Map) {
     final x = (kp['x'] as num?)?.toDouble();
     final y = (kp['y'] as num?)?.toDouble();
     if (x == null || y == null) return null;
     return Offset(x, y);
   }

   // Case 4: object with x,y or point.x, point.y
   try {
     final x = (kp.x as num?)?.toDouble();
     final y = (kp.y as num?)?.toDouble();
     if (x != null && y != null) return Offset(x, y);
   } catch (_) {}
   try {
     final p = kp.point ?? kp.pt ?? kp.xy;
     final x = (p.x as num?)?.toDouble();
     final y = (p.y as num?)?.toDouble();
     if (x != null && y != null) return Offset(x, y);
   } catch (_) {}

   return null;
 }

 // Returns angle ABC at point B, in degrees, clamped [0, 180]
 double _angleAtB(Offset a, Offset b, Offset c) {
   final v1 = Offset(a.dx - b.dx, a.dy - b.dy);
   final v2 = Offset(c.dx - b.dx, c.dy - b.dy);
   final dot = v1.dx * v2.dx + v1.dy * v2.dy;
   final mag1 = math.sqrt(v1.dx * v1.dx + v1.dy * v1.dy);
   final mag2 = math.sqrt(v2.dx * v2.dx + v2.dy * v2.dy);
   if (mag1 == 0 || mag2 == 0) return double.nan;
   var cosang = (dot / (mag1 * mag2)).clamp(-1.0, 1.0);
   final ang = math.acos(cosang);
   return ang * 180 / math.pi;
 }

 double? get leftElbowAngle => _leftElbowAngle;
 double? get rightElbowAngle => _rightElbowAngle;
 int? get debugKeypointCount => _debugKeypointCount;

 @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
