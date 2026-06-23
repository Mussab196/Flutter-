import 'lib/agent/offline_command_matcher.dart';

void main() {
  final match = OfflineCommandMatcher.tryMatch("hey aura");
  print(match);
}
