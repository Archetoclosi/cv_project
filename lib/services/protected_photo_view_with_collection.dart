import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'risk_engine/feature_vector.dart';
import 'risk_engine/risk_engine.dart';
import 'data_collection/data_collector.dart';
import 'data_collection/collection_controller.dart';
import '../widgets/collection_overlay.dart';

/// Drop-in replacement for ProtectedPhotoView that adds data collection
/// in debug builds. In release builds, behaves identically to before.
///
/// The only change to your existing code:
///   Replace: ProtectedPhotoView(featureStream: ..., child: ...)
///   With:    ProtectedPhotoViewWithCollection(featureStream: ..., child: ...)
class ProtectedPhotoViewWithCollection extends StatefulWidget {
  final Stream<FeatureVector> featureStream;
  final Widget child;

  const ProtectedPhotoViewWithCollection({
    super.key,
    required this.featureStream,
    required this.child,
  });

  @override
  State<ProtectedPhotoViewWithCollection> createState() =>
      _ProtectedPhotoViewWithCollectionState();
}

class _ProtectedPhotoViewWithCollectionState
    extends State<ProtectedPhotoViewWithCollection> {
  late final CollectionController _collectionController;
  late final StreamSubscription<FeatureVector> _sub;

  @override
  void initState() {
    super.initState();

    _collectionController = CollectionController(
      engine: RiskEngine(),
      collector: DataCollector(),
    );

    _collectionController.init();

    // Forward every feature to the controller
    _sub = widget.featureStream.listen(_collectionController.onFeatures);
  }

  @override
  void dispose() {
    _sub.cancel();
    _collectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Your existing protected content
        widget.child,

        // Data collection UI — debug only, zero overhead in release
        if (kDebugMode)
          CollectionOverlay(controller: _collectionController),
      ],
    );
  }
}
