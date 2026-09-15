import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform_bridge.dart';

enum VoiceState {
  checking,
  missingModel,
  downloading,
  loading,
  ready,
  listening,
  thinking,
  error,
}

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final bridge = PlatformBridge();
  Timer? clock;
  final textController = TextEditingController();
  VoiceState state = VoiceState.checking;
  DateTime now = DateTime.now();
  int downloadPercent = 0;
  String heard = '';
  String answer = '';
  String detail = '로컬 AI를 확인하고 있어요';

  @override
  void initState() {
    super.initState();
    bridge.setEventHandler(onNativeEvent);
    refreshModelStatus();
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    textController.dispose();
    super.dispose();
  }

  void onNativeEvent(String method, Map<String, dynamic> data) {
    if (!mounted) return;
    if (method == 'modelProgress') {
      setState(() {
        state = VoiceState.downloading;
        downloadPercent = data['percent'] as int? ?? 0;
        detail = 'AI 모델 설치 중 · $downloadPercent%';
      });
      return;
    }
    if (method == 'modelState') {
      final nativeState = data['state'] as String?;
      setState(() {
        detail = data['message'] as String? ?? detail;
        state = switch (nativeState) {
          'loading' => VoiceState.loading,
          'ready' => VoiceState.ready,
          'error' => VoiceState.error,
          _ => state,
        };
      });
    }
  }

  Future<void> refreshModelStatus() async {
    final status = await bridge.modelStatus();
    if (!mounted) return;
    setState(() {
      if (status['unsupported'] == true) {
        state = VoiceState.error;
        detail = 'Android 기기에서 실행해 주세요';
      } else if (status['loaded'] == true) {
        state = VoiceState.ready;
        detail = '폰 안의 AI가 준비됐어요';
      } else if (status['installed'] == true) {
        state = VoiceState.loading;
        detail = 'AI 모델을 메모리에 올리고 있어요';
      } else if (status['downloading'] == true) {
        state = VoiceState.downloading;
        detail = 'AI 모델을 설치하고 있어요';
      } else {
        state = VoiceState.missingModel;
        detail = '처음 한 번 AI 모델 설치가 필요해요';
      }
    });
  }

  Future<void> installModel() async {
    setState(() {
      state = VoiceState.downloading;
      detail = '다운로드를 시작하고 있어요';
    });
    try {
      await bridge.installModel();
    } on PlatformException catch (error) {
      showError(error.message ?? '모델 설치를 시작하지 못했습니다.');
    }
  }

  Future<void> talk() async {
    if (state != VoiceState.ready) return;
    setState(() {
      state = VoiceState.listening;
      heard = '';
      answer = '';
      detail = '듣고 있어요…';
    });
    try {
      final transcript = await bridge.recognizeKorean();
      if (transcript == null || transcript.trim().isEmpty) {
        setState(() {
          state = VoiceState.ready;
          detail = '버튼을 누르고 말씀해 주세요';
        });
        return;
      }
      setState(() {
        heard = transcript.trim();
        textController.text = heard;
        textController.selection = TextSelection.collapsed(offset: textController.text.length);
        state = VoiceState.ready;
        detail = '내용을 확인하고 보내기를 눌러 주세요';
      });
    } on PlatformException catch (error) {
      if (error.code == 'cancelled') {
        setState(() {
          state = VoiceState.ready;
          detail = '버튼을 누르고 말씀해 주세요';
        });
      } else {
        showError(error.message ?? '음성 요청을 처리하지 못했습니다.');
      }
    }
  }

  Future<void> sendText() async {
    final prompt = textController.text.trim();
    if (prompt.isEmpty || state != VoiceState.ready) return;
    setState(() {
      heard = prompt;
      answer = '';
      state = VoiceState.thinking;
      detail = '폰 안에서 답을 생각하고 있어요…';
    });
    try {
      final response = await bridge.askLocal(prompt);
      if (!mounted) return;
      setState(() {
        answer = response;
        state = VoiceState.ready;
        detail = '다시 질문해 주세요';
      });
    } on PlatformException catch (error) {
      showError(error.message ?? '텍스트 요청을 처리하지 못했습니다.');
    }
  }

  void showError(String message) {
    if (!mounted) return;
    setState(() {
      state = VoiceState.error;
      detail = message;
    });
  }

  String get dateLabel {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final period = now.hour < 12 ? '오전' : '오후';
    return '${now.year}. ${now.month}. ${now.day}. ${weekdays[now.weekday - 1]}요일  $period $hour:${now.minute.toString().padLeft(2, '0')}';
  }

  void showHaruInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF6F8F5),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('하루', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.phone_android_rounded, color: Color(0xFF176B45)),
                title: Text('온디바이스 · 오프라인'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.history_toggle_off_rounded, color: Color(0xFF176B45)),
                title: Text('대화 14회 · 자동 정리'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.edit_note_rounded, color: Color(0xFF176B45)),
                title: Text('음성 수정 · 텍스트 보내기'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = state == VoiceState.listening || state == VoiceState.thinking;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: showHaruInfo,
                    child: Image.asset(
                      'assets/brand/haru-primary-transparent.png',
                      width: 58,
                      height: 42,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('하루', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const Spacer(),
                  const Icon(Icons.lock_outline_rounded, size: 17),
                  const SizedBox(width: 5),
                  const Text(
                    '오프라인',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(dateLabel, style: TextStyle(color: Colors.grey.shade600)),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (state == VoiceState.missingModel) ...[
                          Image.asset('assets/brand/haru-primary-transparent.png', width: 230, height: 148, fit: BoxFit.contain),
                          const SizedBox(height: 24),
                          Text(
                            '로컬 AI 설치',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '처음 한 번만 모델을 내려받아요.\n설치 후에는 인터넷이 필요 없습니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              height: 1.55,
                            ),
                          ),
                          const SizedBox(height: 28),
                          FilledButton.icon(
                            onPressed: installModel,
                            icon: const Icon(Icons.download_rounded),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 13),
                              child: Text('모델 설치하기'),
                            ),
                          ),
                        ] else if (state == VoiceState.downloading) ...[
                          SizedBox(
                            width: 112,
                            height: 112,
                            child: CircularProgressIndicator(
                              value: downloadPercent == 0
                                  ? null
                                  : downloadPercent / 100,
                              strokeWidth: 9,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '$downloadPercent%',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                        ] else if (state == VoiceState.loading ||
                            state == VoiceState.checking) ...[
                          const SizedBox(
                            width: 76,
                            height: 76,
                            child: CircularProgressIndicator(strokeWidth: 8),
                          ),
                        ] else ...[
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              if (busy) ...[
                                _RippleRing(size: 250),
                                _RippleRing(size: 220),
                              ],
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                width: busy ? 230 : 200,
                                height: busy ? 230 : 200,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFBDECCF),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: busy ? const Color(0xFF55B98B) : Colors.transparent,
                                    width: busy ? 8 : 0,
                                  ),
                                ),
                                child: GestureDetector(
                                  onTap: state == VoiceState.error
                                      ? refreshModelStatus
                                      : busy
                                      ? null
                                      : talk,
                                  child: Center(
                                    child: _AnimatedOtter(
                                      width: busy ? 214 : 188,
                                      height: busy ? 138 : 121,
                                      active: busy,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const SizedBox(height: 20),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 430),
                            child: TextField(
                              controller: textController,
                              enabled: !busy,
                              minLines: 1,
                              maxLines: 3,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => sendText(),
                              decoration: InputDecoration(
                                hintText: '음성 내용을 고치거나 직접 입력하세요',
                                filled: true,
                                fillColor: const Color(0xFFF6F8F5),
                                suffixIcon: IconButton(
                                  onPressed: busy ? null : sendText,
                                  icon: const Icon(Icons.send_rounded),
                                  color: const Color(0xFF176B45),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          if (heard.isNotEmpty) ...[
                            const SizedBox(height: 34),
                            Text(
                              '“$heard”',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (answer.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Text(
                              answer,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Text(detail, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _RippleRing extends StatefulWidget {
  const _RippleRing({required this.size});
  final double size;

  @override
  State<_RippleRing> createState() => _RippleRingState();
}

class _AnimatedOtter extends StatefulWidget {
  const _AnimatedOtter({required this.width, required this.height, required this.active});
  final double width;
  final double height;
  final bool active;

  @override
  State<_AnimatedOtter> createState() => _AnimatedOtterState();
}

class _AnimatedOtterState extends State<_AnimatedOtter>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  )..repeat(reverse: true);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (_, child) => Transform.scale(
          scale: widget.active
              ? 0.98 + controller.value * .06
              : 0.98 + controller.value * .025,
          child: child,
        ),
        child: Image.asset(
          'assets/brand/haru-primary-transparent.png',
          width: widget.width,
          height: widget.height,
          fit: BoxFit.contain,
        ),
      );
}

class _RippleRingState extends State<_RippleRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (_, __) => Container(
          width: widget.size + controller.value * 18,
          height: widget.size + controller.value * 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0x6655B98B).withValues(alpha: 1 - controller.value * .8),
              width: 4,
            ),
          ),
        ),
      );
}

class _OtterMark extends StatelessWidget {
  const _OtterMark({required this.size, required this.showWaves});

  final double size;
  final bool showWaves;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size + (showWaves ? size * .42 : 0), size),
        painter: _OtterPainter(showWaves: showWaves),
      );
}

class _OtterPainter extends CustomPainter {
  const _OtterPainter({required this.showWaves});
  final bool showWaves;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height;
    final cx = s * .43;
    final center = Offset(cx, s * .5);
    final green = Paint()..color = const Color(0xFF176B45);
    final cream = Paint()..color = const Color(0xFFF6F8F5);
    final dark = Paint()..color = const Color(0xFF18201D);
    final mint = Paint()..color = const Color(0xFFBDECCF);
    canvas.drawCircle(center, s * .42, green);
    canvas.drawCircle(Offset(cx - s * .28, s * .18), s * .1, dark);
    canvas.drawCircle(Offset(cx + s * .28, s * .18), s * .1, dark);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, s * .56), width: s * .62, height: s * .53), cream);
    canvas.drawCircle(Offset(cx - s * .16, s * .45), s * .055, dark);
    canvas.drawCircle(Offset(cx + s * .16, s * .45), s * .055, dark);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, s * .56), width: s * .17, height: s * .1), dark);
    final mouth = Path()..moveTo(cx - s * .1, s * .62)..quadraticBezierTo(cx, s * .77, cx + s * .1, s * .62)..quadraticBezierTo(cx, s * .68, cx - s * .1, s * .62);
    canvas.drawPath(mouth, mint);
    final whisker = Paint()..color = const Color(0xFF18201D)..strokeWidth = s * .025..strokeCap = StrokeCap.round;
    for (final y in [.53, .61, .69]) {
      canvas.drawLine(Offset(cx - s * .2, s * y), Offset(cx - s * .46, s * (y - .06)), whisker);
      canvas.drawLine(Offset(cx + s * .2, s * y), Offset(cx + s * .46, s * (y - .06)), whisker);
    }
    if (showWaves) {
      final wave = Paint()..color = const Color(0xFF55B98B)..style = PaintingStyle.stroke..strokeWidth = s * .06..strokeCap = StrokeCap.round;
      for (var i = 0; i < 2; i++) {
        final p = Path()..moveTo(s * (.82 + i * .13), s * .35)..quadraticBezierTo(s * (.96 + i * .13), s * .5, s * (.82 + i * .13), s * .65);
        canvas.drawPath(p, wave);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OtterPainter oldDelegate) => oldDelegate.showWaves != showWaves;
}
