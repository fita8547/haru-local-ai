import 'package:flutter/services.dart';

typedef NativeEventHandler =
    void Function(String method, Map<String, dynamic> data);

class PlatformBridge {
  PlatformBridge();

  static const _channel = MethodChannel('app.haru/native');

  void setEventHandler(NativeEventHandler handler) {
    _channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      if (arguments is Map) {
        handler(call.method, Map<String, dynamic>.from(arguments));
      }
    });
  }

  Future<Map<String, dynamic>> modelStatus() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'modelStatus',
      );
      return value ?? const {'installed': false};
    } on MissingPluginException {
      return const {'installed': false, 'unsupported': true};
    }
  }

  Future<void> installModel() async {
    await _channel.invokeMethod<void>('installModel');
  }

  Future<String?> recognizeKorean() async {
    return _channel.invokeMethod<String>('recognizeKorean');
  }

  Future<String> askLocal(String prompt) async {
    final answer = await _channel.invokeMethod<String>('askLocal', {
      'prompt': prompt,
    });
    return answer ?? '';
  }
}
