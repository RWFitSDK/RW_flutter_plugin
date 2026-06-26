#import "RwfitBlePlugin.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import <DHBleSDK/DHBleSDK.h>

/**
 * RWFIT 智能戒指 BLE 插件（iOS）。
 * 从 uni 版 RWFitBleModule.m 移植：方法体几乎原样搬运，
 * 仅把 (options, callback) 换成 (args, FlutterResult)，把 fireEvent 改走 FlutterEventSink。
 * iOS 返回值本就是 NSDictionary/NSArray（codec-safe），无 FastJSON 转换问题。
 */
@interface RwfitBlePlugin () <DHBleConnectDelegate>
@property (nonatomic, copy) FlutterEventSink eventSink;
@property (nonatomic, strong) DeviceFuncV2Model *deviceFuncModel;
@property (nonatomic, assign) BOOL scanning;
@property (nonatomic, assign) BOOL observersRegistered;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DHPeripheralModel *> *discoveredDevices;
@end

@implementation RwfitBlePlugin

#pragma mark - FlutterPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *method =
        [FlutterMethodChannel methodChannelWithName:@"rwfit_ble/methods"
                                    binaryMessenger:[registrar messenger]];
    FlutterEventChannel *event =
        [FlutterEventChannel eventChannelWithName:@"rwfit_ble/events"
                                  binaryMessenger:[registrar messenger]];
    RwfitBlePlugin *instance = [[RwfitBlePlugin alloc] init];
    instance.discoveredDevices = [NSMutableDictionary dictionary];
    [registrar addMethodCallDelegate:instance channel:method];
    [event setStreamHandler:instance];
}

#pragma mark - FlutterStreamHandler

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
    self.eventSink = events;
    return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
    self.eventSink = nil;
    return nil;
}

