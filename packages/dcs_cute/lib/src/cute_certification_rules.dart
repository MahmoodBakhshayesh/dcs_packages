import 'cute_models.dart';

enum CuteRuleSeverity { pass, warning, error }

class CuteRuleFinding {
  const CuteRuleFinding({
    required this.id,
    required this.severity,
    required this.message,
  });

  final String id;
  final CuteRuleSeverity severity;
  final String message;

  bool get isBlocking => severity == CuteRuleSeverity.error;
}

class CuteCertificationProfile {
  const CuteCertificationProfile({
    required this.endpoint,
    required this.session,
    this.requiresStandardMatipPort = true,
    this.requiresAsciiPayloads = true,
    this.requiresFiniteTimeouts = true,
    this.connectTimeout = const Duration(seconds: 10),
    this.sessionOpenTimeout = const Duration(seconds: 10),
  });

  final CuteEndpoint endpoint;
  final CuteSessionConfig session;
  final bool requiresStandardMatipPort;
  final bool requiresAsciiPayloads;
  final bool requiresFiniteTimeouts;
  final Duration connectTimeout;
  final Duration sessionOpenTimeout;
}

class CuteCertificationRules {
  const CuteCertificationRules();

  List<CuteRuleFinding> evaluate(CuteCertificationProfile profile) {
    return [
      _configurationIsCoherent(profile.session),
      _usesExpectedPort(profile),
      _usesAsciiWhenRequired(profile),
      _usesFiniteTimeouts(profile),
      _typeBHldPairIsComplete(profile.session),
      _sessionHasKnownTrafficPurpose(profile.session),
    ];
  }

  bool isReady(CuteCertificationProfile profile) {
    return evaluate(profile).every((finding) => !finding.isBlocking);
  }

  CuteRuleFinding _configurationIsCoherent(CuteSessionConfig session) {
    try {
      session.validate();
      return const CuteRuleFinding(
        id: 'CUTE-MATIP-001',
        severity: CuteRuleSeverity.pass,
        message: 'MATIP session configuration is internally coherent.',
      );
    } catch (error) {
      return CuteRuleFinding(
        id: 'CUTE-MATIP-001',
        severity: CuteRuleSeverity.error,
        message: error.toString(),
      );
    }
  }

  CuteRuleFinding _usesExpectedPort(CuteCertificationProfile profile) {
    if (!profile.requiresStandardMatipPort) {
      return const CuteRuleFinding(
        id: 'CUTE-MATIP-002',
        severity: CuteRuleSeverity.pass,
        message: 'Standard MATIP port enforcement is disabled by profile.',
      );
    }
    final expected = profile.session.trafficType.defaultPort;
    if (profile.endpoint.port == expected) {
      return CuteRuleFinding(
        id: 'CUTE-MATIP-002',
        severity: CuteRuleSeverity.pass,
        message: 'Endpoint uses standard MATIP port $expected.',
      );
    }
    return CuteRuleFinding(
      id: 'CUTE-MATIP-002',
      severity: CuteRuleSeverity.warning,
      message:
          'Endpoint uses port ${profile.endpoint.port}; MATIP '
          '${profile.session.trafficType.name} commonly uses port $expected.',
    );
  }

  CuteRuleFinding _usesAsciiWhenRequired(CuteCertificationProfile profile) {
    if (!profile.requiresAsciiPayloads ||
        profile.session.characterSet == CuteCharacterSet.ascii7Bit) {
      return const CuteRuleFinding(
        id: 'CUTE-MATIP-003',
        severity: CuteRuleSeverity.pass,
        message: 'Character set is acceptable for this profile.',
      );
    }
    return CuteRuleFinding(
      id: 'CUTE-MATIP-003',
      severity: CuteRuleSeverity.warning,
      message:
          'Profile expects ASCII payloads, but session uses '
          '${profile.session.characterSet.name}. Confirm this with the host.',
    );
  }

  CuteRuleFinding _usesFiniteTimeouts(CuteCertificationProfile profile) {
    if (!profile.requiresFiniteTimeouts) {
      return const CuteRuleFinding(
        id: 'CUTE-MATIP-004',
        severity: CuteRuleSeverity.pass,
        message: 'Timeout enforcement is disabled by profile.',
      );
    }
    if (profile.connectTimeout > Duration.zero &&
        profile.sessionOpenTimeout > Duration.zero) {
      return const CuteRuleFinding(
        id: 'CUTE-MATIP-004',
        severity: CuteRuleSeverity.pass,
        message: 'Connection and session-open timeouts are finite.',
      );
    }
    return const CuteRuleFinding(
      id: 'CUTE-MATIP-004',
      severity: CuteRuleSeverity.error,
      message:
          'Connection and session-open timeouts must be greater than zero.',
    );
  }

  CuteRuleFinding _typeBHldPairIsComplete(CuteSessionConfig session) {
    if (session.trafficType != CuteTrafficType.typeB ||
        (session.senderHld == null && session.recipientHld == null) ||
        (session.senderHld != null && session.recipientHld != null)) {
      return const CuteRuleFinding(
        id: 'CUTE-MATIP-005',
        severity: CuteRuleSeverity.pass,
        message: 'Type B HLD configuration is complete.',
      );
    }
    return const CuteRuleFinding(
      id: 'CUTE-MATIP-005',
      severity: CuteRuleSeverity.error,
      message: 'Type B senderHld and recipientHld must be configured together.',
    );
  }

  CuteRuleFinding _sessionHasKnownTrafficPurpose(CuteSessionConfig session) {
    if (session.trafficType == CuteTrafficType.typeB ||
        session.subtype == CuteTrafficSubtype.conversational ||
        session.subtype == CuteTrafficSubtype.iataHostToHost ||
        session.subtype == CuteTrafficSubtype.sitaHostToHost) {
      return const CuteRuleFinding(
        id: 'CUTE-MATIP-006',
        severity: CuteRuleSeverity.pass,
        message: 'Session traffic type/subtype is explicit.',
      );
    }
    return const CuteRuleFinding(
      id: 'CUTE-MATIP-006',
      severity: CuteRuleSeverity.error,
      message: 'Session traffic type/subtype must be explicit.',
    );
  }
}
