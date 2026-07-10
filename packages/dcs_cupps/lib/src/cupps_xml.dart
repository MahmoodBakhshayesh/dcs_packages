import 'package:xml/xml.dart';

import 'cupps_models.dart';

const cuppsNamespace = 'http://www.cupps.aero/cupps/01.03';
const cuppsXsiNamespace = 'http://www.w3.org/2001/XMLSchema-instance';
const minPlatformMessageId = 4294901760;

class CuppsEnvelope {
  const CuppsEnvelope({
    required this.messageId,
    required this.messageName,
    required this.rawXml,
    required this.document,
  });

  final int messageId;
  final String messageName;
  final String rawXml;
  final XmlDocument document;

  bool get isPlatformEvent => messageId >= minPlatformMessageId;
}

class CuppsXml {
  const CuppsXml._();

  static CuppsEnvelope parseEnvelope(String xml) {
    final document = XmlDocument.parse(xml);
    final root = document.rootElement;
    return CuppsEnvelope(
      messageId: _messageIdFromRoot(root) ?? -1,
      messageName: _attr(root, 'messageName') ?? '',
      rawXml: xml,
      document: document,
    );
  }

  static int? _messageIdFromRoot(XmlElement root) {
    for (final key in ['messageID', 'messageId', 'MessageID']) {
      final parsed = int.tryParse(_attr(root, key) ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }

  static String interfaceLevelsAvailableRequest({
    required int messageId,
    required String hsXsdVersion,
  }) {
    return _document(
      messageId: messageId,
      messageName: 'interfaceLevelsAvailableRequest',
      includeCuppsNamespace: false,
      body: XmlElement(XmlName('interfaceLevelsAvailableRequest'), [
        XmlAttribute(XmlName('hsXsdVersion'), hsXsdVersion),
      ]),
    );
  }

  static String interfaceLevelRequest({
    required int messageId,
    required String level,
  }) {
    return _document(
      messageId: messageId,
      messageName: 'interfaceLevelRequest',
      includeCuppsNamespace: false,
      body: XmlElement(XmlName('interfaceLevelRequest'), [
        XmlAttribute(XmlName('level'), level),
      ]),
    );
  }

  static String authenticateRequest({
    required int messageId,
    required CuppsApplicationInfo application,
    required String eventToken,
    required String platformDefinedParameter,
  }) {
    return _document(
      messageId: messageId,
      messageName: 'authenticateRequest',
      body: XmlElement(
        XmlName('authenticateRequest'),
        [
          XmlAttribute(XmlName('airline'), application.airlineCode),
          XmlAttribute(XmlName('eventToken'), eventToken),
          XmlAttribute(
            XmlName('platformDefinedParameter'),
            platformDefinedParameter,
          ),
        ],
        [
          XmlElement(XmlName('applicationList'), [], [
            XmlElement(XmlName('application'), [
              XmlAttribute(
                XmlName('applicationName'),
                application.applicationName,
              ),
              XmlAttribute(
                XmlName('applicationVersion'),
                application.applicationVersion,
              ),
              if (application.applicationData?.isNotEmpty ?? false)
                XmlAttribute(
                  XmlName('applicationData'),
                  application.applicationData!,
                ),
            ]),
          ]),
        ],
      ),
    );
  }

  static String deviceQueryRequest({
    required int messageId,
    String deviceName = '',
  }) {
    return _document(
      messageId: messageId,
      messageName: 'deviceQueryRequest',
      body: XmlElement(XmlName('deviceQueryRequest'), [
        XmlAttribute(XmlName('deviceName'), deviceName),
      ]),
    );
  }

  static String deviceStatusRequest({required int messageId}) {
    return _emptyBody(messageId, 'deviceStatusRequest');
  }

  static String deviceAcquireRequest({
    required int messageId,
    required String deviceName,
    required String deviceToken,
    required String airlineId,
    String? msFoidMasking,
  }) {
    final attributes = <XmlAttribute>[
      XmlAttribute(XmlName('deviceName'), deviceName),
      XmlAttribute(XmlName('deviceToken'), deviceToken),
      XmlAttribute(XmlName('airlineID'), airlineId),
    ];
    final masking = msFoidMasking?.trim();
    if (masking != null && masking.isNotEmpty) {
      attributes.add(XmlAttribute(XmlName('msFoidMasking'), masking));
    }
    return _document(
      messageId: messageId,
      messageName: 'deviceAcquireRequest',
      body: XmlElement(XmlName('deviceAcquireRequest'), attributes),
    );
  }

  static String deviceLockRequest({
    required int messageId,
    String lockMethod = 'byDeviceToken',
    bool renew = false,
  }) {
    return _document(
      messageId: messageId,
      messageName: 'deviceLockRequest',
      body: XmlElement(XmlName('deviceLockRequest'), [
        XmlAttribute(XmlName('lockMethod'), lockMethod),
        XmlAttribute(XmlName('renew'), renew.toString()),
      ]),
    );
  }

  static String deviceUnlockRequest({required int messageId}) {
    return _emptyBody(messageId, 'deviceUnlockRequest');
  }

  static String interfaceModeRequest({
    required int messageId,
    required String mode,
  }) {
    return _document(
      messageId: messageId,
      messageName: 'interfaceModeRequest',
      body: XmlElement(XmlName('interfaceModeRequest'), [
        XmlAttribute(XmlName('mode'), mode),
      ]),
    );
  }

  static String aeaResponse({
    required int messageId,
    String result = 'OK',
  }) {
    return _document(
      messageId: messageId,
      messageName: 'aeaResponse',
      body: XmlElement(XmlName('aeaResponse'), [
        XmlAttribute(XmlName('result'), result),
      ]),
    );
  }

  static String deviceReleaseRequest({required int messageId}) {
    return _emptyBody(messageId, 'deviceReleaseRequest');
  }

  static String aeaRequest({required int messageId, required String command}) {
    return _document(
      messageId: messageId,
      messageName: 'aeaRequest',
      body: XmlElement(XmlName('aeaRequest'), [], [XmlText(command)]),
    );
  }

  static String printRequest({
    required int messageId,
    required String document,
    String documentId = '',
    String stockName = '',
  }) {
    return _document(
      messageId: messageId,
      messageName: 'printRequest',
      body: XmlElement(
        XmlName('printRequest'),
        [
          XmlAttribute(XmlName('documentID'), documentId),
          XmlAttribute(XmlName('stockName'), stockName),
        ],
        [XmlText(document)],
      ),
    );
  }

  static String byeRequest({required int messageId}) {
    return _emptyBody(messageId, 'bye');
  }

  static String applicationStopCommandResponse({
    required int messageId,
    required CuppsStopCommandDecision decision,
  }) {
    final result = switch (decision) {
      CuppsStopCommandDecision.defer => 'defer',
      CuppsStopCommandDecision.forceClose => 'forceClose',
    };
    return _document(
      messageId: messageId,
      messageName: 'applicationStopCommandResponse',
      body: XmlElement(XmlName('applicationStopCommandResponse'), [
        XmlAttribute(XmlName('result'), result),
      ]),
    );
  }

  static List<String> interfaceLevels(String xml) {
    final document = XmlDocument.parse(xml);
    return document
        .findAllElements('interfaceLevel')
        .map((element) => _attr(element, 'level'))
        .whereType<String>()
        .toList(growable: false);
  }

  static String result(String xml) {
    final document = XmlDocument.parse(xml);
    final response = document.rootElement.childElements.firstOrNull;
    return _attr(response, 'result') ?? '';
  }

  static List<String> aeaRequestTexts(String xml) {
    final document = XmlDocument.parse(xml);
    final element = document.findAllElements('aeaRequest').firstOrNull;
    if (element == null) return const [];
    return element.innerText.trim().isEmpty
        ? const []
        : [element.innerText.trim()];
  }

  static String? deviceHardwareStatusLabel(String xml, CuppsDeviceType type) {
    final document = XmlDocument.parse(xml);
    final suffix = '${type.code}Status';
    for (final element in document.findAllElements('*')) {
      final name = element.name.local;
      if (!name.toLowerCase().endsWith('status')) continue;
      if (name.toLowerCase() != suffix &&
          !name.toLowerCase().startsWith(type.code)) {
        continue;
      }
      final derived = _hardwareLabelFromStatusElement(element);
      if (derived != null) return derived;
    }
    return null;
  }

  static String? hardwareStatusLabelFromNotify(String xml) {
    final document = XmlDocument.parse(xml);
    for (final element in document.findAllElements('*')) {
      final name = element.name.local;
      if (!name.toLowerCase().endsWith('status')) continue;
      final derived = _hardwareLabelFromStatusElement(element);
      if (derived != null) return derived;
    }
    return null;
  }

  static String? deviceNameFromNotify(String xml) {
    final document = XmlDocument.parse(xml);
    for (final element in document.descendants.whereType<XmlElement>()) {
      final device = _attr(element, 'device') ?? _attr(element, 'deviceName');
      if (device != null && device.trim().isNotEmpty) return device.trim();
    }
    return null;
  }

  static String? _hardwareLabelFromStatusElement(XmlElement element) {
    final status = _attr(element, 'status') ?? _attr(element, 'state');
    if (status != null && status.trim().isNotEmpty) return status.trim();

    final desc = _attr(element, 'desc')?.trim();
    if (_isTruthy(_attr(element, 'paperJam'))) return 'paperJam';
    if (_isTruthy(_attr(element, 'paperOut'))) return 'paperOut';
    if (_isTruthy(_attr(element, 'powerOff'))) return 'powerOff';
    if (_isTruthy(_attr(element, 'init'))) return desc ?? 'initializing';
    if (_isTruthy(_attr(element, 'ready'))) return 'ready';
    if (_isTruthy(_attr(element, 'unknown'))) return 'unknown';
    if (desc != null && desc.isNotEmpty) return desc;
    return null;
  }

  static bool _isTruthy(String? value) =>
      value != null && value.toLowerCase() == 'true';

  static String? deviceToken(String xml) {
    final document = XmlDocument.parse(xml);
    final response = document.rootElement.childElements.firstOrNull;
    return _attr(response, 'deviceToken');
  }

  static CuppsStopCommand? stopCommand(String xml) {
    final document = XmlDocument.parse(xml);
    final element = document
        .findAllElements('applicationStopCommandRequest')
        .firstOrNull;
    if (element == null) return null;
    return CuppsStopCommand(
      canDefer: (_attr(element, 'canDefer') ?? '').toLowerCase() == 'true',
      message: _attr(element, 'stopMessage') ?? '',
    );
  }

  /// Parsed fields for structured CUPPS protocol logging.
  static Map<String, Object?> messageLogData(CuppsEnvelope envelope) {
    final xml = envelope.rawXml;
    final data = <String, Object?>{
      'messageName': envelope.messageName,
      'messageId': envelope.messageId,
    };

    final responseResult = result(xml);
    if (responseResult.isNotEmpty) {
      data['result'] = responseResult;
    }

    final aeaTexts = aeaRequestTexts(xml);
    if (aeaTexts.isNotEmpty) {
      data['aea'] = aeaTexts.join();
    }

    final deviceName = deviceNameFromNotify(xml);
    if (deviceName != null) {
      data['deviceName'] = deviceName;
    }

    final hardwareStatus = hardwareStatusLabelFromNotify(xml);
    if (hardwareStatus != null) {
      data['hardwareStatus'] = hardwareStatus;
    }

    final notifyEvent = _notifyEventName(envelope.document);
    if (notifyEvent != null) {
      data['notifyEvent'] = notifyEvent;
    }

    final sessionError = _sessionErrorEventData(envelope.document);
    if (sessionError != null) {
      data.addAll(sessionError);
    }

    final illogical = _illogicalMessageErrorData(envelope.document);
    if (illogical != null) {
      data.addAll(illogical);
    }

    final exception = _exceptionEventData(envelope.document);
    if (exception != null) {
      data.addAll(exception);
    }

    final mode = envelope.document
        .findAllElements('interfaceModeRequest')
        .firstOrNull;
    if (mode != null) {
      final value = _attr(mode, 'mode');
      if (value != null && value.isNotEmpty) {
        data['interfaceMode'] = value;
      }
    }

    return data;
  }

  static Map<String, Object?> messageLogDataFromXml(String xml) {
    return messageLogData(parseEnvelope(xml));
  }

  /// Compact one-line summary for log messages.
  static String messageLogSummary(CuppsEnvelope envelope) {
    final data = messageLogData(envelope);
    final parts = <String>[envelope.messageName];
    void addField(String key, String label) {
      final value = data[key];
      if (value == null) return;
      final text = '$value'.trim();
      if (text.isEmpty) return;
      parts.add('$label=$text');
    }

    addField('result', 'result');
    addField('aea', 'aea');
    addField('hardwareStatus', 'status');
    addField('deviceName', 'device');
    addField('notifyEvent', 'event');
    addField('eventType', 'eventType');
    addField('exceptionSource', 'exceptionSource');
    addField('interfaceMode', 'mode');
    return parts.join(' · ');
  }

  static bool isSessionFaultNotify(CuppsEnvelope envelope) {
    final event = _notifyEventName(envelope.document);
    return event == 'sessionErrorEvent' ||
        event == 'illogicalMessageErrorEvent' ||
        event == 'messageIDErrorEvent';
  }

  static String? sessionFaultDescription(CuppsEnvelope envelope) {
    if (!isSessionFaultNotify(envelope)) return null;
    final data = messageLogData(envelope);
    final event = data['notifyEvent'];
    final eventType = data['eventType'];
    if (eventType != null) {
      return '$event: $eventType';
    }
    return event?.toString();
  }

  static Map<String, Object?>? _sessionErrorEventData(XmlDocument document) {
    final element = document.findAllElements('sessionErrorEvent').firstOrNull;
    if (element == null) return null;

    final data = <String, Object?>{};
    for (final key in ['eventType', 'workstation', 'applicationName']) {
      final value = _attr(element, key);
      if (value != null && value.trim().isNotEmpty) {
        data[key] = value.trim();
      }
    }
    return data.isEmpty ? null : data;
  }

  static Map<String, Object?>? _illogicalMessageErrorData(XmlDocument document) {
    final element =
        document.findAllElements('illogicalMessageErrorEvent').firstOrNull;
    if (element == null) return null;

    final data = <String, Object?>{};
    final device = _attr(element, 'device');
    if (device != null && device.trim().isNotEmpty) {
      data['deviceName'] = device.trim();
    }
    final encoded = element.findAllElements('illogicalMessage').firstOrNull;
    if (encoded != null) {
      final text = encoded.innerText.trim();
      if (text.isNotEmpty) {
        data['illogicalMessage'] = text;
      }
    }
    return data.isEmpty ? null : data;
  }

  static String messageLogSummaryFromXml(String xml) {
    return messageLogSummary(parseEnvelope(xml));
  }

  static String? _notifyEventName(XmlDocument document) {
    final notify = document.findAllElements('notify').firstOrNull;
    if (notify == null) return null;
    for (final child in notify.childElements) {
      return child.name.local;
    }
    return null;
  }

  static Map<String, Object?>? _exceptionEventData(XmlDocument document) {
    final element = document.findAllElements('exceptionEvent').firstOrNull;
    if (element == null) return null;

    final data = <String, Object?>{};
    for (final key in [
      'exceptionSource',
      'applicationName',
      'exceptionType',
      'exceptionMessage',
    ]) {
      final value = _attr(element, key);
      if (value != null && value.trim().isNotEmpty) {
        data[key] = value.trim();
      }
    }
    return data.isEmpty ? null : data;
  }

  static List<CuppsDeviceDescriptor> devicesFromAuthenticateResponse(
    String xml,
  ) {
    final document = XmlDocument.parse(xml);
    return document
        .findAllElements('device')
        .where((element) {
          final index = _attr(element, 'deviceIndex') ?? '';
          final parameterType = _attr(element, 'deviceParameterType');
          return !index.contains('.') &&
              CuppsDeviceType.fromParameterName(parameterType) !=
                  CuppsDeviceType.unknown;
        })
        .map(_deviceFromElement)
        .toList(growable: false);
  }

  static CuppsDeviceDescriptor _deviceFromElement(XmlElement element) {
    final parameterType = _attr(element, 'deviceParameterType') ?? '';
    final parameter = element.getElement(parameterType);
    final endpoint = _endpointFromParameter(parameter);
    final modes = element
        .findAllElements('interfaceMode')
        .map((mode) => _attr(mode, 'mode') ?? _attr(mode, 'level'))
        .whereType<String>()
        .toList(growable: false);

    return CuppsDeviceDescriptor(
      index: _attr(element, 'deviceIndex') ?? '',
      name: _attr(element, 'deviceName') ?? '',
      parameterType: parameterType,
      type: CuppsDeviceType.fromParameterName(parameterType),
      ip: endpoint.host,
      port: endpoint.port,
      supportedInterfaceModes: modes,
      rawXml: element.toXmlString(),
    );
  }

  static CuppsEndpoint _endpointFromParameter(XmlElement? parameter) {
    if (parameter == null) {
      return const CuppsEndpoint(host: '', port: 0);
    }

    final ipAndPortElement = parameter.getElement('ipAndPort');
    if (ipAndPortElement != null) {
      final ip = (_attr(ipAndPortElement, 'ip') ?? '').trim();
      final port = int.tryParse((_attr(ipAndPortElement, 'port') ?? '').trim()) ?? 0;
      if (ip.isNotEmpty || port > 0) {
        return CuppsEndpoint(host: ip, port: port);
      }
    }

    final combined = _attr(parameter, 'ipAndPort') ?? _attr(parameter, 'ipAddress');
    if (combined != null && combined.trim().isNotEmpty) {
      return _parseEndpoint(combined.trim());
    }

    final ip = (_attr(parameter, 'ip') ?? '').trim();
    final port = int.tryParse((_attr(parameter, 'port') ?? '').trim()) ?? 0;
    return CuppsEndpoint(host: ip, port: port);
  }

  static CuppsEndpoint _parseEndpoint(String value) {
    final parts = value.split(':');
    if (parts.length >= 2) {
      return CuppsEndpoint(
        host: parts.first,
        port: int.tryParse(parts.last) ?? 0,
      );
    }
    return CuppsEndpoint(host: value, port: 0);
  }

  static String _emptyBody(int messageId, String messageName) {
    return _document(
      messageId: messageId,
      messageName: messageName,
      body: XmlElement(XmlName(messageName)),
    );
  }

  static String _document({
    required int messageId,
    required String messageName,
    required XmlElement body,
    bool includeCuppsNamespace = true,
  }) {
    final attributes = <XmlAttribute>[
      if (includeCuppsNamespace) XmlAttribute(XmlName('xmlns'), cuppsNamespace),
      XmlAttribute(XmlName('xmlns:xsi'), cuppsXsiNamespace),
      XmlAttribute(XmlName('messageID'), messageId.toString()),
      XmlAttribute(XmlName('messageName'), messageName),
    ];
    final document = XmlDocument([
      XmlProcessing('xml', 'version="1.0" encoding="utf-8"'),
      XmlElement(
        XmlName('cupps'),
        attributes,
        [body],
      ),
    ]);
    return document.toXmlString(pretty: false);
  }

  static String? _attr(XmlElement? element, String name) {
    if (element == null) return null;
    return element.getAttribute(name);
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