#pragma mark - 方法分发

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSDictionary *args = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};
    NSString *m = call.method;

    if ([m isEqualToString:@"initSDK"]) {
        [DHBleCentralManager setLogStatus:YES];
        [DHBleCentralManager initWithServiceUuids:@[]];
        [DHBleCentralManager shareInstance].connectDelegate = self;
        self.scanning = NO;
        self.discoveredDevices = [NSMutableDictionary dictionary];
        [self registerObserversIfNeeded];
        [self ok:result extra:nil];
    } else if ([m isEqualToString:@"getSDKVersion"]) {
        [self ok:result extra:@{@"version": [DHBleCommand getSDKVersion] ?: @""}];
    } else if ([m isEqualToString:@"getPluginVersion"]) {
        NSString *v = [NSString stringWithFormat:@"0.0.1_%@", [DHBleCommand getSDKVersion] ?: @""];
        [self ok:result extra:@{@"pluginVersion": v}];
    } else if ([m isEqualToString:@"isBleConnected"]) {
        [self ok:result extra:@{@"connected": @([DHBleCentralManager isConnected])}];
    } else if ([m isEqualToString:@"startScan"]) {
        [DHBleCentralManager shareInstance].connectDelegate = self;
        self.scanning = YES;
        [self.discoveredDevices removeAllObjects];
        [DHBleCentralManager startScan];
        [self ok:result extra:nil];
    } else if ([m isEqualToString:@"stopScan"]) {
        self.scanning = NO;
        [DHBleCentralManager stopScan];
        [self fire:@"rwfit:scanFinish" data:@{}];
        [self ok:result extra:nil];
    } else if ([m isEqualToString:@"connectDevice"]) {
        [self connectDevice:args result:result];
    } else if ([m isEqualToString:@"disconnect"]) {
        [DHBleCentralManager disconnectDevice];
        [self ok:result extra:nil];
    } else if ([m isEqualToString:@"reconnectDevice"]) {
        [DHBleCentralManager shareInstance].connectDelegate = self;
        [DHBleCentralManager checkAndAutoReconnectDevice];
        [self ok:result extra:nil];
    } else if ([m isEqualToString:@"iOSSetBindedStatus"]) {
        [DHBleCentralManager setBindedStatus:[args[@"isBinded"] boolValue]];
        [self ok:result extra:nil];
    } else if ([m isEqualToString:@"getPower"]) {
        [DHBleCommand getBattery:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{
                DHBatteryInfoModel *model = data;
                [self ok:result extra:@{@"power": @([model battery])}];
            }];
        }];
    } else if ([m isEqualToString:@"getFirmwareVersion"]) {
        [DHBleCommand getFirmwareVersion:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{
                DHFirmwareVersionModel *model = data;
                [self ok:result extra:@{
                    @"deviceClazz": model.deviceModel ?: @"",
                    @"deviceNo": model.firmwareVersion ?: @"",
                    @"uiVersion": model.uiVersion ?: @""
                }];
            }];
        }];
    } else if ([m isEqualToString:@"setUserInfo"]) {
        DHUserInfoSetModel *model = [DHUserInfoSetModel new];
        model.gender = [args[@"gender"] integerValue];
        // iOS SDK 的 height/weight 是 NSInteger，Dart 传浮点 cm/kg，桥接层 ×10 保 0.1 精度
        model.height = (NSInteger)round([args[@"height"] doubleValue] * 10);
        model.weight = (NSInteger)round([args[@"weight"] doubleValue] * 10);
        model.age = [args[@"age"] integerValue];
        [DHBleCommand setUserInfo:model block:^(int code, id data) {
            [self simple:code result:result action:@"setUserInfo"];
        }];
    } else if ([m isEqualToString:@"setTimeFormat"]) {
        UInt8 format = [args[@"format"] unsignedCharValue];
        [DHBleCommand ringSetTimeformat:format block:^(int code, id data) {
            [self simple:code result:result action:@"setTimeFormat"];
        }];
    } else if ([m isEqualToString:@"getFunctionList"]) {
        NSDictionary *menu = self.deviceFuncModel ? [self supportMenuDictionary:self.deviceFuncModel] : @{};
        [self ok:result extra:@{@"supportMenu": menu}];
    } else if ([m isEqualToString:@"controlHealthData"]) {
        NSNumber *dataType = [self dataTypeFromControlKey:[self stringValue:args[@"key"]]];
        if (dataType == nil) {
            [self fail:result code:-1 msg:@"unsupported control key"];
        } else {
            NSInteger state = [args[@"state"] integerValue];
            [DHBleCommand controlOpen:state dataType:[dataType integerValue] block:^(int code, id data) {
                [self simple:code result:result action:@"controlHealthData"];
            }];
        }
    } else if ([m isEqualToString:@"controlFindDevice"]) {
        [DHBleCommand controlFindDeviceBegin:^(int code, id data) {
            [self simple:code result:result action:@"controlFindDevice"];
        }];
    } else if ([m isEqualToString:@"setPowerOff"]) {
        NSInteger type = [args[@"type"] integerValue];
        [DHBleCommand controlDevice:type block:^(int code, id data) {}];
        [self ok:result extra:nil];
    } else if ([m isEqualToString:@"ringOta"]) {
        NSData *fileData = [self fileDataFromOptions:args];
        if (fileData == nil) {
            [self fail:result code:-1 msg:@"ota file not found"];
        } else {
            [DHBleCommand ringOtaWithFileData:fileData block:^(int code, CGFloat progress, id data) {
                [self fire:@"rwfit:otaProgress" data:@{@"progress": @(progress)}];
                if (progress >= 1.0f && code == 0) {
                    [self fire:@"rwfit:otaFinish" data:@{}];
                } else if (code != 0) {
                    [self fire:@"rwfit:otaFinish" data:@{@"code": @(code)}];
                }
            }];
            [self ok:result extra:nil];
        }
    } else if ([m isEqualToString:@"pushMessage"]) {
        [self ok:result extra:nil]; // iOS 走系统 ANCS，主动推消息为 no-op
    } else if ([m isEqualToString:@"setRingBtName"]) {
        [DHBleCommand setRingBtName:[self stringValue:args[@"name"]] block:^(int code, id data) {
            [self simple:code result:result action:@"setRingBtName"];
        }];
    } else if ([m isEqualToString:@"syncAllHealthData"]) {
        [self startHealthSync:result];
    } else if ([m isEqualToString:@"removeHealthDataCallback"]) {
        [self ok:result extra:nil];
    } else if ([m isEqualToString:@"unbind"]) {
        [DHBleCentralManager setBindedStatus:NO];
        [DHBleCentralManager disconnectDevice];
        [self ok:result extra:nil];
    } else if ([m isEqualToString:@"controlTakePhoto"]) {
        [DHBleCommand controlCamera:[args[@"state"] integerValue] block:^(int code, id data) {
            [self simple:code result:result action:@"controlTakePhoto"];
        }];
    }
    // ---- 全天检测（6 项）----
    else if ([m isEqualToString:@"getTimedHeartRate"]) { [self timedGet:@"hr" result:result]; }
    else if ([m isEqualToString:@"setTimedHeartRate"]) { [self timedSet:@"hr" args:args result:result]; }
    else if ([m isEqualToString:@"getTimedBloodOxygen"]) { [self timedGet:@"bo" result:result]; }
    else if ([m isEqualToString:@"setTimedBloodOxygen"]) { [self timedSet:@"bo" args:args result:result]; }
    else if ([m isEqualToString:@"getTimedHRV"]) { [self timedGet:@"hrv" result:result]; }
    else if ([m isEqualToString:@"setTimedHRV"]) { [self timedSet:@"hrv" args:args result:result]; }
    else if ([m isEqualToString:@"getTimedStress"]) { [self timedGet:@"stress" result:result]; }
    else if ([m isEqualToString:@"setTimedStress"]) { [self timedSet:@"stress" args:args result:result]; }
    else if ([m isEqualToString:@"getTimedBloodSugar"]) { [self timedGet:@"sugar" result:result]; }
    else if ([m isEqualToString:@"setTimedBloodSugar"]) { [self timedSet:@"sugar" args:args result:result]; }
    else if ([m isEqualToString:@"getTimedBloodPressure"]) { [self timedGet:@"bp" result:result]; }
    else if ([m isEqualToString:@"setTimedBloodPressure"]) { [self timedSet:@"bp" args:args result:result]; }
    // ---- 闹钟 ----
    else if ([m isEqualToString:@"getAlarm"]) {
        [DHBleCommand getAlarms:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{
                NSMutableArray *alarms = [NSMutableArray array];
                for (DHAlarmSetModel *item in (NSArray *)data) [alarms addObject:[self alarmDictionary:item]];
                [self ok:result extra:@{@"data": alarms}];
            }];
        }];
    }
    else if ([m isEqualToString:@"setAlarm"]) {
        NSMutableArray *alarms = [NSMutableArray array];
        for (NSDictionary *item in (NSArray *)args[@"alarms"]) {
            DHAlarmSetModel *model = [DHAlarmSetModel new];
            model.isOpen = [item[@"isOpen"] boolValue];
            model.hour = [item[@"startHour"] integerValue];
            model.minute = [item[@"startMin"] integerValue];
            model.alarmType = [self stringValue:item[@"alarmTag"]];
            model.jlAlarmId = [item[@"alarmId"] unsignedCharValue];
            model.repeats = item[@"repeats"] ?: @[@0, @0, @0, @0, @0, @0, @0];
            [alarms addObject:model];
        }
        [DHBleCommand setAlarms:alarms block:^(int code, id data) {
            [self simple:code result:result action:@"setAlarm"];
        }];
    }
    else if ([m isEqualToString:@"deleteAllAlarm"]) {
        [DHBleCommand setAlarms:@[] block:^(int code, id data) {
            [self simple:code result:result action:@"deleteAllAlarm"];
        }];
    }
    // ---- 屏幕 ----
    else if ([m isEqualToString:@"getRaiseBrightScreen"]) {
        [DHBleCommand ringGetGesture:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{
                DHGestureSetModel *md = data;
                [self ok:result extra:@{@"isOpen": @([md isOpen]), @"startHour": @([md startHour]),
                    @"startMin": @([md startMinute]), @"endHour": @([md endHour]), @"endMin": @([md endMinute])}];
            }];
        }];
    }
    else if ([m isEqualToString:@"setRaiseBrightScreen"]) {
        DHGestureSetModel *md = [DHGestureSetModel new];
        md.isOpen = [args[@"isOpen"] boolValue];
        md.startHour = [args[@"startHour"] integerValue];
        md.startMinute = [args[@"startMin"] integerValue];
        md.endHour = [args[@"endHour"] integerValue];
        md.endMinute = [args[@"endMin"] integerValue];
        [DHBleCommand ringSetGesture:md block:^(int code, id data) {
            [self simple:code result:result action:@"setRaiseBrightScreen"];
        }];
    }
    else if ([m isEqualToString:@"getBrightScreenTime"]) {
        [DHBleCommand getBrightTime:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{
                DHBrightTimeSetModel *md = data;
                [self ok:result extra:@{@"timeSecond": @([md duration])}];
            }];
        }];
    }
    else if ([m isEqualToString:@"setBrightScreenTime"]) {
        DHBrightTimeSetModel *md = [DHBrightTimeSetModel new];
        md.duration = [args[@"timeSecond"] integerValue];
        [DHBleCommand setBrightTime:md block:^(int code, id data) {
            [self simple:code result:result action:@"setBrightScreenTime"];
        }];
    }
    else if ([m isEqualToString:@"getBrightScreenSleepTime"]) {
        [DHBleCommand getDisplaySleepMode:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{
                DHBrightTimeSetModel *md = data;
                [self ok:result extra:@{@"isOpen": @([md sleepOpen]), @"startHour": @([md sleepStartHour]),
                    @"startMin": @([md sleepStartMin]), @"endHour": @([md sleepEndHour]), @"endMin": @([md sleepEndMin])}];
            }];
        }];
    }
    else if ([m isEqualToString:@"setBrightScreenSleepTime"]) {
        DHBrightTimeSetModel *md = [DHBrightTimeSetModel new];
        md.sleepOpen = [args[@"isOpen"] boolValue];
        md.sleepStartHour = [args[@"startHour"] integerValue];
        md.sleepStartMin = [args[@"startMin"] integerValue];
        md.sleepEndHour = [args[@"endHour"] integerValue];
        md.sleepEndMin = [args[@"endMin"] integerValue];
        [DHBleCommand setDisplaySleepMode:md block:^(int code, id data) {
            [self simple:code result:result action:@"setBrightScreenSleepTime"];
        }];
    }
    else if ([m isEqualToString:@"getRingLedLevel"]) {
        [DHBleCommand getRingLEDLight:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{ [self ok:result extra:[self ledDictionary:data]]; }];
        }];
    }
    else if ([m isEqualToString:@"setRingLedLevel"]) {
        DHLedLightSetModel *md = [DHLedLightSetModel new];
        md.isOpen = [args[@"isOpen"] boolValue];
        md.lightLevel = [args[@"lcdLevel"] integerValue];
        [DHBleCommand setRingLEDLight:md block:^(int code, id data) {
            [self simple:code result:result action:@"setRingLedLevel"];
        }];
    }
    // ---- 视频 HID ----
    else if ([m isEqualToString:@"getVideoHid"]) {
        [DHBleCommand getVideoHid:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{
                DHVideoHidSetModel *md = data;
                [self ok:result extra:@{@"hidOpen": @([md isOpen])}];
            }];
        }];
    }
    else if ([m isEqualToString:@"setVideoHid"]) {
        DHVideoHidSetModel *md = [DHVideoHidSetModel new];
        md.isOpen = [args[@"hidOpen"] intValue];
        [DHBleCommand setVideoHid:md block:^(int code, id data) {
            [self simple:code result:result action:@"setVideoHid"];
        }];
    }
    // ---- 佩戴方向 ----
    else if ([m isEqualToString:@"getRingWearDir"]) {
        [DHBleCommand getRingWearHand:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{
                [self ok:result extra:@{@"isRight": @([data integerValue] == 1)}];
            }];
        }];
    }
    else if ([m isEqualToString:@"setRingWearHand"]) {
        UInt8 hand = [args[@"isRight"] boolValue] ? 1 : 0;
        [DHBleCommand setRingWearHand:hand block:^(int code, id data) {
            [self simple:code result:result action:@"setRingWearHand"];
        }];
    }
    // ---- 振动 ----
    else if ([m isEqualToString:@"getVibrationCount"]) {
        [DHBleCommand getRingMotorLevel:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{
                DHVibrationLevelModel *md = data;
                [self ok:result extra:@{@"count": @([md vibrationNumber]), @"level": @([md vibrationLevel])}];
            }];
        }];
    }
    else if ([m isEqualToString:@"setVibrationCount"]) {
        [DHBleCommand setRingMotorLevel:[args[@"level"] integerValue] motorNum:[args[@"count"] integerValue] block:^(int code, id data) {
            [self simple:code result:result action:@"setVibrationCount"];
        }];
    }
    else if ([m isEqualToString:@"getAlarmVibrationDuration"]) {
        [DHBleCommand getAlarmVibrationDuration:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{
                [self ok:result extra:@{@"duration": @([data integerValue])}];
            }];
        }];
    }
    else if ([m isEqualToString:@"setAlarmVibrationDuration"]) {
        [DHBleCommand setAlarmVibrationDuration:[args[@"duration"] unsignedCharValue] block:^(int code, id data) {
            [self simple:code result:result action:@"setAlarmVibrationDuration"];
        }];
    }
    // ---- 通知开关（iOS 专用 ANCS）----
    else if ([m isEqualToString:@"setNotificationSwitch"]) {
        DHAncsSetModel *md = [DHAncsSetModel new];
        for (NSString *key in [args allKeys]) {
            id value = args[key];
            if (![value respondsToSelector:@selector(boolValue)]) continue;
            @try { [md setValue:@([value boolValue]) forKey:key]; } @catch (NSException *e) { (void)e; }
        }
        [DHBleCommand ringSetAncs:md block:^(int code, id data) {
            [self simple:code result:result action:@"setNotificationSwitch"];
        }];
    }
    else if ([m isEqualToString:@"getNotificationSwitch"]) {
        [DHBleCommand ringGetAncs:^(int code, id data) {
            [self handleCode:code result:result successBlock:^{
                [self ok:result extra:@{@"switches": [self switchesDictFromAncs:data]}];
            }];
        }];
    }
    // ---- Android 专用，iOS no-op ----
    else if ([m isEqualToString:@"createOrRemoveBond"]) {
        [self ok:result extra:@{@"result": @NO}]; // iOS 无蓝牙 HID 配对概念
    }
    else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)connectDevice:(NSDictionary *)args result:(FlutterResult)result {
    self.scanning = NO;
    [DHBleCentralManager stopScan];
    NSString *mac = [self stringValue:args[@"mac"]];
    NSString *uuid = [self stringValue:args[@"uuid"]];
    DHPeripheralModel *model = [self cachedPeripheralForMac:mac uuid:uuid];
    if (model == nil) {
        [self fail:result code:-1 msg:@"device not in scan cache; call startScan() first, or use reconnectDevice()"];
        return;
    }
    [DHBleCentralManager shareInstance].connectDelegate = self;
    [self fire:@"rwfit:connectState" data:@{
        @"state": @"connecting",
        @"name": model.name ?: @"",
        @"mac": model.macAddr ?: @"",
        @"uuid": model.uuid ?: @""
    }];
    [DHBleCentralManager connectDeviceWithModel:model];
    [self ok:result extra:nil];
}

