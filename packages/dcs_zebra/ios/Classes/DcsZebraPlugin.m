#import "DcsZebraPlugin.h"
#import <ExternalAccessory/ExternalAccessory.h>

#import "TcpPrinterConnection.h"
#import "MfiBtPrinterConnection.h"
#import "ZebraPrinterFactory.h"
#import "ZebraPrinter.h"
#import "PrinterStatus.h"

@interface DcsZebraPlugin ()
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *connections;
@end

@implementation DcsZebraPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"dcs_zebra"
                                  binaryMessenger:[registrar messenger]];
  DcsZebraPlugin *instance = [[DcsZebraPlugin alloc] init];
  instance.connections = [NSMutableDictionary dictionary];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"capabilities"]) {
    result(@{
      @"tcp" : @YES,
      @"bluetooth" : @YES,
      @"bluetoothLe" : @NO,
      @"usb" : @NO,
    });
    return;
  }

  if ([call.method isEqualToString:@"discover"]) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSArray *found = [self discoverPrinters];
      dispatch_async(dispatch_get_main_queue(), ^{ result(found); });
    });
    return;
  }

  if ([call.method isEqualToString:@"connect"]) {
    NSDictionary *args = call.arguments;
    NSString *printerId = args[@"id"];
    NSString *address = args[@"address"];
    NSString *type = args[@"connectionType"] ?: @"tcp";
    if (printerId.length == 0 || address.length == 0) {
      result([FlutterError errorWithCode:@"bad_args"
                                 message:@"id/address required"
                                 details:nil]);
      return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSError *error = nil;
      BOOL ok = [self connectId:printerId address:address type:type error:&error];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (ok) {
          result(nil);
        } else {
          result([FlutterError errorWithCode:@"connect_failed"
                                     message:error.localizedDescription ?: @"connect failed"
                                     details:nil]);
        }
      });
    });
    return;
  }

  if ([call.method isEqualToString:@"disconnect"]) {
    NSString *printerId = call.arguments[@"id"];
    [self disconnectId:printerId];
    result(nil);
    return;
  }

  if ([call.method isEqualToString:@"write"]) {
    NSDictionary *args = call.arguments;
    NSString *printerId = args[@"id"];
    FlutterStandardTypedData *bytes = args[@"bytes"];
    if (printerId.length == 0 || bytes == nil) {
      result([FlutterError errorWithCode:@"bad_args"
                                 message:@"id/bytes required"
                                 details:nil]);
      return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSError *error = nil;
      BOOL ok = [self writeId:printerId data:bytes.data error:&error];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (ok) {
          result(nil);
        } else {
          result([FlutterError errorWithCode:@"write_failed"
                                     message:error.localizedDescription ?: @"write failed"
                                     details:nil]);
        }
      });
    });
    return;
  }

  if ([call.method isEqualToString:@"read"]) {
    NSString *printerId = call.arguments[@"id"];
    NSNumber *timeoutMs = call.arguments[@"timeoutMs"] ?: @2000;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSData *data = [self readId:printerId timeoutMs:timeoutMs.integerValue];
      dispatch_async(dispatch_get_main_queue(), ^{
        result(data == nil ? nil : [FlutterStandardTypedData typedDataWithBytes:data]);
      });
    });
    return;
  }

  if ([call.method isEqualToString:@"getStatus"]) {
    NSString *printerId = call.arguments[@"id"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSDictionary *status = [self statusForId:printerId];
      dispatch_async(dispatch_get_main_queue(), ^{ result(status); });
    });
    return;
  }

  result(FlutterMethodNotImplemented);
}

