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
      messageId: int.tryParse(_attr(root, 'messageID') ?? '') ?? -1,
      messageName: _attr(root, 'messageName') ?? '',
      rawXml: xml,
      document: document,
    );
  }

  static String interfaceLevelsAvailableRequest({
    required int messageId,
    required String hsXsdVersion,
  }) {
    return _document(
      messageId: messageId,
      messageName: 'interfaceLevelsAvailableRequest',
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
    String msFoidMasking = 'false',
  }) {
    return _document(
      messageId: messageId,
      messageName: 'deviceAcquireRequest',
      body: XmlElement(XmlName('deviceAcquireRequest'), [
        XmlAttribute(XmlName('deviceName'), deviceName),
        XmlAttribute(XmlName('deviceToken'), deviceToken),
        XmlAttribute(XmlName('airlineID'), airlineId),
        XmlAttribute(XmlName('msFoidMasking'), msFoidMasking),
      ]),
    );
  }

  static String deviceLockRequest({
    required int messageId,
    String lockMethod = 'byConnection',
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
    final ipAndPort =
        _attr(parameter, 'ipAndPort') ??
        _attr(parameter, 'ipAddress') ??
        _attr(parameter, 'ip') ??
        '';
    final endpoint = _parseEndpoint(ipAndPort);
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
  }) {
    final document = XmlDocument([
      XmlProcessing('xml', 'version="1.0" encoding="utf-8"'),
      XmlElement(
        XmlName('cupps'),
        [
          XmlAttribute(XmlName('xmlns'), cuppsNamespace),
          XmlAttribute(XmlName('xmlns:xsi'), cuppsXsiNamespace),
          XmlAttribute(XmlName('messageID'), messageId.toString()),
          XmlAttribute(XmlName('messageName'), messageName),
        ],
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