#pragma mark - DHBleConnectDelegate（事件源）

- (void)centralManagerDidDiscoverPeripheral:(NSArray<DHPeripheralModel *> *)peripherals {
    if (!self.scanning) return;
    for (DHPeripheralModel *item in peripherals) {
        [self cachePeripheral:item];
        [self fire:@"rwfit:scanResult" data:@{
            @"name": item.name ?: @"",
            @"mac": item.macAddr ?: @"",
            @"uuid": item.uuid ?: @"",
            @"rssi": @(-labs(item.rssi))
        }];
    }
}

- (void)centralManagerDidConnectPeripheral:(CBPeripheral *)peripheral {
    self.scanning = NO;
    [self fire:@"rwfit:connectState" data:[self connectStatePayload:@"connected" peripheral:peripheral extra:nil]];
}

- (void)centralManagerDidFunctionMenu:(DeviceFuncV2Model *)deviceFuncModel peripheral:(DHPeripheralModel *)peripheral {
    self.deviceFuncModel = deviceFuncModel;
    [self fire:@"rwfit:functionMenu" data:@{
        @"state": @"ready",
        @"name": peripheral.name ?: @"",
        @"mac": peripheral.macAddr ?: @"",
        @"uuid": peripheral.uuid ?: @"",
        @"supportMenu": [self supportMenuDictionary:deviceFuncModel]
    }];
}

