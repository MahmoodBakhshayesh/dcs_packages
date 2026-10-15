#import "DcsZebraPlugin.h"
#import <ExternalAccessory/ExternalAccessory.h>
#import <UIKit/UIKit.h>

#import "TcpPrinterConnection.h"
#import "MfiBtPrinterConnection.h"
#import "ZebraPrinterFactory.h"
#import "ZebraPrinter.h"
#import "PrinterStatus.h"

@interface DcsZebraPlugin () <FlutterStreamHandler>
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *connections;
@property(nonatomic, copy) FlutterEventSink discoverSink;
@property(nonatomic, assign) BOOL discoverCancelled;
@end

@implementation DcsZebraPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:@"dcs_zebra"
                                  binaryMessenger:[registrar messenger]];
  FlutterEventChannel *discoverChannel =
      [FlutterEventChannel eventChannelWithName:@"dcs_zebra/discover"
                                binaryMessenger:[registrar messenger]];
  DcsZebraPlugin *instance = [[DcsZebraPlugin alloc] init];
  instance.connections = [NSMutableDictionary dictionary];
  [registrar addMethodCallDelegate:instance channel:channel];
  [discoverChannel setStreamHandler:instance];
}

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
  self.discoverSink = events;
  return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
  self.discoverCancelled = YES;
  self.discoverSink = nil;
  return nil;
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
      NSArray *found = [self discoverPrintersStreaming:NO];
      dispatch_async(dispatch_get_main_queue(), ^{ result(found); });
    });
    return;
  }

  if ([call.method isEqualToString:@"startDiscover"]) {
    self.discoverCancelled = NO;
    result(nil);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      [self discoverPrintersStreaming:YES];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (self.discoverSink != nil) {
          self.discoverSink(@{@"done" : @YES});
        }
      });
    });
    return;
  }

  if ([call.method isEqualToString:@"cancelDiscover"]) {
    self.discoverCancelled = YES;
    result(nil);
    return;
  }

  if ([call.method isEqualToString:@"pair"] || [call.method isEqualToString:@"unpair"]) {
    // MFi pairing is performed in iOS Settings.
    result(@"openSystemSettings");
    return;
  }

  if ([call.method isEqualToString:@"pairedAccessories"] ||
      [call.method isEqualToString:@"bondedPrinters"]) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      NSArray *found = [self discoverPrintersStreaming:NO];
      dispatch_async(dispatch_get_main_queue(), ^{ result(found); });
    });
    return;
  }

  if ([call.method isEqualToString:@"ensureBluetoothPermissions"]) {
    // Accessory / Bluetooth usage is gated by Info.plist strings; there is no
    // runtime BT permission prompt equivalent to Android 12+.
    result(@"granted");
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

- (NSArray *)discoverPrintersStreaming:(BOOL)stream {
  NSMutableArray *found = [NSMutableArray array];
  NSArray<EAAccessory *> *accessories =
      [EAAccessoryManager sharedAccessoryManager].connectedAccessories;
  for (EAAccessory *accessory in accessories) {
    if (self.discoverCancelled) break;
    NSString *address =
        accessory.serialNumber.length > 0 ? accessory.serialNumber : accessory.name;
    NSDictionary *map = @{
      @"id" : [NSString stringWithFormat:@"bluetooth:%@", address],
      @"address" : address ?: @"",
      @"connectionType" : @"bluetooth",
      @"name" : accessory.name ?: address ?: @"",
      @"serialNumber" : accessory.serialNumber ?: [NSNull null],
      @"model" : accessory.modelNumber ?: [NSNull null],
      @"macAddress" : [NSNull null],
      @"manufacturer" : @"Zebra",
      @"rssi" : [NSNull null],
      @"paired" : @YES,
    };
    [found addObject:map];
    if (stream && self.discoverSink != nil) {
      dispatch_async(dispatch_get_main_queue(), ^{ self.discoverSink(map); });
    }
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
    NSInteger port = parts.count > 1 ? [(NSString *)parts[1] integerValue] : 9100;
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
