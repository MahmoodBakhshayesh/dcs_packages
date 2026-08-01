class ArincPcpCommand {
  static const int receive = 1;
  static const int send = 2;
  static const int lock = 3;
  static const int unlock = 4;
  static const int status = 5;
  static const int mode = 6;
  static const int cancel = 7;
  static const int reset = 8;
  static const int send2 = 18;
  static const int byteOrder = 21930;

  static const int receiveAck = 32769;
  static const int sendAck = 32770;
  static const int lockAck = 32771;
  static const int unlockAck = 32772;
  static const int statusAck = 32773;
  static const int modeAck = 32774;
}

class ArincPcpMode {
  static const int unsolicitedReadWrite = 17;
}

class ArincPhysicalStatus {
  static const int cts = 1;
  static const int dsr = 2;
  static const int online = 3;
  static const int offline = 2;
  static const int powerOff = 0;
}
