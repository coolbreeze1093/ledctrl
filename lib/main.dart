// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'utils.dart';
import 'dart:convert';
import 'UdpSocketManager.dart';
import 'dart:async';
import 'DeviceInfoDialog.dart';
import 'GetNetworkInfo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '灯控',
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: Colors.blueGrey.shade800,
          secondary: Colors.cyanAccent,
          surface: Colors.grey.shade800,
          error: Colors.redAccent,
          onPrimary: Colors.white,
          onSecondary: Colors.black,
          onSurface: Colors.white,
          onError: Colors.black,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: '又是美好的一天'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  //UiState _uiState = UiState(0.0, BrightnessModel.soft);

  NetworkInfoMan getNetworkInfo = NetworkInfoMan();

  int _timeCount = 0;

  Map<String, String>? _remoteDeviceList;

  UdpSocketManager udpSocketManager = UdpSocketManager();

  Timer? _debounceTimer;

  late DeviceInfoDialog deviceInfoDialog;

  DeviceInfo _curUser = DeviceInfo();

  // 模式的名称
  final Map<BrightnessModel, String> _showText = {
    BrightnessModel.soft: '柔光',
    BrightnessModel.sleep: '睡眠',
    BrightnessModel.read: '阅读',
    BrightnessModel.colorful: '炫彩'
  };

  final List<BrightnessModel> _showSeq = [
    BrightnessModel.read,
    BrightnessModel.sleep,
    BrightnessModel.colorful,
    BrightnessModel.soft
  ];
  @override
  void initState() {
    super.initState();
    _curUser.address = "127.0.0.1";
    _curUser.name = "empty";
    _curUser.deviceList = [];

    udpSocketManager.initializeSocket();
    udpSocketManager.brightnessCallback(setUiState);
    getCurrentUser();
    deviceInfoDialog = DeviceInfoDialog(
        networkInfo: getNetworkInfo, udpSocketManager: udpSocketManager);
  }

  void getCurrentUser() async {
    String? ip = await getData(config_Key_CurrentUser);
    if (ip != null) {
      _curUser.address = ip;
    }
    List<dynamic>? deviceList = await getListData(config_Key_CurrentLightInfo);
    if (deviceList != null) {
      _curUser.deviceList = List<String>.from(deviceList);
    }

    for (String value in _curUser.deviceList) {
      _curUser.lightinfo[value] = UiState(0, BrightnessModel.none);
    }

    getNetworkInfo.getNetworkInfo((String ip, String mac) {
      udpSocketManager.queryBrightness(_curUser.address, ip);
    });
  }

  @override
  void dispose() {
    super.dispose();
    _debounceTimer?.cancel();
    udpSocketManager.close();
  }

  void setUiState(Map<String, int> us) {
    setState(() {
      us.forEach((String key, int value) {
        _curUser.lightinfo[key]
            ?.setBrightness(mapValue(value.ceilToDouble(), 0, 1024, 0, 100));
      });
    });
  }

  void _incrementCounter(double value) {
    setState(() {
      logger.d("cur brightness $value");
      _curUser.lightinfo[_curUser.selectedLight]?.setBrightness(value);
    });

    // 如果已有计时器在运行，则取消它
    if (_debounceTimer?.isActive ?? false) {
      _timeCount++;
      _debounceTimer?.cancel();
    }

    if (_timeCount >= 10) {
      _timeCount = 0;
      _sendCtrlMessage(_curUser.address, sendPort);
      return;
    }

    // 设置一个新的定时器，仅在延迟完成后发送消息
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      _sendCtrlMessage(_curUser.address, sendPort);
    });
  }

  void _sendCtrlMessage(String ip, int port) {
    Map<String, int> brightnessMap = {};
    _curUser.lightinfo.forEach((String key, UiState value) {
      brightnessMap[key] = mapValue(value.brightness, 0, 100, 0, 1024).round();
    });

    Map<String, dynamic> sendData = {
      key_type: send_type_lightInfo,
      value_brightness: brightnessMap,
    };
    logger.d("sendData $sendData");
    udpSocketManager.sendMessage(jsonEncode(sendData), ip, port);
  }

  Color _getModelColor(int index) {
    if (_curUser.lightinfo.isNotEmpty) {
      if (_curUser.lightinfo[_curUser.selectedLight]?.model ==
          BrightnessModel.none) {
        return Colors.blueGrey.shade600;
      } else {
        return _curUser.lightinfo[_curUser.selectedLight]?.model ==
                _showSeq[index]
            ? Colors.cyanAccent.shade700
            : Colors.blueGrey.shade600;
      }
    } else {
      return Colors.blueGrey.shade600;
    }
  }

  void _modelOnTap(int index) {
    setState(() {
      if (_curUser.lightinfo.isNotEmpty) {
        _curUser.lightinfo[_curUser.selectedLight]
            ?.setBrightModel(_showSeq[index]);
      }
    });
    if (_curUser.lightinfo.isNotEmpty) {
      switch (_curUser.lightinfo[_curUser.selectedLight]?.model) {
        case BrightnessModel.read:
          _incrementCounter(3);
          break;
        case BrightnessModel.colorful:
          _incrementCounter(80);
          break;
        case BrightnessModel.sleep:
          _incrementCounter(0);
          break;
        case BrightnessModel.soft:
          _incrementCounter(30);
          break;
        case null:
        // TODO: Handle this case.
        case BrightnessModel.none:
        // TODO: Handle this case.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 35, 52, 52),
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.build), // 使用扳手图标
            onPressed: () async {
              DeviceInfo? selectUser = await showDialog<DeviceInfo?>(
                context: context,
                builder: (BuildContext context) {
                  return deviceInfoDialog;
                },
              );
              if (selectUser != null || selectUser?.address != "empty") {
                setState(() {
                  _curUser = selectUser!;
                  for (var element in _curUser.deviceList) {
                    _curUser.lightinfo[element] = UiState(0, BrightnessModel.none);
                  }
                  _curUser.selectedLight=_curUser.deviceList.first;
                });
                saveData(config_Key_CurrentUser, _curUser.address);
                saveListData(config_Key_CurrentLightInfo, _curUser.deviceList);
              }
            }, // 点击后调用的方法
            tooltip: '设置', // 鼠标悬停时显示的提示
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 60, height: 380),
                SizedBox(
                  height: 380,
                  child: Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.wb_sunny), // 表示亮度增强
                        color: const Color.fromARGB(255, 162, 153, 77),
                        iconSize: 30,
                        onPressed: () {
                          _incrementCounter(100);
                        },
                      ),
                      SizedBox(
                        height: 280,
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 65, // 设置轨道高度
                              trackShape: const RoundedRectSliderTrackShape(),
                              activeTrackColor: Colors.cyanAccent.shade400,
                              inactiveTrackColor: Colors.blueGrey.shade700,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 25), // 设置滑块大小
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 30), // 设置滑块外圈大小
                            ),
                            child: Slider(
                              value: _curUser.lightinfo.isEmpty
                                  ? 0
                                  : _curUser.lightinfo.keys.contains(_curUser.selectedLight)?_curUser.lightinfo[_curUser.selectedLight]!.brightness:0
                                      ,
                              onChanged: (double value) {
                                _incrementCounter(value);
                              },
                              onChangeEnd: (double value) {},
                              min: 0,
                              max: 100,
                              divisions: 100,
                              label: _curUser.lightinfo.isEmpty
                                  ? "0"
                                  : _curUser.lightinfo.keys.contains(_curUser.selectedLight)?_curUser.lightinfo[_curUser.selectedLight]!
                                      .brightness
                                      .round()
                                      .toString():"0",
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.nightlight_round), // 表示亮度减弱
                        color: Colors.blueGrey,
                        iconSize: 30,
                        onPressed: () {
                          _incrementCounter(0);
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 60,
                  height: 380,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(25), // 设置整体圆角
                      child: Container(
                        width: 50, // 设置宽度，确保内容不超出
                        height: 280, // 设置高度
                        color: Colors.transparent,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_curUser.deviceList.length,
                              (index) {
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _curUser.selectedLight =
                                      _curUser.deviceList[index];
                                });
                              },
                              child: Container(
                                width: 50, // 设置宽度
                                height: 50, // 设置高度
                                alignment: Alignment.center, // 使文字居中
                                color: _curUser.selectedLight ==
                                        _curUser.deviceList[index]
                                    ? Colors.cyanAccent.shade700
                                    : Colors.blueGrey.shade600,
                                child: Text(
                                  _curUser.deviceList[index],
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 18),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 100),
            ClipRRect(
              borderRadius: BorderRadius.circular(25), // 设置整体圆角
              child: Container(
                width: 320, // 设置宽度，确保内容不超出
                height: 50, // 设置高度
                color: Colors.transparent,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_showSeq.length, (index) {
                    return GestureDetector(
                      onTap: () {
                        _modelOnTap(index);
                      },
                      child: Container(
                        width: 80, // 设置宽度
                        height: 50, // 设置高度
                        alignment: Alignment.center, // 使文字居中
                        color: _getModelColor(index),
                        child: Text(
                          _showText[_showSeq[index]]!,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
