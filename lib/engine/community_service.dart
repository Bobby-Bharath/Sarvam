import '../utils/logger.dart';

class CommunityService {
  static double? normalizeScore(dynamic rawScore) {
    final numeric = switch (rawScore) {
      num v => v.toDouble(),
      String v => double.tryParse(v),
      _ => null,
    };
    
    if (numeric == null || numeric == 0) return null;
    
    // Convert 100-scale to 10-scale, or keep 10-scale as is
    final normalized = numeric > 10 
        ? double.parse((numeric / 10.0).toStringAsFixed(1)) 
        : double.parse(numeric.toStringAsFixed(1));
        
    return normalized;
  }
}
