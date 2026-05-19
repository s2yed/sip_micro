import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'sip_provider.dart';
import 'sip_settings_provider.dart';
import 'setup_screen.dart';

class CallScreen extends ConsumerWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sip = ref.watch(sipProvider);

    if (sip.isVideoEnabled && sip.status == CallStatus.active) {
      return _VideoCallView(sip: sip);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: sip.status == CallStatus.idle || sip.status == CallStatus.failed
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white54),
                  tooltip: 'تغيير الإعدادات',
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const SetupScreen()),
                    );
                  },
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: switch (sip.status) {
          CallStatus.incoming => _IncomingCallView(sip: sip),
          _ => _OutgoingCallView(sip: sip),
        },
      ),
    );
  }
}

// ── شاشة المكالمة المرئية ────────────────────────────────────────
class _VideoCallView extends ConsumerWidget {
  final SipState sip;
  const _VideoCallView({required this.sip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sipProvider.notifier);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (sip.remoteRenderer != null)
            Positioned.fill(
              child: RTCVideoView(sip.remoteRenderer!, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            )
          else
            const Center(child: Icon(Icons.videocam_off, color: Colors.white38, size: 80)),

          if (sip.localRenderer != null)
            Positioned(
              top: 50,
              right: 16,
              width: 100,
              height: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(sip.localRenderer!, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),

          Positioned(
            top: 50,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    sip.callerNumber ?? 'مكالمة فيديو',
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: sip.isMuted ? Icons.mic_off : Icons.mic,
                  label: sip.isMuted ? 'صوت' : 'كتم',
                  active: sip.isMuted,
                  onTap: notifier.toggleMute,
                ),
                _RoundButton(
                  icon: Icons.call_end,
                  color: Colors.red,
                  size: 70,
                  onTap: notifier.hangUp,
                ),
                _ActionButton(
                  icon: sip.isSpeaker ? Icons.volume_up : Icons.hearing,
                  label: sip.isSpeaker ? 'سماعة' : 'أذن',
                  active: sip.isSpeaker,
                  onTap: notifier.toggleSpeaker,
                ),
              ],
            ),
          ),

          if (sip.hasIncomingCallWaiting)
            _CallWaitingOverlay(sip: sip),

          if (sip.hasHeldCall)
            _HeldCallControls(sip: sip),
        ],
      ),
    );
  }
}

// ── شاشة المكالمة الواردة ────────────────────────────────────────
class _IncomingCallView extends ConsumerWidget {
  final SipState sip;
  const _IncomingCallView({required this.sip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sipProvider.notifier);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        const SizedBox(height: 20),
        const Text(
          'مكالمة واردة',
          style: TextStyle(color: Colors.white54, fontSize: 16),
        ),
        _Avatar(label: sip.callerNumber ?? 'مجهول'),
        Text(
          sip.callerNumber ?? 'مجهول',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const _PulsingRing(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RoundButton(
              icon: Icons.call_end,
              color: Colors.red,
              label: 'رفض',
              onTap: notifier.rejectCall,
            ),
            _AnswerButton(
              number: sip.callerNumber ?? 'مجهول',
              onTap: notifier.answerCall,
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ── شاشة المكالمة الصادرة / النشطة ──────────────────────────────
class _OutgoingCallView extends ConsumerWidget {
  final SipState sip;
  const _OutgoingCallView({required this.sip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sipProvider.notifier);
    final settings = ref.watch(sipSettingsProvider).valueOrNull;
    final isActive = sip.status == CallStatus.active;
    final isConnecting =
        sip.status == CallStatus.connecting || sip.status == CallStatus.ringing;

    final String displayName = (sip.callerNumber != null && sip.callerNumber!.isNotEmpty)
        ? sip.callerNumber!
        : (settings != null && settings.callTarget.isNotEmpty)
            ? settings.callTarget
            : 'الدعم الفني';

    return Stack(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(height: 20),
            Text(
              _statusLabel(sip.status, sip.registrationStatus),
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
            if (settings != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _InfoChip(label: 'رقمي', value: settings.myExtension),
                    _InfoChip(label: 'أتصل بـ', value: settings.callTarget),
                  ],
                ),
              ),

            _Avatar(
              label: isActive || isConnecting ? displayName : '',
              icon: Icons.support_agent,
            ),

            Column(
              children: [
                if (isActive || isConnecting) ...[
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (isActive) const _CallTimer(),
                ],
                if (sip.error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      sip.error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),

            if (isActive)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ActionButton(
                    icon: sip.isMuted ? Icons.mic_off : Icons.mic,
                    label: sip.isMuted ? 'صوت' : 'كتم',
                    active: sip.isMuted,
                    onTap: notifier.toggleMute,
                  ),
                  const SizedBox(width: 40),
                  _ActionButton(
                    icon: sip.isSpeaker ? Icons.volume_up : Icons.hearing,
                    label: sip.isSpeaker ? 'سماعة' : 'أذن',
                    active: sip.isSpeaker,
                    onTap: notifier.toggleSpeaker,
                  ),
                ],
              ),

            if (isConnecting)
              Column(
                children: [
                  const SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      color: Colors.greenAccent,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _RoundButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    size: 70,
                    label: 'إلغاء',
                    onTap: notifier.hangUp,
                  ),
                ],
              )
            else if (isActive)
              _RoundButton(
                icon: Icons.call_end,
                color: Colors.red,
                size: 80,
                onTap: notifier.hangUp,
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundButton(
                    icon: Icons.call,
                    color: Colors.green,
                    size: 70,
                    label: 'صوت',
                    onTap: notifier.startCall,
                  ),
                  const SizedBox(width: 32),
                  _RoundButton(
                    icon: Icons.videocam,
                    color: Colors.blueAccent,
                    size: 70,
                    label: 'فيديو',
                    onTap: () => notifier.startCall(withVideo: true),
                  ),
                ],
              ),

            const SizedBox(height: 20),
          ],
        ),
        if (sip.hasIncomingCallWaiting)
          _CallWaitingOverlay(sip: sip),

        if (sip.hasHeldCall)
          _HeldCallControls(sip: sip),
      ],
    );
  }

  String _statusLabel(CallStatus s, SipRegistrationStatus reg) => switch (s) {
        CallStatus.idle when reg == SipRegistrationStatus.registering =>
          'جارٍ الاتصال بالخادم...',
        CallStatus.idle when reg == SipRegistrationStatus.failed ||
            reg == SipRegistrationStatus.unregistered =>
          'انقطع الاتصال بالخادم',
        CallStatus.idle when reg == SipRegistrationStatus.none =>
          'جارٍ تحميل الإعدادات...',
        CallStatus.idle => 'اضغط للاتصال بالدعم الفني',
        CallStatus.connecting => 'جاري الاتصال...',
        CallStatus.ringing => 'رنين...',
        CallStatus.active => 'متصل',
        CallStatus.failed => 'فشل — حاول مجدداً',
        CallStatus.incoming => '',
      };
}

