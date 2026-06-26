package com.rwfit.rwfit_ble;

import android.app.Activity;
import android.content.Context;
import android.media.AudioManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.KeyEvent;

import androidx.annotation.NonNull;

import com.alibaba.fastjson.JSONArray;
import com.alibaba.fastjson.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.example.blesdk.DHBleSdk;
import com.example.blesdk.bean.function.*;
import com.example.blesdk.bean.sync.*;
import com.example.blesdk.ble.ScanBleService;
import com.example.blesdk.ble.bean.BleDevice;
import com.example.blesdk.callback.OnFileTransferCallback;
import com.example.blesdk.callback.data.*;
import com.example.blesdk.callback.status.*;
import com.example.blesdk.utils.BlueToothUtils;
import com.example.blesdk.utils.CmdConstants;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

/**
 * RWFIT 智能戒指 BLE 插件（Android）。
 * 从 uni 版 RWFitBleModule 移植：方法体几乎原样搬运，仅替换"入参来源"与"结果回传"两层外壳，
 * 并把 FastJSON 对象经 {@link #toCodecSafe} 转成 Map/List 后再回传（StandardMessageCodec 不认 FastJSON）。
 */
public class RwfitBlePlugin implements FlutterPlugin, MethodCallHandler,
        EventChannel.StreamHandler, ActivityAware {

    private static final String TAG = "RwfitBlePlugin";
    private static final String PLUGIN_VERSION = "0.0.1";

    private MethodChannel methodChannel;
    private EventChannel eventChannel;
    private EventChannel.EventSink eventSink;
    private Activity activity;
    private final Handler main = new Handler(Looper.getMainLooper());

    // 长期订阅引用（切换/重设时先 dispose 旧的，避免事件叠加）
    private HealthDataBroCallback realtimeDataCallback;
    private TakePhotoCallback takePhotoEventCallback;
    private MusicPushSettingCallback musicControlEventCallback;

    private RWFitCallbackManager cb() {
        RWFitCallbackManager m = RWFitCallbackManager.getInstance();
        m.setSink(eventSink);
        m.setPlugin(this);
        return m;
    }

    // ==================== FlutterPlugin ====================

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        methodChannel = new MethodChannel(binding.getBinaryMessenger(), "rwfit_ble/methods");
        methodChannel.setMethodCallHandler(this);
        eventChannel = new EventChannel(binding.getBinaryMessenger(), "rwfit_ble/events");
        eventChannel.setStreamHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        methodChannel.setMethodCallHandler(null);
        eventChannel.setStreamHandler(null);
    }

    // ==================== EventChannel.StreamHandler ====================

    @Override
    public void onListen(Object args, EventChannel.EventSink sink) {
        eventSink = sink;
        RWFitCallbackManager.getInstance().setSink(sink);
    }

    @Override
    public void onCancel(Object args) {
        eventSink = null;
        RWFitCallbackManager.getInstance().setSink(null);
    }

    // ==================== ActivityAware ====================

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        activity = null;
    }

    @Override
    public void onDetachedFromActivity() {
        activity = null;
    }

    // ==================== 方法分发 ====================

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result raw) {
        // 所有 result 回调必须在主线程；SDK 回调多在子线程，统一包一层
        final Reply result = new Reply(raw, main);
        try {
            switch (call.method) {
                case "initSDK": initSDK(result); break;
                case "getSDKVersion": {
                    Map<String, Object> r = success();
                    r.put("version", DHBleSdk.INSTANCE.getSDKVersion());
                    result.success(r);
                    break;
                }
                case "getPluginVersion": {
                    Map<String, Object> r = success();
                    r.put("pluginVersion", PLUGIN_VERSION + "_" + DHBleSdk.INSTANCE.getSDKVersion());
                    result.success(r);
                    break;
                }
                case "isBleConnected": {
                    Map<String, Object> r = success();
                    r.put("connected", DHBleSdk.INSTANCE.isBleConnected());
                    result.success(r);
                    break;
                }
                case "startScan": {
                    Boolean filter = call.argument("filter");
                    ScanBleService.getService().startScan(filter != null ? filter : true, null);
                    result.success(success());
                    break;
                }
                case "stopScan":
                    ScanBleService.getService().stopScan();
                    result.success(success());
                    break;
                case "connectDevice":
                case "reconnectDevice":
                    connectDevice(call);
                    result.success(success());
                    break;
                case "disconnect":
                    DHBleSdk.INSTANCE.disconnect();
                    result.success(success());
                    break;
                case "iOSSetBindedStatus": // Android 无副作用
                    result.success(success());
                    break;
                case "getPower": getPower(result); break;
                case "getFirmwareVersion": getFirmwareVersion(result); break;
                case "controlHealthData": controlHealthData(call, result); break;
                case "controlFindDevice": controlFindDevice(result); break;
                case "controlTakePhoto": controlTakePhoto(call, result); break;
                case "setPowerOff": {
                    Integer type = call.argument("type");
                    DHBleSdk.INSTANCE.setPowerOffJL(type != null ? type : 1);
                    result.success(success());
                    break;
                }
                case "syncAllHealthData":
                    DHBleSdk.INSTANCE.syncAllHealthData(cb());
                    result.success(success());
                    break;
                case "removeHealthDataCallback":
                    DHBleSdk.INSTANCE.removeHealthDataCallBack(cb());
                    result.success(success());
                    break;
                case "ringOta": ringOta(call, result); break;
                case "unbind": unbind(result); break;
                // iOS 专用，Android no-op
                case "setNotificationSwitch":
                    result.success(success());
                    break;
                case "getNotificationSwitch": {
                    Map<String, Object> r = success();
                    r.put("switches", new HashMap<>());
                    result.success(r);
                    break;
                }
                // ---- 设备信息 ----
                case "setUserInfo": setUserInfo(call, result); break;
                case "setTimeFormat": setTimeFormat(call, result); break;
                case "getFunctionList": getFunctionList(result); break;
                case "setRingBtName": setRingBtName(call, result); break;
                // ---- 全天检测 ----
                case "getTimedHeartRate": getTimed(result, "hr"); break;
                case "setTimedHeartRate": setTimed(call, result, "hr"); break;
                case "getTimedBloodOxygen": getTimed(result, "bo"); break;
                case "setTimedBloodOxygen": setTimed(call, result, "bo"); break;
                case "getTimedHRV": getTimed(result, "hrv"); break;
                case "setTimedHRV": setTimed(call, result, "hrv"); break;
                case "getTimedStress": getTimed(result, "stress"); break;
                case "setTimedStress": setTimed(call, result, "stress"); break;
                case "getTimedBloodSugar": getTimed(result, "sugar"); break;
                case "setTimedBloodSugar": setTimed(call, result, "sugar"); break;
                case "getTimedBloodPressure": getTimed(result, "bp"); break;
                case "setTimedBloodPressure": setTimed(call, result, "bp"); break;
                // ---- 闹钟 ----
                case "getAlarm": getAlarm(result); break;
                case "setAlarm": setAlarm(call, result); break;
                case "deleteAllAlarm": deleteAllAlarm(result); break;
                // ---- 屏幕 ----
                case "getRaiseBrightScreen": getRaiseBrightScreen(result); break;
                case "setRaiseBrightScreen": setRaiseBrightScreen(call, result); break;
                case "getBrightScreenTime": getBrightScreenTime(result); break;
                case "setBrightScreenTime": setBrightScreenTime(call, result); break;
                case "getBrightScreenSleepTime": getBrightScreenSleepTime(result); break;
                case "setBrightScreenSleepTime": setBrightScreenSleepTime(call, result); break;
                case "getRingLedLevel": getRingLedLevel(result); break;
                case "setRingLedLevel": setRingLedLevel(call, result); break;
                // ---- 视频 HID / HID 配对 ----
                case "getVideoHid": getVideoHid(result); break;
                case "setVideoHid": setVideoHid(call, result); break;
                case "createOrRemoveBond": {
                    Integer type = call.argument("type");
                    String mac = call.argument("mac");
                    boolean ok = BlueToothUtils.INSTANCE.createOrRemoveBond(type != null ? type : 0, mac);
                    Map<String, Object> r = success();
                    r.put("result", ok);
                    result.success(r);
                    break;
                }
                // ---- 佩戴方向 ----
                case "getRingWearDir": getRingWearDir(result); break;
                case "setRingWearHand": setRingWearHand(call, result); break;
                // ---- 振动 ----
                case "getVibrationCount": getVibrationCount(result); break;
                case "setVibrationCount": setVibrationCount(call, result); break;
                case "getAlarmVibrationDuration": getAlarmVibrationDuration(result); break;
                case "setAlarmVibrationDuration": setAlarmVibrationDuration(call, result); break;
                // ---- 消息推送（Android 专用）----
                case "pushMessage": pushMessage(call, result); break;
                default:
                    result.notImplemented();
            }
        } catch (Exception e) {
            Log.e(TAG, "onMethodCall " + call.method + " error", e);
            result.error(-1, e.getMessage());
        }
    }

    // ==================== 方法实现（移植自 RWFitBleModule.java）====================

    private void initSDK(Reply result) {
        if (activity == null) {
            result.error(-1, "no activity context");
            return;
        }
        DHBleSdk.INSTANCE.initSDK(activity);
        DHBleSdk.INSTANCE.setConnectBleCallback(cb());
        ScanBleService.getService().initBle(activity);
        ScanBleService.getService().registerScanBleCallback(cb());
        result.success(success());
    }

    private void connectDevice(MethodCall call) {
        BleDevice device = new BleDevice();
        device.setBleName((String) call.argument("name"));
        device.setBleMac((String) call.argument("mac"));
        Integer rssi = call.argument("rssi");
        device.setBleRssi(rssi != null ? rssi : 0);
        DHBleSdk.INSTANCE.setConnectBleCallback(cb());
        DHBleSdk.INSTANCE.connectDeviceWithModel(device);
    }

    private void getPower(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new PowerCallback() {
            @Override public void onSuccess() {}
            @Override public void onFail(int errorCode) {
                result.error(errorCode, "getPower failed");
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onResult(PowerBean data) {
                if (data != null) {
                    Map<String, Object> r = success();
                    r.put("power", data.getPower());
                    result.success(r);
                    DHBleSdk.INSTANCE.dispose(this);
                }
            }
        });
        DHBleSdk.INSTANCE.getPowerJL();
    }

    private void getFirmwareVersion(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new FirmwareCallback() {
            @Override public void onSuccess() {}
            @Override public void onFail(int errorCode) {
                result.error(errorCode, "getFirmwareVersion failed");
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onResult(FirmVersionBean data) {
                if (data != null) {
                    Map<String, Object> r = success();
                    r.put("deviceClazz", data.getDeviceClazz() != null ? data.getDeviceClazz() : "");
                    r.put("deviceNo", data.getDeviceNo() != null ? data.getDeviceNo() : "");
                    r.put("uiVersion", data.getUiVersion() != null ? data.getUiVersion() : "");
                    result.success(r);
                    DHBleSdk.INSTANCE.dispose(this);
                }
            }
        });
        DHBleSdk.INSTANCE.getFirmwareVersionJL();
    }

    private void controlHealthData(MethodCall call, final Reply result) {
        String keyName = call.argument("key");
        Integer stateArg = call.argument("state");
        int state = stateArg != null ? stateArg : 0;

        byte key;
        switch (keyName != null ? keyName : "") {
            case "JL_HR_DATA_TRANSFER_KEY": key = CmdConstants.JL_HR_DATA_TRANSFER_KEY; break;
            case "JL_BO_DATA_TRANSFER_KEY": key = CmdConstants.JL_BO_DATA_TRANSFER_KEY; break;
            case "JL_HRV_DATA_TRANSFER_KEY": key = CmdConstants.JL_HRV_DATA_TRANSFER_KEY; break;
            case "JL_PRESSURE_DATA_TRANSFER_KEY": key = CmdConstants.JL_PRESSURE_DATA_TRANSFER_KEY; break;
            case "JL_BLOODSUGAR_DATA_TRANSFER_KEY": key = CmdConstants.JL_BLOODSUGAR_DATA_TRANSFER_KEY; break;
            case "JL_BP_DATA_TRANSFER_KEY": key = CmdConstants.JL_BP_DATA_TRANSFER_KEY; break;
            default:
                result.error(-1, "unknown key: " + keyName);
                return;
        }

        if (realtimeDataCallback != null) {
            DHBleSdk.INSTANCE.dispose(realtimeDataCallback);
            realtimeDataCallback = null;
        }

        // state=1 开启时才订阅实时数据回调；state=0 停止时只 dispose、不再重新订阅
        if (state == 1) {
            realtimeDataCallback = new HealthDataBroCallback() {
                @Override public void onResult(HealthDataSyncBean data) {
                    if (data == null) return;
                    JSONObject eventData = buildRealtimeDataPayload(data);
                    if (eventData != null) fireEvent("rwfit:healthData", eventData);
                }
                @Override public void onFail(int errorCode) {}
                @Override public void onSuccess() {}
            };
            DHBleSdk.INSTANCE.subscribeData(realtimeDataCallback);
        }

        DHBleSdk.INSTANCE.subscribeData(new HealthDataControlCallback() {
            @Override public void onSuccess() {
                result.success(success());
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onResult(Integer data) {}
            @Override public void onFail(int errorCode) {
                result.error(errorCode, "controlHealthData failed");
                DHBleSdk.INSTANCE.dispose(this);
            }
        });

        DHBleSdk.INSTANCE.controlHealthDataJL(key, (byte) state);
    }

    private void controlFindDevice(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new FindDeviceControlCallback() {
            @Override public void onSuccess() { result.success(success()); }
            @Override public void onFail(int errorCode) { result.error(errorCode, "controlFindDevice failed"); }
            @Override public void onResult(Integer data) {}
        });
        DHBleSdk.INSTANCE.controlFindDeviceJL();
    }

    private void controlTakePhoto(MethodCall call, Reply result) {
        Integer stateArg = call.argument("state");
        int state = stateArg != null ? stateArg : 0;
        if (takePhotoEventCallback == null) {
            takePhotoEventCallback = new TakePhotoCallback() {
                @Override public void onSuccess() {}
                @Override public void onFail(int errorCode) {}
                @Override public void onResult(Integer data) {
                    JSONObject eventData = new JSONObject();
                    eventData.put("keyType", 0);
                    eventData.put("touchType", 0);
                    eventData.put("action", "cameraTakePicture");
                    fireEvent("rwfit:touchEvent", eventData);
                }
            };
            DHBleSdk.INSTANCE.subscribeData(takePhotoEventCallback);
        }
        DHBleSdk.INSTANCE.controlTakePhotoJL(state);
        result.success(success());
    }

    private void ringOta(MethodCall call, final Reply result) {
        String otaPath = call.argument("path");
        DHBleSdk.INSTANCE.ringOtaWithFileData(otaPath, new OnFileTransferCallback() {
            @Override public void onProgress(float pro) {
                // 归一化到 0–1（iOS 端 SDK 回调已是 0–1；Android SDK 若返 0–100 则除 100）
                float normalized = pro > 1.0f ? pro / 100.0f : pro;
                fireEvent("rwfit:otaProgress", "progress", normalized);
            }
            @Override public void onFinish() {
                fireEvent("rwfit:otaFinish", null, 0);
                result.success(success());
            }
            @Override public void onFail(int code) {
                fireEvent("rwfit:otaFinish", "code", code);
                result.error(code, "OTA failed");
            }
        });
    }

    private void unbind(final Reply result) {
        DHBleSdk.INSTANCE.unbindJL();
        DHBleSdk.INSTANCE.subscribeStatus(new CommonStatusCallback() {
            @Override public void onSuccess(int msgId) {
                result.success(success());
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onFail(int msgId, int errorCode) {
                result.error(errorCode, "unbind failed");
                DHBleSdk.INSTANCE.dispose(this);
            }
        });
    }

    // ==================== 设备信息 ====================

    private void setUserInfo(MethodCall call, final Reply result) {
        PersonBean person = new PersonBean();
        person.setGender(i(call, "gender"));
        // Android SDK 接收 cm/kg 浮点值，与 Dart 层传入一致。
        // 注意：iOS 端 ×10 转 NSInteger（iOS SDK 用整数、保 0.1 精度）——
        // 两端桥接层内部各自做单位适配，对 Dart 暴露的都是 cm/kg 浮点。
        person.setHeight(f(call, "height"));
        person.setWeight(f(call, "weight"));
        person.setAge(i(call, "age"));
        person.setMeasureUnit(0); // 固定公制
        statusReply(result, "setUserInfo failed");
        DHBleSdk.INSTANCE.setUserInfo(person);
    }

    private void setTimeFormat(MethodCall call, final Reply result) {
        statusReply(result, "setTimeFormat failed");
        DHBleSdk.INSTANCE.ringSetTimeformat(i(call, "format"));
    }

    private void setRingBtName(MethodCall call, final Reply result) {
        BtNameBean bean = new BtNameBean();
        bean.setBtName(s(call, "name"));
        DHBleSdk.INSTANCE.setRingBtName(bean);
        statusReply(result, "setRingBtName failed");
    }

    private void getFunctionList(final Reply result) {
        DHBleSdk.INSTANCE.getFunctionListV2JL();
        DHBleSdk.INSTANCE.subscribeData(new SupportCallback() {
            @Override public void onSuccess() {}
            @Override public void onFail(int errorCode) { result.error(errorCode, "getFunctionList failed"); }
            @Override public void onResult(SupportMenuBean bean) {
                Map<String, Object> r = success();
                r.put("supportMenu", supportMenuMap(bean));
                result.success(r);
                DHBleSdk.INSTANCE.dispose(this);
            }
        });
    }

    private Map<String, Object> supportMenuMap(SupportMenuBean bean) {
        Map<String, Object> menu = new HashMap<>();
        menu.put("isStep", bean.isStep());
        menu.put("isSleep", bean.isSleep());
        menu.put("isHr", bean.isHr());
        menu.put("isBloodOxy", bean.isBloodOxy());
        menu.put("isBloodPress", bean.isBloodPress());
        menu.put("isBloodSugar", bean.isBloodSugar());
        menu.put("isHrv", bean.isHrv());
        menu.put("isPressure", bean.isPressure());
        menu.put("isBodyTemp", bean.isBodyTemp());
        menu.put("isAlarm", bean.isAlarm());
        menu.put("isBrightScreenTime", bean.isBrightScreenTime());
        menu.put("isBrightScreenSleepTime", bean.isBrightScreenSleepTime());
        menu.put("isPushMsgEnableSwitch", bean.isPushMsgEnableSwitch());
        menu.put("isFindDevice", bean.isFindDevice());
        menu.put("isTakePhoto", bean.isTakePhoto());
        menu.put("isSupportMotoVibrationLevel", bean.isSupportMotoVibrationLevel());
        menu.put("isSupportAlarmVibrationDuration", bean.isSupportAlarmVibrationDuration());
        menu.put("isMuslimCountData", bean.isMuslimCountData());
        menu.put("isSupportMuslimTimeDisplayMode", bean.isSupportMuslimTimeDisplayMode());
        return menu;
    }

    // ==================== 全天检测（6 项共用 DrinkReminderBean）====================

    private DrinkReminderBean timedBean(MethodCall call) {
        DrinkReminderBean bean = new DrinkReminderBean();
        bean.setOpen(b(call, "isOpen"));
        bean.setRemindDuration(i(call, "duration"));
        bean.setStartHour(i(call, "startHour"));
        bean.setStartMin(i(call, "startMin"));
        bean.setEndHour(i(call, "endHour"));
        bean.setEndMin(i(call, "endMin"));
        return bean;
    }

    private void timedReply(Reply result, DrinkReminderBean d) {
        if (d == null) return;
        Map<String, Object> r = success();
        r.put("isOpen", d.isOpen());
        r.put("duration", d.getRemindDuration());
        r.put("startHour", d.getStartHour());
        r.put("startMin", d.getStartMin());
        r.put("endHour", d.getEndHour());
        r.put("endMin", d.getEndMin());
        result.success(r);
    }

    private void getTimed(final Reply result, String type) {
        switch (type) {
            case "hr":
                DHBleSdk.INSTANCE.subscribeData(new TimedHeartRateCallback() {
                    @Override public void onResult(DrinkReminderBean d) { timedReply(result, d); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onFail(int e) { result.error(e, "getTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() {}
                });
                DHBleSdk.INSTANCE.getTimedHeartRateJL();
                break;
            case "bo":
                DHBleSdk.INSTANCE.subscribeData(new TimedBloodOxygenCallback() {
                    @Override public void onResult(DrinkReminderBean d) { timedReply(result, d); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onFail(int e) { result.error(e, "getTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() {}
                });
                DHBleSdk.INSTANCE.getTimedBloodOxygenJL();
                break;
            case "hrv":
                DHBleSdk.INSTANCE.subscribeData(new TimedHrvCallback() {
                    @Override public void onResult(DrinkReminderBean d) { timedReply(result, d); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onFail(int e) { result.error(e, "getTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() {}
                });
                DHBleSdk.INSTANCE.getTimedHRVJL();
                break;
            case "stress":
                DHBleSdk.INSTANCE.subscribeData(new TimedStressCallback() {
                    @Override public void onResult(DrinkReminderBean d) { timedReply(result, d); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onFail(int e) { result.error(e, "getTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() {}
                });
                DHBleSdk.INSTANCE.getTimedStressJL();
                break;
            case "sugar":
                DHBleSdk.INSTANCE.subscribeData(new TimedBloodSugarCallback() {
                    @Override public void onResult(DrinkReminderBean d) { timedReply(result, d); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onFail(int e) { result.error(e, "getTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() {}
                });
                DHBleSdk.INSTANCE.getTimedBloodSugarJL();
                break;
            case "bp":
                DHBleSdk.INSTANCE.subscribeData(new TimedBloodPressureCallback() {
                    @Override public void onResult(DrinkReminderBean d) { timedReply(result, d); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onFail(int e) { result.error(e, "getTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() {}
                });
                DHBleSdk.INSTANCE.getTimedBloodPressureJL();
                break;
        }
    }

    private void setTimed(MethodCall call, final Reply result, String type) {
        DrinkReminderBean bean = timedBean(call);
        switch (type) {
            case "hr":
                DHBleSdk.INSTANCE.subscribeData(new TimedHeartRateCallback() {
                    @Override public void onResult(DrinkReminderBean d) {}
                    @Override public void onFail(int e) { result.error(e, "setTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
                });
                DHBleSdk.INSTANCE.setTimedHeartRateJL(bean);
                break;
            case "bo":
                DHBleSdk.INSTANCE.subscribeData(new TimedBloodOxygenCallback() {
                    @Override public void onResult(DrinkReminderBean d) {}
                    @Override public void onFail(int e) { result.error(e, "setTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
                });
                DHBleSdk.INSTANCE.setTimedBloodOxygenJL(bean);
                break;
            case "hrv":
                DHBleSdk.INSTANCE.subscribeData(new TimedHrvCallback() {
                    @Override public void onResult(DrinkReminderBean d) {}
                    @Override public void onFail(int e) { result.error(e, "setTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
                });
                DHBleSdk.INSTANCE.setTimedHRVJL(bean);
                break;
            case "stress":
                DHBleSdk.INSTANCE.subscribeData(new TimedStressCallback() {
                    @Override public void onResult(DrinkReminderBean d) {}
                    @Override public void onFail(int e) { result.error(e, "setTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
                });
                DHBleSdk.INSTANCE.setTimedStressJL(bean);
                break;
            case "sugar":
                DHBleSdk.INSTANCE.subscribeData(new TimedBloodSugarCallback() {
                    @Override public void onResult(DrinkReminderBean d) {}
                    @Override public void onFail(int e) { result.error(e, "setTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
                });
                DHBleSdk.INSTANCE.setTimedBloodSugarJL(bean);
                break;
            case "bp":
                DHBleSdk.INSTANCE.subscribeData(new TimedBloodPressureCallback() {
                    @Override public void onResult(DrinkReminderBean d) {}
                    @Override public void onFail(int e) { result.error(e, "setTimed failed"); DHBleSdk.INSTANCE.dispose(this); }
                    @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
                });
                DHBleSdk.INSTANCE.setTimedBloodPressureJL(bean);
                break;
        }
    }

    // ==================== 闹钟 ====================

    private void getAlarm(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new AlarmCallback() {
            @Override public void onResult(List<AlarmRemainderBean> data) {
                JSONArray arr = new JSONArray();
                if (data != null) {
                    for (AlarmRemainderBean bean : data) {
                        if (bean == null) continue;
                        JSONObject item = new JSONObject();
                        item.put("alarmId", bean.getAlarmId());
                        item.put("startHour", bean.getStartHour());
                        item.put("startMin", bean.getStartMin());
                        item.put("isOpen", bean.isOpen());
                        item.put("alarmTag", bean.getAlarmTag());
                        int[] repeatModel = bean.getRepeatModel();
                        JSONArray repeats = new JSONArray();
                        if (repeatModel != null) for (int v : repeatModel) repeats.add(v);
                        item.put("repeats", repeats);
                        arr.add(item);
                    }
                }
                Map<String, Object> r = success();
                r.put("data", toCodecSafe(arr));
                result.success(r);
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onFail(int errorCode) { result.error(errorCode, "getAlarm failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() {}
        });
        DHBleSdk.INSTANCE.getAlarmRemindJL();
    }

    private void setAlarm(MethodCall call, final Reply result) {
        List<Map<String, Object>> alarms = call.argument("alarms");
        ArrayList<AlarmRemainderBean> params = new ArrayList<>();
        if (alarms != null) {
            for (Map<String, Object> item : alarms) {
                AlarmRemainderBean bean = new AlarmRemainderBean();
                bean.setAlarmId(asInt(item.get("alarmId")));
                bean.setStartHour(asInt(item.get("startHour")));
                bean.setStartMin(asInt(item.get("startMin")));
                bean.setOpen(Boolean.TRUE.equals(item.get("isOpen")));
                Object tag = item.get("alarmTag");
                bean.setAlarmTag(tag instanceof String ? (String) tag : "");
                int[] repeatModel = new int[7];
                Object rep = item.get("repeats");
                if (rep instanceof List) {
                    List<?> rl = (List<?>) rep;
                    for (int r = 0; r < Math.min(7, rl.size()); r++) repeatModel[r] = asInt(rl.get(r));
                }
                bean.setRepeatModel(repeatModel);
                params.add(bean);
            }
        }
        DHBleSdk.INSTANCE.subscribeData(new AlarmCallback() {
            @Override public void onResult(List<AlarmRemainderBean> data) {}
            @Override public void onFail(int errorCode) { result.error(errorCode, "setAlarm failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.setAlarmRemindJL(params);
    }

    private void deleteAllAlarm(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new AlarmCallback() {
            @Override public void onResult(List<AlarmRemainderBean> data) {}
            @Override public void onFail(int errorCode) { result.error(errorCode, "deleteAllAlarm failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.deleteAllAlarmRemindJL();
    }

    // ==================== 屏幕 ====================

    private void getRaiseBrightScreen(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new BrightCallback() {
            @Override public void onResult(BrightScreenBean d) {
                if (d == null) return;
                Map<String, Object> r = success();
                r.put("isOpen", d.isOpen());
                r.put("startHour", d.getStartHour());
                r.put("startMin", d.getStartMin());
                r.put("endHour", d.getEndHour());
                r.put("endMin", d.getEndMin());
                result.success(r);
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onFail(int e) { result.error(e, "getRaiseBrightScreen failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() {}
        });
        DHBleSdk.INSTANCE.getRaiseBrightScreenJL();
    }

    private void setRaiseBrightScreen(MethodCall call, final Reply result) {
        BrightScreenBean bean = new BrightScreenBean();
        bean.setOpen(b(call, "isOpen"));
        bean.setStartHour(i(call, "startHour"));
        bean.setStartMin(i(call, "startMin"));
        bean.setEndHour(i(call, "endHour"));
        bean.setEndMin(i(call, "endMin"));
        DHBleSdk.INSTANCE.subscribeData(new BrightCallback() {
            @Override public void onResult(BrightScreenBean d) {}
            @Override public void onFail(int e) { result.error(e, "setRaiseBrightScreen failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.setRaiseBrightScreenJL(bean);
    }

    private void getBrightScreenTime(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new BrightTimeCallback() {
            @Override public void onResult(BrightScreenTimeBean d) {
                if (d == null) return;
                Map<String, Object> r = success();
                r.put("timeSecond", d.getTimeSecond());
                result.success(r);
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onFail(int e) {}
            @Override public void onSuccess() {}
        });
        DHBleSdk.INSTANCE.getBrightScreenTimeJL();
    }

    private void setBrightScreenTime(MethodCall call, final Reply result) {
        BrightScreenTimeBean bean = new BrightScreenTimeBean();
        bean.setTimeSecond(i(call, "timeSecond"));
        DHBleSdk.INSTANCE.subscribeData(new BrightTimeCallback() {
            @Override public void onResult(BrightScreenTimeBean d) {}
            @Override public void onFail(int e) { result.error(e, "setBrightScreenTime failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.setBrightScreenTimeJL(bean);
    }

    private void getBrightScreenSleepTime(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new BrightTimeCallback() {
            @Override public void onResult(BrightScreenTimeBean d) {
                if (d == null) return;
                Map<String, Object> r = success();
                r.put("isOpen", d.isOpen());
                r.put("startHour", d.getStartHour());
                r.put("startMin", d.getStartMin());
                r.put("endHour", d.getEndHour());
                r.put("endMin", d.getEndMin());
                result.success(r);
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onFail(int e) {}
            @Override public void onSuccess() {}
        });
        DHBleSdk.INSTANCE.getRingBrightScreenSleepTime();
    }

    private void setBrightScreenSleepTime(MethodCall call, final Reply result) {
        BrightScreenTimeBean bean = new BrightScreenTimeBean();
        bean.setOpen(b(call, "isOpen"));
        bean.setStartHour(i(call, "startHour"));
        bean.setStartMin(i(call, "startMin"));
        bean.setEndHour(i(call, "endHour"));
        bean.setEndMin(i(call, "endMin"));
        DHBleSdk.INSTANCE.subscribeData(new BrightTimeCallback() {
            @Override public void onResult(BrightScreenTimeBean d) {}
            @Override public void onFail(int e) { result.error(e, "setBrightScreenSleepTime failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.setRingBrightScreenSleepTime(bean);
    }

    private void getRingLedLevel(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new BrightLedLevelCallback() {
            @Override public void onResult(BrightScreenLedBean d) {
                if (d == null) return;
                Map<String, Object> r = success();
                r.put("isOpen", d.isOpen());
                r.put("lcdLevel", d.getLcdLevel());
                result.success(r);
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onFail(int e) {}
            @Override public void onSuccess() {}
        });
        DHBleSdk.INSTANCE.getRingLedLevel();
    }

    private void setRingLedLevel(MethodCall call, final Reply result) {
        BrightScreenLedBean bean = new BrightScreenLedBean();
        bean.setOpen(b(call, "isOpen"));
        bean.setLcdLevel(i(call, "lcdLevel"));
        DHBleSdk.INSTANCE.subscribeData(new BrightLedLevelCallback() {
            @Override public void onResult(BrightScreenLedBean d) {}
            @Override public void onFail(int e) { result.error(e, "setRingLedLevel failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.setRingLedLevel(bean);
    }

    // ==================== 视频 HID ====================

    private void getVideoHid(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new VideoHidCallback() {
            @Override public void onResult(VideoHidBean d) {
                if (d == null) return;
                Map<String, Object> r = success();
                r.put("hidOpen", d.getHidOpen());
                result.success(r);
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onFail(int e) {}
            @Override public void onSuccess() {}
        });
        DHBleSdk.INSTANCE.getVideoHidJL();
    }

    private void setVideoHid(MethodCall call, final Reply result) {
        VideoHidBean bean = new VideoHidBean();
        bean.setHidOpen(i(call, "hidOpen"));
        DHBleSdk.INSTANCE.subscribeData(new VideoHidCallback() {
            @Override public void onResult(VideoHidBean d) {}
            @Override public void onFail(int e) { result.error(e, "setVideoHid failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.setVideoHidJL(bean);
    }

    // ==================== 佩戴方向 ====================

    private void getRingWearDir(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new WearHandCallback() {
            @Override public void onSuccess() {}
            @Override public void onResult(FactoryInBean d) {
                if (d != null) {
                    Map<String, Object> r = success();
                    r.put("isRight", d.isOpen() == 1);
                    result.success(r);
                }
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onFail(int e) { result.error(e, "getRingWearDir failed"); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.getRingWearDir();
    }

    private void setRingWearHand(MethodCall call, final Reply result) {
        boolean isRight = b(call, "isRight");
        DHBleSdk.INSTANCE.subscribeData(new WearHandCallback() {
            @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onResult(FactoryInBean d) {}
            @Override public void onFail(int e) { result.error(e, "setRingWearHand failed"); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.setRingWearHand(isRight);
    }

    // ==================== 振动 ====================

    private void getVibrationCount(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new VibrationCountCallback() {
            @Override public void onSuccess() {}
            @Override public void onResult(BrightVibrationBean d) {
                if (d != null) {
                    Map<String, Object> r = success();
                    r.put("count", d.getCount());
                    r.put("level", d.getLevel());
                    result.success(r);
                }
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onFail(int e) { result.error(e, "getVibrationCount failed"); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.getVibrationCount();
    }

    private void setVibrationCount(MethodCall call, final Reply result) {
        int level = i(call, "level");
        int count = i(call, "count");
        DHBleSdk.INSTANCE.subscribeData(new VibrationCountCallback() {
            @Override public void onResult(BrightVibrationBean d) {}
            @Override public void onFail(int e) { result.error(e, "setVibrationCount failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.setVibrationCount(level, count);
    }

    private void getAlarmVibrationDuration(final Reply result) {
        DHBleSdk.INSTANCE.subscribeData(new AlarmVibrationDurationCallback() {
            @Override public void onResult(Integer data) {
                Map<String, Object> r = success();
                r.put("duration", data);
                result.success(r);
                DHBleSdk.INSTANCE.dispose(this);
            }
            @Override public void onFail(int e) { result.error(e, "getAlarmVibrationDuration failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() {}
        });
        DHBleSdk.INSTANCE.getAlarmVibrationDuration();
    }

    private void setAlarmVibrationDuration(MethodCall call, final Reply result) {
        int duration = i(call, "duration");
        DHBleSdk.INSTANCE.subscribeData(new AlarmVibrationDurationCallback() {
            @Override public void onResult(Integer data) {}
            @Override public void onFail(int e) { result.error(e, "setAlarmVibrationDuration failed"); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onSuccess() { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
        });
        DHBleSdk.INSTANCE.setAlarmVibrationDuration(duration);
    }

    // ==================== 消息推送（Android 专用）====================

    private void pushMessage(MethodCall call, final Reply result) {
        MsgPushBean bean = new MsgPushBean();
        bean.setAppId(s(call, "appId"));
        bean.setTitle(s(call, "title"));
        bean.setContent(s(call, "content"));
        if (call.argument("msgType") != null) bean.setMsgType(i(call, "msgType"));
        if (call.argument("timeMill") != null) bean.setTimeMill(l(call, "timeMill"));
        DHBleSdk.INSTANCE.subscribeData(new MsgPushSettingCallback() {
            @Override public void onResult(Integer data) {}
            @Override public void onFail(int e) { result.error(e, "pushMessage failed"); }
            @Override public void onSuccess() { result.success(success()); }
        });
        DHBleSdk.INSTANCE.setPushMsgJL(bean);
    }

    /** 用 CommonStatusCallback 统一回执的 set 类。 */
    private void statusReply(final Reply result, final String failMsg) {
        DHBleSdk.INSTANCE.subscribeStatus(new CommonStatusCallback() {
            @Override public void onSuccess(int msgId) { result.success(success()); DHBleSdk.INSTANCE.dispose(this); }
            @Override public void onFail(int msgId, int errorCode) { result.error(errorCode, failMsg); DHBleSdk.INSTANCE.dispose(this); }
        });
    }

    // ==================== 音乐控制（Android 专用，连接就绪后自动启用）====================

    void enableMusicControl() {
        if (musicControlEventCallback != null) {
            DHBleSdk.INSTANCE.dispose(musicControlEventCallback);
            musicControlEventCallback = null;
        }
        musicControlEventCallback = new MusicPushSettingCallback() {
            @Override public void onSuccess() {}
            @Override public void onFail(int errorCode) {}
            @Override public void onResult(Integer data) {
                if (data == null) return;
                String action;
                switch (data) {
                    case 1: action = "musicPlay"; break;
                    case 2: action = "musicPause"; break;
                    case 3: action = "musicPrev"; break;
                    case 4: action = "musicNext"; break;
                    case 5: action = "musicVolumeUp"; break;
                    case 6: action = "musicVolumeDown"; break;
                    default: return;
                }
                dispatchMusicControl(data);
                JSONObject eventData = new JSONObject();
                eventData.put("keyType", 0);
                eventData.put("touchType", 0);
                eventData.put("action", action);
                fireEvent("rwfit:touchEvent", eventData);
            }
        };
        DHBleSdk.INSTANCE.subscribeData(musicControlEventCallback);
    }

    private void dispatchMusicControl(int code) {
        Context ctx = activity != null ? activity.getApplicationContext() : null;
        if (ctx == null) return;
        AudioManager am = (AudioManager) ctx.getSystemService(Context.AUDIO_SERVICE);
        if (am == null) return;
        switch (code) {
            case 1: sendMediaKey(am, KeyEvent.KEYCODE_MEDIA_PLAY); break;
            case 2: sendMediaKey(am, KeyEvent.KEYCODE_MEDIA_PAUSE); break;
            // 设备端 prev/next 与系统媒体键语义相反，此处交换：3=next, 4=prev
            case 3: sendMediaKey(am, KeyEvent.KEYCODE_MEDIA_NEXT); break;
            case 4: sendMediaKey(am, KeyEvent.KEYCODE_MEDIA_PREVIOUS); break;
            case 5: am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI); break;
            case 6: am.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI); break;
            default: break;
        }
    }

    private void sendMediaKey(AudioManager am, int keyCode) {
        am.dispatchMediaKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, keyCode));
        am.dispatchMediaKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, keyCode));
    }

    private JSONObject buildRealtimeDataPayload(HealthDataSyncBean data) {
        int dataType = data.getDataType();
        JSONObject event = new JSONObject();
        event.put("dataType", dataType);
        switch (dataType) {
            case 1:
            case 13: {
                List<HrPartData> list = data.getHrPartData();
                if (list == null || list.isEmpty()) return null;
                HrPartData last = list.get(list.size() - 1);
                event.put("dataValue", last.getHr());
                event.put("time", last.getTime());
                return event;
            }
            case 3: {
                List<BoPartData> list = data.getBoPartData();
                if (list == null || list.isEmpty()) return null;
                BoPartData last = list.get(list.size() - 1);
                event.put("dataValue", last.getBo());
                event.put("time", last.getTime());
                return event;
            }
            case 4: {
                List<BpPartData> list = data.getBpPartData();
                if (list == null || list.isEmpty()) return null;
                BpPartData last = list.get(list.size() - 1);
                event.put("dataValue", last.getSp());
                event.put("diastolic", last.getDp());
                event.put("time", last.getTime());
                return event;
            }
            case 8: {
                List<PressurePartData> list = data.getPressurePartData();
                if (list == null || list.isEmpty()) return null;
                PressurePartData last = list.get(list.size() - 1);
                event.put("dataValue", last.getPressure());
                event.put("time", last.getTime());
                return event;
            }
            case 9: {
                // 血糖实时数据：RW SDK 复用 TempPartData 容器（getTemp() 返回血糖原始值）。
                // 与 iOS 端 BLE_KEY_APP_REAL_BLOOD_SUGAR_DATA → dataType=9 对齐。
                List<TempPartData> list = data.getTempPartData();
                if (list == null || list.isEmpty()) return null;
                TempPartData last = list.get(list.size() - 1);
                event.put("dataValue", last.getTemp());
                event.put("time", last.getTime());
                return event;
            }
            default:
                return null;
        }
    }

    // ==================== 事件转发 ====================

    void fireEvent(String eventName, JSONObject rawData) {
        JSONObject data = rawData != null ? rawData : new JSONObject();
        data.put("event", eventName);
        final Object safe = toCodecSafe(data);
        main.post(() -> {
            if (eventSink != null) eventSink.success(safe);
        });
    }

    /** OTA 旧代码 key/value 形式：key==null → 空对象（成功 {}）。 */
    void fireEvent(String eventName, String key, Object value) {
        JSONObject o = new JSONObject();
        if (key != null) o.put(key, value);
        fireEvent(eventName, o);
    }

    // ==================== 工具 ====================

    private Map<String, Object> success() {
        Map<String, Object> m = new HashMap<>();
        m.put("code", 0);
        m.put("msg", "success");
        return m;
    }

    // 入参安全提取（MethodCall.argument 缺省返回 null）
    private int i(MethodCall c, String k) { Integer v = c.argument(k); return v != null ? v : 0; }
    private long l(MethodCall c, String k) { Object v = c.argument(k); return v instanceof Number ? ((Number) v).longValue() : 0L; }
    private float f(MethodCall c, String k) { Object v = c.argument(k); return v instanceof Number ? ((Number) v).floatValue() : 0f; }
    private boolean b(MethodCall c, String k) { Boolean v = c.argument(k); return v != null && v; }
    private String s(MethodCall c, String k) { Object v = c.argument(k); return v instanceof String ? (String) v : ""; }
    private static int asInt(Object v) { return v instanceof Number ? ((Number) v).intValue() : 0; }

    /** JSONObject/JSONArray → StandardMessageCodec 可序列化的 Map/List（递归）。 */
    static Object toCodecSafe(Object v) {
        if (v instanceof JSONObject) {
            Map<String, Object> m = new HashMap<>();
            for (String k : ((JSONObject) v).keySet()) {
                m.put(k, toCodecSafe(((JSONObject) v).get(k)));
            }
            return m;
        } else if (v instanceof JSONArray) {
            List<Object> l = new ArrayList<>();
            for (Object e : (JSONArray) v) l.add(toCodecSafe(e));
            return l;
        }
        return v;
    }

    /** MethodChannel 结果必须在主线程回、且只回一次。 */
    private static final class Reply {
        private final Result result;
        private final Handler main;
        private boolean done;

        Reply(Result result, Handler main) {
            this.result = result;
            this.main = main;
        }

        void success(final Object data) {
            if (done) return;
            done = true;
            main.post(() -> result.success(data));
        }

        /**
         * 失败也走 success 回一个 {code!=0, msg} Map —— 与 Dart callAsync 的
         * "读 result['code']、非 0 抛 RwfitException" 契约一致（不要用 result.error，
         * 否则 Dart 侧拿到的是 PlatformException 而非 RwfitException）。
         */
        void error(final int code, final String msg) {
            if (done) return;
            done = true;
            final Map<String, Object> m = new HashMap<>();
            m.put("code", code);
            m.put("msg", msg);
            main.post(() -> result.success(m));
        }

        void notImplemented() {
            if (done) return;
            done = true;
            main.post(result::notImplemented);
        }
    }
}