- (void)centralManagerDidDisconnectPeripheral:(CBPeripheral *)peripheral {
    self.scanning = NO;
    [self fire:@"rwfit:connectState" data:[self connectStatePayload:@"disconnected" peripheral:peripheral extra:nil]];
}

- (void)centralManagerDidFailedPeripheral:(CBPeripheral *)peripheral {
    self.scanning = NO;
    [self fire:@"rwfit:connectState" data:[self connectStatePayload:@"failed" peripheral:peripheral extra:@{@"reason": @"unknown"}]];
}

#pragma mark - 事件转发

- (void)fire:(NSString *)name data:(NSDictionary *)data {
    NSMutableDictionary *d = data ? [data mutableCopy] : [NSMutableDictionary dictionary];
    d[@"event"] = name;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.eventSink) self.eventSink(d);
    });
}

#pragma mark - 结果回传（失败也走 success 回 {code,msg}，对齐 Dart callAsync 契约）

- (void)ok:(FlutterResult)result extra:(NSDictionary *)extra {
    NSMutableDictionary *r = [@{@"code": @0, @"msg": @"success"} mutableCopy];
    if (extra) [r addEntriesFromDictionary:extra];
    dispatch_async(dispatch_get_main_queue(), ^{ result(r); });
}

- (void)fail:(FlutterResult)result code:(NSInteger)code msg:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        result(@{@"code": @(code), @"msg": msg ?: @"error"});
    });
}

