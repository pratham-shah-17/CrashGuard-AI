/// Honest outcome of attempting emergency SMS (no fake “help is coming” without proof).
///
/// **(A) bar:** [primaryAutomatedBarMet] — prefer device [SEND_SMS]; HTTP relay 2xx alone counts
/// on **Android** only when `SMS_RELAY_COUNTS_AS_PRIMARY_DISPATCH=true` (audited backend).
/// On **iOS**, relay success is the only automated SMS path, so it satisfies **(A)** when 2xx.
///
/// Note: Neither a carrier API call nor an HTTP relay guarantees the emergency authority received the message.
/// This model intentionally tracks *request acceptance* rather than "delivered".
enum SmsDispatchProofLevel {
  none,

  /// We successfully handed the request to either the OS (SEND_SMS) or a backend relay (HTTP 2xx).
  accepted,
}

class SmsDispatchOutcome {
  /// Android Telephony [sendSms] reported success (direct emergency number).
  final bool deviceDirectSmsSent;

  /// Any configured HTTP relay ([INDIA_SOS_DISPATCH_URL] or [SMS_DISPATCH_URL]) returned 2xx.
  final bool backendRelayAccepted;

  /// Satisfies the v1 “(A)” automated bar for orchestrator / session success.
  final bool primaryAutomatedBarMet;

  /// Indicates what we can actually prove right now (acceptance only in this build).
  final SmsDispatchProofLevel proofLevel;

  /// User-visible status line for dispatch UI.
  final String detail;

  const SmsDispatchOutcome({
    required this.deviceDirectSmsSent,
    required this.backendRelayAccepted,
    required this.primaryAutomatedBarMet,
    required this.proofLevel,
    required this.detail,
  });
}
