// lib/core/services/learner_scope.dart
//
// Which learner the per-learner stores read and write.
//
// Several people share one tablet. What belongs to a LEARNER — the spaced-
// repetition database, stars and streak, which tutorials they have seen, their
// songs and saved projects — is stored under a per-profile key; what belongs to
// the DEVICE (language, sound, instruments, the tray) is not.
//
// The first profile keeps the original, un-prefixed keys. That is the whole
// migration: an install from before profiles existed simply IS the default
// profile, and nothing has to be copied at upgrade.

/// The id of the profile that owns the legacy, un-prefixed keys.
const kDefaultLearnerId = 'default';

String _prefix = '';

/// The storage key for per-learner value [base] under the active profile.
String learnerKey(String base) => '$_prefix$base';

/// The storage key [base] would have under profile [learnerId].
String learnerKeyFor(String learnerId, String base) =>
    '${_prefixOf(learnerId)}$base';

String _prefixOf(String learnerId) =>
    learnerId == kDefaultLearnerId ? '' : 'p.$learnerId.';

/// Points [learnerKey] at [learnerId]. Called by `ProfileService` only; the
/// stores must be reloaded afterwards.
void setLearnerScope(String learnerId) => _prefix = _prefixOf(learnerId);