- (void)handleCode:(int)code result:(FlutterResult)result successBlock:(void (^)(void))successBlock {
    if (code == 0) {
        successBlock();
    } else {
        [self fail:result code:code msg:@"native call failed"];
    }
}

- (void)simple:(int)code result:(FlutterResult)result action:(NSString *)action {
    if (code == 0) {
        [self ok:result extra:nil];
    } else {
        [self fail:result code:code msg:[NSString stringWithFormat:@"%@ failed", action]];
    }
}

- (NSNumber *)dataTypeFromControlKey:(NSString *)key {
    static NSDictionary *mapping;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mapping = @{
            @"JL_HR_DATA_TRANSFER_KEY": @(BLE_KEY_HEART_RATE),
            @"JL_BO_DATA_TRANSFER_KEY": @(BLE_KEY_BLOOD_OXYGEN),
            @"JL_HRV_DATA_TRANSFER_KEY": @(BLE_KEY_HRV),
            @"JL_PRESSURE_DATA_TRANSFER_KEY": @(BLE_KEY_STRESS),
            @"JL_BLOODSUGAR_DATA_TRANSFER_KEY": @(BLE_KEY_BLOOD_SUGAR),
            @"JL_BP_DATA_TRANSFER_KEY": @(BLE_KEY_BLOOD_PRESSURE)
        };
    });
    return mapping[key];
}

- (NSData *)fileDataFromOptions:(NSDictionary *)options {
    NSString *path = [self stringValue:options[@"path"]];
    if ([path hasPrefix:@"file://"]) {
        path = [[NSURL URLWithString:path] path];
    }
    if (path.length == 0) return nil;
    return [NSData dataWithContentsOfFile:path];
}

#pragma mark - 实时 / 拍照 通知观察者

- (void)registerObserversIfNeeded {
    if (self.observersRegistered) return;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(handleMeasureValue:)
                   name:BluetoothNotificationHealthRingMeasureValueChange object:nil];
    [center addObserver:self selector:@selector(handleCameraTakePicture:)
                   name:BluetoothNotificationCameraTakePicture object:nil];
    self.observersRegistered = YES;
}

- (void)handleMeasureValue:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo ?: @{};
    NSInteger iosType = [userInfo[@"dataType"] integerValue];
    NSInteger dataType;
    switch (iosType) {
        case BLE_KEY_APP_REAL_TIME_HR_DATA:           dataType = 1;  break;
        case BLE_KEY_APP_REAL_TIME_BLOOD_OXYGEN_DATA: dataType = 3;  break;
        case BLE_KEY_APP_REAL_TIME_BP_DATA:           dataType = 4;  break;
        case BLE_KEY_APP_REAL_TIME_STRESS_DATA:       dataType = 8;  break;
        case BLE_KEY_APP_REAL_BLOOD_SUGAR_DATA:       dataType = 9;  break;
        case BLE_KEY_APP_REAL_TIME_HRV_DATA:          dataType = 13; break;
        default: return;
    }
    NSMutableDictionary *event = [NSMutableDictionary dictionary];
    event[@"dataType"] = @(dataType);
    // iOS 通知无时间戳，桥接层补当前时间（毫秒，与 Dart timestampMs 对齐）
    event[@"time"] = @((long long)([[NSDate date] timeIntervalSince1970] * 1000));
    if (dataType == 4) {
        event[@"dataValue"] = userInfo[@"systolic"] ?: @0;
        event[@"diastolic"] = userInfo[@"diastolic"] ?: @0;
    } else {
        event[@"dataValue"] = userInfo[@"dataValue"] ?: @0;
    }
    [self fire:@"rwfit:healthData" data:event];
}

- (void)handleCameraTakePicture:(NSNotification *)notification {
    [self fire:@"rwfit:touchEvent" data:@{@"keyType": @0, @"touchType": @0, @"action": @"cameraTakePicture"}];
}

#pragma mark - 全天检测（6 项共用）

- (void)modeReply:(int)code data:(id)data result:(FlutterResult)result {
    [self handleCode:code result:result successBlock:^{
        [self ok:result extra:@{
            @"isOpen": @([[data valueForKey:@"isOpen"] boolValue]),
            @"duration": [data valueForKey:@"interval"] ?: @0,
            @"startHour": [data valueForKey:@"startHour"] ?: @0,
            @"startMin": [data valueForKey:@"startMinute"] ?: @0,
            @"endHour": [data valueForKey:@"endHour"] ?: @0,
            @"endMin": [data valueForKey:@"endMinute"] ?: @0
        }];
    }];
}

