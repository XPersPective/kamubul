import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/input_latency_test.dart';

void main() {
  test('tap latency includes raster queue and excludes report batching', () {
    final latency = TapLatency.fromFrame(
      tapWallTime: 1000000,
      timing: FrameTiming(
        vsyncStart: 100,
        buildStart: 1000,
        buildFinish: 6000,
        rasterStart: 16000,
        rasterFinish: 20000,
        rasterFinishWallTime: 1025000,
      ),
      tapToBuildMs: 11,
      reportElapsedMs: 125,
    );
    expect(latency.visibleResponseMs, 25);
    expect(latency.rasterMs, 4);
    expect(latency.reportLagMs, 100);
  });
}