- (NSArray *)discoverPrinters {
  NSMutableArray *found = [NSMutableArray array];
  NSArray<EAAccessory *> *accessories = [EAAccessoryManager sharedAccessoryManager].connectedAccessories;
  for (EAAccessory *accessory in accessories) {
    BOOL zebra = NO;
    for (NSString *protocol in accessory.protocolStrings) {
      NSString *lower = protocol.lowercaseString;
      if ([lower containsString:@"zebra"] || [lower containsString:@"com.zebra"]) {
        zebra = YES;
        break;
      }
    }
    if (!zebra) continue;
    NSString *address = accessory.serialNumber.length > 0 ? accessory.serialNumber : accessory.name;
    [found addObject:@{
      @"id" : [NSString stringWithFormat:@"bluetooth:%@", address],
      @"address" : address,
      @"connectionType" : @"bluetooth",
      @"name" : accessory.name ?: address,
      @"serialNumber" : accessory.serialNumber ?: [NSNull null],
      @"model" : accessory.modelNumber ?: [NSNull null],
    }];
  }
  return found;
}

- (BOOL)connectId:(NSString *)printerId
          address:(NSString *)address
             type:(NSString *)type
            error:(NSError **)error {
  [self disconnectId:printerId];
  id<ZebraPrinterConnection, NSObject> connection = nil;
  if ([type isEqualToString:@"bluetooth"]) {
    connection = [[MfiBtPrinterConnection alloc] initWithSerialNumber:address];
  } else {
    NSArray *parts = [address componentsSeparatedByString:@":"];
    NSString *host = parts.firstObject;
    NSInteger port = parts.count > 1 ? parts[1].integerValue : 9100;
    connection = [[TcpPrinterConnection alloc] initWithAddress:host andWithPort:port];
  }
  if (![connection open]) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"dcs_zebra"
                                   code:2
                               userInfo:@{NSLocalizedDescriptionKey : @"Failed to open printer connection"}];
    }
    return NO;
  }
  self.connections[printerId] = connection;
  return YES;
}

- (void)disconnectId:(NSString *)printerId {
  if (printerId.length == 0) return;
  id<ZebraPrinterConnection, NSObject> connection = self.connections[printerId];
  if (connection != nil) {
    [connection close];
    [self.connections removeObjectForKey:printerId];
  }
}

- (BOOL)writeId:(NSString *)printerId data:(NSData *)data error:(NSError **)error {
  id<ZebraPrinterConnection, NSObject> connection = self.connections[printerId];
  if (connection == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"dcs_zebra"
                                   code:5
                               userInfo:@{NSLocalizedDescriptionKey : @"Not connected"}];
    }
    return NO;
  }
  NSError *writeError = nil;
  NSInteger written = [connection write:data error:&writeError];
  if (written < 0 || writeError != nil) {
    if (error != NULL) *error = writeError;
    return NO;
  }
  return YES;
}

- (NSData *)readId:(NSString *)printerId timeoutMs:(NSInteger)timeoutMs {
  id<ZebraPrinterConnection, NSObject> connection = self.connections[printerId];
  if (connection == nil) return nil;
  [connection setMaxTimeoutForRead:timeoutMs];
  [connection setTimeToWaitForMoreData:timeoutMs];
  NSError *error = nil;
  return [connection read:&error];
}

- (NSDictionary *)statusForId:(NSString *)printerId {
  id<ZebraPrinterConnection, NSObject> connection = self.connections[printerId];
  if (connection == nil) return nil;
  NSError *error = nil;
  id<ZebraPrinter, NSObject> printer = [ZebraPrinterFactory getInstance:connection error:&error];
  if (printer == nil || error != nil) return nil;
  PrinterStatus *status = [printer getCurrentStatus:&error];
  if (status == nil || error != nil) return nil;
  return @{
    @"isReadyToPrint" : @(status.isReadyToPrint),
    @"isPaperOut" : @(status.isPaperOut),
    @"isHeadOpen" : @(status.isHeadOpen),
    @"isRibbonOut" : @(status.isRibbonOut),
    @"isPaused" : @(status.isPaused),
    @"isReceiveBufferFull" : @(status.isReceiveBufferFull),
  };
}

@end