- (void)fillTimedModel:(id)model args:(NSDictionary *)args {
    [model setValue:@([args[@"isOpen"] boolValue]) forKey:@"isOpen"];
    [model setValue:@([args[@"startHour"] integerValue]) forKey:@"startHour"];
    [model setValue:@([args[@"startMin"] integerValue]) forKey:@"startMinute"];
    [model setValue:@([args[@"endHour"] integerValue]) forKey:@"endHour"];
    [model setValue:@([args[@"endMin"] integerValue]) forKey:@"endMinute"];
    [model setValue:@([args[@"duration"] integerValue]) forKey:@"interval"];
}

- (void)timedGet:(NSString *)type result:(FlutterResult)result {
    void (^blk)(int, id) = ^(int code, id data) { [self modeReply:code data:data result:result]; };
    if ([type isEqualToString:@"hr"]) { [DHBleCommand getHeartRateMode:blk]; }
    else if ([type isEqualToString:@"bo"]) { [DHBleCommand getBoMode:blk]; }
    else if ([type isEqualToString:@"hrv"]) { [DHBleCommand getHrvMode:blk]; }
    else if ([type isEqualToString:@"stress"]) { [DHBleCommand getStressMode:blk]; }
    else if ([type isEqualToString:@"sugar"]) { [DHBleCommand getBloodSugarMode:blk]; }
    else if ([type isEqualToString:@"bp"]) { [DHBleCommand getBpMode:blk]; }
}

- (void)timedSet:(NSString *)type args:(NSDictionary *)args result:(FlutterResult)result {
    void (^blk)(int, id) = ^(int code, id data) { [self simple:code result:result action:@"setTimed"]; };
    if ([type isEqualToString:@"hr"]) {
        DHHeartRateModeSetModel *md = [DHHeartRateModeSetModel new]; [self fillTimedModel:md args:args];
        [DHBleCommand setHeartRateMode:md block:blk];
    } else if ([type isEqualToString:@"bo"]) {
        DHBoModeSetModel *md = [DHBoModeSetModel new]; [self fillTimedModel:md args:args];
        [DHBleCommand setBoMode:md block:blk];
    } else if ([type isEqualToString:@"hrv"]) {
        DHHrvModeSetModel *md = [DHHrvModeSetModel new]; [self fillTimedModel:md args:args];
        [DHBleCommand setHrvMode:md block:blk];
    } else if ([type isEqualToString:@"stress"]) {
        DHStressModeSetModel *md = [DHStressModeSetModel new]; [self fillTimedModel:md args:args];
        [DHBleCommand setStressMode:md block:blk];
    } else if ([type isEqualToString:@"sugar"]) {
        DHBloodSugarModeSetModel *md = [DHBloodSugarModeSetModel new]; [self fillTimedModel:md args:args];
        [DHBleCommand setBloodSugarMode:md block:blk];
    } else if ([type isEqualToString:@"bp"]) {
        DHBpModeSetModel *md = [DHBpModeSetModel new]; [self fillTimedModel:md args:args];
        [DHBleCommand setBpMode:md block:blk];
    }
}

#pragma mark - payload 字典

- (NSDictionary *)alarmDictionary:(DHAlarmSetModel *)item {
    return @{
        @"alarmId": @([item jlAlarmId]),
        @"startHour": @([item hour]),
        @"startMin": @([item minute]),
        @"isOpen": @([item isOpen]),
        @"alarmTag": item.alarmType ?: @"",
        @"repeats": item.repeats ?: @[]
    };
}

- (NSDictionary *)ledDictionary:(DHLedLightSetModel *)model {
    return @{@"isOpen": @([model isOpen]), @"lcdLevel": @([model lightLevel])};
}

#pragma mark - 健康数据同步

- (void)startHealthSync:(FlutterResult)result {
    [DHBleCommand startDataSyncing:^(int code, id data) {
        if (code == 0) {
            [self fire:@"rwfit:syncFinish" data:@{}];
        } else {
            [self fire:@"rwfit:syncError" data:@{@"code": @(code)}];
        }
    } datablcok:^(int code, int progress, id data) {
        if (code != 0) {
            [self fire:@"rwfit:syncError" data:@{@"code": @(code)}];
            return;
        }
        [self fire:@"rwfit:syncProgress" data:@{@"progress": @(progress)}];
        if ([data isKindOfClass:[NSArray class]]) {
            NSDictionary *grouped = [self groupedSyncPayload:(NSArray *)data];
            for (NSString *type in grouped) {
                [self fire:@"rwfit:syncResult" data:@{@"type": type, @"data": grouped[type]}];
            }
        }
    }];
    [self ok:result extra:nil];
}

- (NSDictionary *)groupedSyncPayload:(NSArray *)items {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (id model in items) {
        NSString *type = nil;
        NSDictionary *dict = [self syncDictFromModel:model outType:&type];
        if (type.length == 0 || dict == nil) continue;
        NSMutableArray *bucket = result[type];
        if (bucket == nil) { bucket = [NSMutableArray array]; result[type] = bucket; }
        [bucket addObject:dict];
    }
    return result;
}