// ── ويدجت الأفاتار ───────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Avatar({required this.label, this.icon = Icons.person});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF1A3A5C), Color(0xFF0D2137)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Icon(icon, size: 55, color: Colors.white70),
    );
  }
}

// ── حلقة نابضة ──────────────────────────────────────────────────
class _PulsingRing extends StatefulWidget {
  const _PulsingRing();

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Opacity(
        opacity: _anim.value,
        child: const Text(
          '● ● ●',
          style: TextStyle(color: Colors.greenAccent, fontSize: 22, letterSpacing: 8),
        ),
      ),
    );
  }
}

// ── زر دائري ────────────────────────────────────────────────────
class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? label;
  final double size;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.label,
    this.size = 70,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
          if (label != null) ...[
            const SizedBox(height: 8),
            Text(label!, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}

// ── زر الإجراء (ميك / سماعة) ────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.white : Colors.white12,
            ),
            child: Icon(icon, color: active ? Colors.black : Colors.white, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── مؤقت وقت المكالمة ───────────────────────────────────────────
class _CallTimer extends StatefulWidget {
  const _CallTimer();

  @override
  State<_CallTimer> createState() => _CallTimerState();
}

// ── زر القبول مع رقم المتصل ─────────────────────────────────────
class _AnswerButton extends StatelessWidget {
  final String number;
  final VoidCallback onTap;
  const _AnswerButton({required this.number, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green,
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.call, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 8),
          Text(
            number,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A5C),
        borderRadius: BorderRadius.circular(20),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: '$label  ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            TextSpan(text: value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _CallTimerState extends State<_CallTimer> {
  late final Timer _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _seconds++),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return Text(
      '$m:$s',
      style: const TextStyle(color: Colors.white54, fontSize: 18),
    );
  }
}

class _CallWaitingOverlay extends ConsumerWidget {
  final SipState sip;
  const _CallWaitingOverlay({required this.sip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sipProvider.notifier);
    return Positioned(
      top: 50,
      left: 16,
      right: 16,
      child: Card(
        color: const Color(0xEE1E293B), // Ultra premium dark blue card
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blueAccent.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.15),
                blurRadius: 20,
                spreadRadius: 2,
              )
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.amber,
                ),
                child: const Icon(Icons.phone_paused, color: Colors.black, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'مكالمة واردة أخرى...',
                      style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sip.callerNumberWaiting ?? 'مجهول',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              // Decline button
              IconButton(
                icon: const Icon(Icons.call_end, color: Colors.redAccent, size: 28),
                onPressed: notifier.rejectWaitingCall,
                tooltip: 'رفض',
              ),
              const SizedBox(width: 8),
              // Answer & Hold button
              IconButton(
                icon: const Icon(Icons.phone, color: Colors.greenAccent, size: 28),
                onPressed: notifier.acceptWaitingCall,
                tooltip: 'وضع الانتظار والرد',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeldCallControls extends ConsumerWidget {
  final SipState sip;
  const _HeldCallControls({required this.sip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sipProvider.notifier);
    return Positioned(
      bottom: 140, // Perfectly floats right above the main action buttons
      left: 20,
      right: 20,
      child: Card(
        color: const Color(0xE81A2238), // Deep blue glassmorphic card
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.pause_circle_filled, color: Colors.orangeAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'المكالمة الأخرى (${sip.callerNumberHeld ?? 'مجهول'}) بالانتظار',
                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Swap button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.swap_calls, size: 18),
                    label: const Text('تبديل المكالمة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: notifier.swapCalls,
                  ),
                  // Conference/Merge button
                  if (!sip.isConferenceActive)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      icon: const Icon(Icons.call_merge, size: 18),
                      label: const Text('مكالمة جماعية', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: notifier.mergeIntoConference,
                    )
                  else
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      icon: const Icon(Icons.call_split, size: 18),
                      label: const Text('فصل الجماعي', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: notifier.splitConference,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
