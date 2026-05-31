import 'package:flutter/material.dart';

/// GlobalKey for the outermost RepaintBoundary used for live broadcast
/// screen capture. Placed outside the inner RepaintBoundary so it captures
/// everything (including the camera PiP overlay).
final GlobalKey broadcastCaptureKey = GlobalKey();