- (NSDictionary *)syncDictFromModel:(id)model outType:(NSString **)outType {
    if (model == nil) return nil;
    if ([model isKindOfClass:NSClassFromString(@"DHDailyStepModel")])        { *outType = @"step";        return [self stepDictFromModel:model]; }
    if ([model isKindOfClass:NSClassFromString(@"DHDailySleepModel")])       { *outType = @"sleep";       return [self sleepDictFromModel:model]; }
    if ([model isKindOfClass:NSClassFromString(@"DHDailyHrModel")])          { *outType = @"hr";          return [self dayDictFromModel:model itemKey:@"hr"]; }
    if ([model isKindOfClass:NSClassFromString(@"DHDailyBoModel")])          { *outType = @"bo";          return [self dayDictFromModel:model itemKey:@"bloodOxy"]; }
    if ([model isKindOfClass:NSClassFromString(@"DHDailyHrvModel")])         { *outType = @"hrv";         return [self dayDictFromModel:model itemKey:@"hrv"]; }
    if ([model isKindOfClass:NSClassFromString(@"DHDailyPressureModel")])    { *outType = @"pressure";    return [self dayDictFromModel:model itemKey:@"pressure"]; }
    if ([model isKindOfClass:NSClassFromString(@"DHDailyBloodSugarModel")])  { *outType = @"bloodSugar";  return [self dayDictFromModel:model itemKey:@"bloodSugar"]; }
    if ([model isKindOfClass:NSClassFromString(@"DHDailyTempModel")])        { *outType = @"temp";        return [self dayDictFromModel:model itemKey:@"temp"]; }
    if ([model isKindOfClass:NSClassFromString(@"DHDailyBpModel")])          { *outType = @"bp";          return [self bpDictFromModel:model]; }
    if ([model isKindOfClass:NSClassFromString(@"DHDailyMuslimCountModel")]) { *outType = @"muslimCount"; return [self muslimDictFromModel:model]; }
    return nil;
}

- (NSNumber *)numberFromTimestamp:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSString class]]) return @([(NSString *)value longLongValue]);
    return @0;
}

- (NSDictionary *)stepDictFromModel:(id)model {
    NSArray *rawItems = [model valueForKey:@"items"];
    if (![rawItems isKindOfClass:[NSArray class]]) rawItems = @[];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *it in rawItems) {
        if (![it isKindOfClass:[NSDictionary class]]) continue;
        [items addObject:@{@"index": it[@"index"] ?: @0, @"steps": it[@"step"] ?: @0,
            @"calorie": it[@"calorie"] ?: @0, @"distance": it[@"distance"] ?: @0}];
    }
    return @{@"time": [self numberFromTimestamp:[model valueForKey:@"timestamp"]],
        @"date": [self stringValue:[model valueForKey:@"date"]],
        @"totalSteps": @([[model valueForKey:@"step"] integerValue]),
        @"totalCalorie": @([[model valueForKey:@"calorie"] integerValue]),
        @"totalDistance": @([[model valueForKey:@"distance"] integerValue]), @"items": items};
}

- (NSDictionary *)sleepDictFromModel:(id)model {
    NSArray *rawItems = [model valueForKey:@"items"];
    if (![rawItems isKindOfClass:[NSArray class]]) rawItems = @[];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *it in rawItems) {
        if (![it isKindOfClass:[NSDictionary class]]) continue;
        [items addObject:@{@"len": it[@"value"] ?: @0, @"sleepType": it[@"status"] ?: @0}];
    }
    return @{@"time": [self numberFromTimestamp:[model valueForKey:@"timestamp"]],
        @"date": [self stringValue:[model valueForKey:@"date"]],
        @"duration": @([[model valueForKey:@"duration"] integerValue]),
        @"beginTime": [self numberFromTimestamp:[model valueForKey:@"beginTime"]],
        @"endTime": [self numberFromTimestamp:[model valueForKey:@"endTime"]], @"items": items};
}

- (NSDictionary *)dayDictFromModel:(id)model itemKey:(NSString *)itemKey {
    NSArray *rawItems = [model valueForKey:@"items"];
    if (![rawItems isKindOfClass:[NSArray class]]) rawItems = @[];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *it in rawItems) {
        if (![it isKindOfClass:[NSDictionary class]]) continue;
        [items addObject:@{@"time": [self numberFromTimestamp:it[@"timestamp"]], itemKey: it[@"value"] ?: @0}];
    }
    return @{@"time": [self numberFromTimestamp:[model valueForKey:@"timestamp"]],
        @"date": [self stringValue:[model valueForKey:@"date"]], @"items": items};
}

- (NSDictionary *)bpDictFromModel:(id)model {
    NSArray *rawItems = [model valueForKey:@"items"];
    if (![rawItems isKindOfClass:[NSArray class]]) rawItems = @[];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *it in rawItems) {
        if (![it isKindOfClass:[NSDictionary class]]) continue;
        [items addObject:@{@"time": [self numberFromTimestamp:it[@"timestamp"]],
            @"systolic": it[@"systolic"] ?: @0, @"diastolic": it[@"diastolic"] ?: @0}];
    }
    return @{@"time": [self numberFromTimestamp:[model valueForKey:@"timestamp"]],
        @"date": [self stringValue:[model valueForKey:@"date"]], @"items": items};
}

