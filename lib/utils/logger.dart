import 'dart:developer' as dev;

void appLog(String message, {String tag = 'OmniHub'}) {
  dev.log(message, name: tag);
  // Fallback for some consoles
  print('[$tag] $message');
}
