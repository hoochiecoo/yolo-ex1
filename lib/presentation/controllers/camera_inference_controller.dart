// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import 'dart:math' as math;
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
     // We take the first person's keypoints if multiple; you can extend to multi-person UI later
     final first = results.isNotEmpty ? results.first : null;
     if (first != null && first.keypoints != null && first.keypoints!.isNotEmpty) {
       // Expecting keypoints as List<YOLOKeypoint> or similar map structure from plugin
       final kps = first.keypoints!;
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
   } catch (_) {
     // ignore parsing errors, keep angles null
   }

   bool changed = (left != _leftElbowAngle) || (right != _rightElbowAngle);
   _leftElbowAngle = left;
   _rightElbowAngle = right;

   if (changed && !_isDisposed) {
     notifyListeners();
   }
 }

 // Helper to get (x,y) from keypoints list that may be List or List<Map>
 Offset? _getKeypointXY(List<dynamic> keypoints, int index) {
   if (index < 0 || index >= keypoints.length) return null;
   final kp = keypoints[index];
   if (kp == null) return null;
   if (kp is List && kp.length >= 2) {
     final x = (kp[0] as num?)?.toDouble();
     final y = (kp[1] as num?)?.toDouble();
     if (x == null || y == null) return null;
     return Offset(x, y);
   }
   if (kp is Map) {
     final x = (kp['x'] as num?)?.toDouble();
     final y = (kp['y'] as num?)?.toDouble();
     if (x == null || y == null) return null;
     return Offset(x, y);
   }
   // If plugin exposes a class with x,y
   try {
     final x = (kp.x as num?)?.toDouble();
     final y = (kp.y as num?)?.toDouble();
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

 @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