- (NSDictionary *)muslimDictFromModel:(id)model {
    NSArray *rawItems = [model valueForKey:@"items"];
    if (![rawItems isKindOfClass:[NSArray class]]) rawItems = @[];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *it in rawItems) {
        if (![it isKindOfClass:[NSDictionary class]]) continue;
        [items addObject:@{@"time": [self numberFromTimestamp:it[@"timestamp"]], @"count": it[@"value"] ?: @0}];
    }
    return @{@"time": [self numberFromTimestamp:[model valueForKey:@"timestamp"]],
        @"date": [self stringValue:[model valueForKey:@"date"]],
        @"totalCount": @([[model valueForKey:@"muslimcount"] integerValue]), @"items": items};
}

- (NSDictionary *)switchesDictFromAncs:(DHAncsSetModel *)model {
    if (![model isKindOfClass:[DHAncsSetModel class]]) return @{};
    return @{
        @"isCall": @(model.isCall), @"isSMS": @(model.isSMS), @"isQQ": @(model.isQQ),
        @"isWechat": @(model.isWechat), @"isWhatsapp": @(model.isWhatsapp), @"isMessenger": @(model.isMessenger),
        @"isTwitter": @(model.isTwitter), @"isLinkedin": @(model.isLinkedin), @"isInstagram": @(model.isInstagram),
        @"isFacebook": @(model.isFacebook), @"isLine": @(model.isLine), @"isWechatWork": @(model.isWechatWork),
        @"isDingding": @(model.isDingding), @"isEmail": @(model.isEmail), @"isCalendar": @(model.isCalendar),
        @"isViber": @(model.isViber), @"isSkype": @(model.isSkype), @"isKakaotalk": @(model.isKakaotalk),
        @"isTumblr": @(model.isTumblr), @"isSnapchat": @(model.isSnapchat), @"isYoutube": @(model.isYoutube),
        @"isPinterset": @(model.isPinterset), @"isTiktok": @(model.isTiktok), @"isGmail": @(model.isGmail),
        @"isJLSinaWeiBo": @(model.isJLSinaWeiBo), @"isJLBand": @(model.isJLBand), @"isJLTelegram": @(model.isJLTelegram),
        @"isJLBetween": @(model.isJLBetween), @"isJLNavercafe": @(model.isJLNavercafe), @"isJLNetflix": @(model.isJLNetflix),
        @"isMax": @(model.isMax), @"isVkim": @(model.isVkim), @"isOther": @(model.isOther)
    };
}

#pragma mark - 扫描缓存 / payload 工具

- (NSString *)stringValue:(id)value {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

- (void)cachePeripheral:(DHPeripheralModel *)model {
    if (model == nil) return;
    if (model.uuid.length > 0) {
        self.discoveredDevices[[NSString stringWithFormat:@"uuid:%@", model.uuid]] = model;
    }
    if (model.macAddr.length > 0) {
        self.discoveredDevices[[NSString stringWithFormat:@"mac:%@", model.macAddr]] = model;
    }
}

- (DHPeripheralModel *)cachedPeripheralForMac:(NSString *)mac uuid:(NSString *)uuid {
    if (uuid.length > 0) {
        DHPeripheralModel *model = self.discoveredDevices[[NSString stringWithFormat:@"uuid:%@", uuid]];
        if (model != nil) return model;
    }
    if (mac.length > 0) {
        DHPeripheralModel *model = self.discoveredDevices[[NSString stringWithFormat:@"mac:%@", mac]];
        if (model != nil) return model;
    }
    return nil;
}

- (NSDictionary *)connectStatePayload:(NSString *)state peripheral:(CBPeripheral *)peripheral extra:(NSDictionary *)extra {
    DHPeripheralModel *cached = nil;
    NSString *cbUuid = peripheral.identifier.UUIDString;
    if (cbUuid.length > 0) {
        cached = self.discoveredDevices[[NSString stringWithFormat:@"uuid:%@", cbUuid]];
    }
    NSMutableDictionary *payload = [@{
        @"state": state,
        @"name":  peripheral.name ?: cached.name ?: @"",
        @"mac":   cached.macAddr ?: @"",
        @"uuid":  cached.uuid ?: cbUuid ?: @""
    } mutableCopy];
    if (extra) [payload addEntriesFromDictionary:extra];
    return payload;
}

- (NSDictionary *)supportMenuDictionary:(DeviceFuncV2Model *)model {
    return @{
        @"isStep": @([model isDataTypeActivity]),
        @"isSleep": @([model isDataTypeSleep]),
        @"isHr": @([model isDataTypeHeart]),
        @"isBloodOxy": @([model isDataTypeSPO2]),
        @"isBloodPress": @([model isDataTypeBloodPressure]),
        @"isBloodSugar": @([model isDataTypeBloodSugar]),
        @"isHrv": @([model isDataTypeHRV]),
        @"isPressure": @([model isDataTypeStress]),
        @"isBodyTemp": @NO,
        @"isAlarm": @([model isAlarm]),
        @"isBrightScreenTime": @([model isBackLight]),
        @"isBrightScreenSleepTime": @([model isBackLightSleepMode]),
        @"isPushMsgEnableSwitch": @([model isPushMsgEnableSwitch]),
        @"isFindDevice": @([model isFindDevice]),
        @"isTakePhoto": @([model isTakePhoto]),
        @"isSupportMotoVibrationLevel": @([model isSupportMotoVibrationLevel]),
        @"isSupportAlarmVibrationDuration": @([model isSupportAlarmVibrationDuration]),
        @"isMuslimCountData": @([model isDataTypeMuslimCount]),
        @"isSupportMuslimTimeDisplayMode": @([model isSupportMuslimTimeDisplayMode])
    };
}

@end
