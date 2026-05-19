import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sip_ua/sip_ua.dart';
import '../../core/config.dart';
import 'sip_settings_provider.dart';

enum CallStatus { idle, connecting, ringing, incoming, active, failed }

enum SipRegistrationStatus { none, registering, registered, unregistered, failed }

class SipState {
  final CallStatus status;
  final SipRegistrationStatus registrationStatus;
  final String? error;
  final bool isSpeaker;
  final bool isMuted;
  final bool isVideoEnabled;
  final String? callerNumber;
  final RTCVideoRenderer? localRenderer;
  final RTCVideoRenderer? remoteRenderer;

  // Call Waiting fields
  final bool hasIncomingCallWaiting;
  final String? callerNumberWaiting;
  final bool isVideoWaiting;

  // Held and Conference fields
  final bool hasHeldCall;
  final String? callerNumberHeld;
  final bool isConferenceActive;

  const SipState({
    this.status = CallStatus.idle,
    this.registrationStatus = SipRegistrationStatus.none,
    this.error,
    this.isSpeaker = false,
    this.isMuted = false,
    this.isVideoEnabled = false,
    this.callerNumber,
    this.localRenderer,
    this.remoteRenderer,
    this.hasIncomingCallWaiting = false,
    this.callerNumberWaiting,
    this.isVideoWaiting = false,
    this.hasHeldCall = false,
    this.callerNumberHeld,
    this.isConferenceActive = false,
  });

  bool get isRegistered => registrationStatus == SipRegistrationStatus.registered;

  SipState copyWith({
    CallStatus? status,
    SipRegistrationStatus? registrationStatus,
    String? error,
    bool? isSpeaker,
    bool? isMuted,
    bool? isVideoEnabled,
    String? callerNumber,
    RTCVideoRenderer? localRenderer,
    RTCVideoRenderer? remoteRenderer,
    bool? hasIncomingCallWaiting,
    String? callerNumberWaiting,
    bool? isVideoWaiting,
    bool? hasHeldCall,
    String? callerNumberHeld,
    bool? isConferenceActive,
  }) => SipState(
    status: status ?? this.status,
    registrationStatus: registrationStatus ?? this.registrationStatus,
    error: error,
    isSpeaker: isSpeaker ?? this.isSpeaker,
    isMuted: isMuted ?? this.isMuted,
    isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
    callerNumber: callerNumber ?? this.callerNumber,
    localRenderer: localRenderer ?? this.localRenderer,
    remoteRenderer: remoteRenderer ?? this.remoteRenderer,
    hasIncomingCallWaiting: hasIncomingCallWaiting ?? this.hasIncomingCallWaiting,
    callerNumberWaiting: callerNumberWaiting ?? this.callerNumberWaiting,
    isVideoWaiting: isVideoWaiting ?? this.isVideoWaiting,
    hasHeldCall: hasHeldCall ?? this.hasHeldCall,
    callerNumberHeld: callerNumberHeld ?? this.callerNumberHeld,
    isConferenceActive: isConferenceActive ?? this.isConferenceActive,
  );
}

class SipNotifier extends Notifier<SipState> implements SipUaHelperListener {
  late SIPUAHelper _helper;
  Call? _currentCall;
  Call? _heldCall;
  Call? _waitingCall;
  bool _registrationStarted = false;
  final _ringtone = FlutterRingtonePlayer();
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;

  @override
  SipState build() {
    _helper = SIPUAHelper();
    _helper.addSipUaHelperListener(this);
    _registrationStarted = false;

    final String mode = UcmConfig.clientMode;
    final bool isAnonymous = mode == 'anonymous';
    final bool isPool = mode == 'pool';
    if (isAnonymous || isPool) {
      _registrationStarted = true;
      // defer so build() returns before _helper.start() fires callbacks
      Future.microtask(_startRegistration);
      return const SipState(
          registrationStatus: SipRegistrationStatus.registering);
    }

    // settings are async — watch and start registration once they load
    ref.listen(sipSettingsProvider, (_, next) {
      next.whenData((settings) {
        if (settings.isConfigured && !_registrationStarted) {
          _registrationStarted = true;
          state = state.copyWith(
              registrationStatus: SipRegistrationStatus.registering);
          // defer so state is initialized before any SIP callbacks fire
          Future.microtask(_startRegistration);
        }
      });
    });

    // also handle the case where settings are already loaded synchronously
    final settings = ref.read(sipSettingsProvider).valueOrNull;
    if (settings != null && settings.isConfigured) {
      _registrationStarted = true;
      // defer so build() returns before _helper.start() fires callbacks
      Future.microtask(_startRegistration);
      return const SipState(
          registrationStatus: SipRegistrationStatus.registering);
    }
    return const SipState();
  }

  SipSettings get _settings {
    return ref.read(sipSettingsProvider).valueOrNull ??
        const SipSettings(myExtension: '', callTarget: '');
  }

  Future<void> _startRegistration() async {
    final settings = _settings;
    final String mode = UcmConfig.clientMode;
    final bool isAnonymous = mode == 'anonymous';
    final bool isPool = mode == 'pool';
    if (!settings.isConfigured && !isAnonymous && !isPool) return;

    final String myExt = (isAnonymous || isPool)
        ? UcmConfig.myExtension
        : settings.myExtension;

    final ua = UaSettings()
      ..transportType = TransportType.WS
      ..webSocketUrl = UcmConfig.wsUrl
      ..webSocketSettings = (WebSocketSettings()
        ..allowBadCertificate = true
        ..extraHeaders = {})
      ..uri = UcmConfig.sipUri(myExt)
      ..authorizationUser = isAnonymous ? null : myExt
      ..password = isAnonymous ? null : UcmConfig.sipPassword
      ..displayName = isAnonymous ? UcmConfig.anonymousDisplayName : myExt
      ..userAgent = 'SipClient/1.0'
      ..iceServers = [
        {
          'urls': 'turn:openrelay.metered.ca:80',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
        {
          'urls': 'turns:openrelay.metered.ca:443',
          'username': 'openrelayproject',
          'credential': 'openrelayproject',
        },
      ]
      ..iceTransportPolicy = IceTransportPolicy.ALL
      ..sessionTimers = false
      ..register = !isAnonymous;

    await _helper.start(ua);
  }

  Future<void> _initRenderers() async {
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    await _localRenderer!.initialize();
    await _remoteRenderer!.initialize();
  }

  void _disposeRenderers() {
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
    _localRenderer = null;
    _remoteRenderer = null;
  }

  Future<void> startCall({bool withVideo = false}) async {
    if (state.status != CallStatus.idle && state.status != CallStatus.failed) {
      return;
    }

    final bool isAnonymous = UcmConfig.clientMode == 'anonymous';

    if (!state.isRegistered && (!isAnonymous || !_helper.connected)) {
      final msg = state.registrationStatus == SipRegistrationStatus.failed
          ? 'فشل الاتصال بالخادم، تحقق من الشبكة'
          : 'جارٍ الاتصال بالخادم، يرجى الانتظار';
      state = state.copyWith(status: CallStatus.failed, error: msg);
      return;
    }

    final target = isAnonymous ? UcmConfig.defaultCallTarget : _settings.callTarget;
    if (target.isEmpty) {
      state = state.copyWith(
        status: CallStatus.failed,
        error: 'لم يتم إعداد رقم الاتصال',
      );
      return;
    }

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      state = state.copyWith(
        status: CallStatus.failed,
        error: 'يجب السماح بالوصول للمايكروفون',
      );
      return;
    }

    if (withVideo) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        state = state.copyWith(
          status: CallStatus.failed,
          error: 'يجب السماح بالوصول للكاميرا',
        );
        return;
      }
      await _initRenderers();
    }

    state = state.copyWith(
      status: CallStatus.connecting,
      isVideoEnabled: withVideo,
      localRenderer: _localRenderer,
      remoteRenderer: _remoteRenderer,
    );

    final result = await _helper.call(
      UcmConfig.callUri(target),
      voiceOnly: !withVideo,
    );
    if (result == false) {
      _disposeRenderers();
      state = state.copyWith(
        status: CallStatus.failed,
        error: 'فشل بدء المكالمة',
      );
    }
  }

  Future<void> answerCall() async {
    if (_currentCall == null || state.status != CallStatus.incoming) return;

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) return;

    final bool withVideo = _currentCall!.remote_has_video;
    if (withVideo) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) return;
      await _initRenderers();
    }

    _ringtone.stop();

    if (withVideo) {
      state = state.copyWith(
        isVideoEnabled: true,
        localRenderer: _localRenderer,
        remoteRenderer: _remoteRenderer,
      );
    }

    _currentCall!.answer({
      'mediaConstraints': {'audio': true, 'video': withVideo},
      'pcConfig': {
        'iceServers': [
          {
            'urls': 'turn:openrelay.metered.ca:80',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
          {
            'urls': 'turns:openrelay.metered.ca:443',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'iceTransportPolicy': 'all',
      },
    });
  }

  void rejectCall() {
    _ringtone.stop();
    _currentCall?.hangup();
    _currentCall = null;
    _disposeRenderers();
    state = SipState(registrationStatus: state.registrationStatus);
  }

  void toggleMute() {
    if (_currentCall == null) return;
    final next = !state.isMuted;
    next ? _currentCall!.mute() : _currentCall!.unmute();
    state = state.copyWith(isMuted: next);
  }

  void toggleSpeaker() {
    final next = !state.isSpeaker;
    Helper.setSpeakerphoneOn(next);
    state = state.copyWith(isSpeaker: next);
  }

  void hangUp() {
    _ringtone.stop();
    if (state.isConferenceActive) {
      _currentCall?.hangup();
      _heldCall?.hangup();
      _currentCall = null;
      _heldCall = null;
      _disposeRenderers();
      state = SipState(registrationStatus: state.registrationStatus);
      return;
    }

    _currentCall?.hangup();
    _currentCall = null;
    _disposeRenderers();

    // If we have a held call, resume it!
    if (_heldCall != null) {
      _currentCall = _heldCall;
      _heldCall = null;
      _currentCall!.unhold();
      state = SipState(
        status: CallStatus.active,
        registrationStatus: state.registrationStatus,
        callerNumber: _currentCall!.remote_identity,
        isVideoEnabled: _currentCall!.remote_has_video,
        hasHeldCall: false,
        callerNumberHeld: null,
        isConferenceActive: false,
      );
    } else {
      state = SipState(registrationStatus: state.registrationStatus);
    }
  }

  void rejectWaitingCall() {
    if (_waitingCall == null) return;
    _ringtone.stop();
    _waitingCall!.hangup({'status_code': 486, 'reason_phrase': 'Busy Here'});
    _waitingCall = null;
    state = state.copyWith(
      hasIncomingCallWaiting: false,
      callerNumberWaiting: null,
      isVideoWaiting: false,
    );
  }

  Future<void> acceptWaitingCall() async {
    if (_waitingCall == null || _currentCall == null) return;

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) return;

    final bool withVideo = _waitingCall!.remote_has_video;
    if (withVideo) {
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) return;
      await _initRenderers();
    }

    _ringtone.stop();

    // 1. Put current call on hold
    _currentCall!.hold();

    // 2. Swap calls
    _heldCall = _currentCall;
    _currentCall = _waitingCall;
    _waitingCall = null;

    // 3. Update state
    state = state.copyWith(
      status: CallStatus.active,
      callerNumber: _currentCall!.remote_identity,
      isVideoEnabled: withVideo,
      localRenderer: withVideo ? _localRenderer : null,
      remoteRenderer: withVideo ? _remoteRenderer : null,
      hasIncomingCallWaiting: false,
      callerNumberWaiting: null,
      isVideoWaiting: false,
      hasHeldCall: true,
      callerNumberHeld: _heldCall!.remote_identity,
      isConferenceActive: false,
    );

    // 4. Answer the new call
    _currentCall!.answer({
      'mediaConstraints': {'audio': true, 'video': withVideo},
      'pcConfig': {
        'iceServers': [
          {
            'urls': 'turn:openrelay.metered.ca:80',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
          {
            'urls': 'turns:openrelay.metered.ca:443',
            'username': 'openrelayproject',
            'credential': 'openrelayproject',
          },
        ],
        'iceTransportPolicy': 'all',
      },
    });
  }

  void swapCalls() {
    if (_currentCall == null || _heldCall == null) return;

    // 1. Put current active call on hold
    _currentCall!.hold();

    // 2. Unhold the held call
    _heldCall!.unhold();

    // 3. Swap the references
    final temp = _currentCall;
    _currentCall = _heldCall;
    _heldCall = temp;

    // 4. Update the state
    state = state.copyWith(
      callerNumber: _currentCall!.remote_identity,
      isVideoEnabled: _currentCall!.remote_has_video,
      localRenderer: _currentCall!.remote_has_video ? _localRenderer : null,
      remoteRenderer: _currentCall!.remote_has_video ? _remoteRenderer : null,
      hasHeldCall: true,
      callerNumberHeld: _heldCall!.remote_identity,
      isConferenceActive: false,
    );
  }

  void mergeIntoConference() {
    if (_currentCall == null || _heldCall == null) return;

    // Unhold both calls to active status
    _currentCall!.unhold();
    _heldCall!.unhold();

    state = state.copyWith(
      isConferenceActive: true,
      callerNumber: 'مكالمة جماعية (${_currentCall!.remote_identity} و ${_heldCall!.remote_identity})',
    );
  }

  void splitConference() {
    if (_currentCall == null || _heldCall == null) return;

    // Put held call back on hold
    _heldCall!.hold();

    state = state.copyWith(
      isConferenceActive: false,
      callerNumber: _currentCall!.remote_identity,
    );
  }

  // ─── SipUaHelperListener ────────────────────────────────────────

  @override
  void registrationStateChanged(RegistrationState s) {
    switch (s.state) {
      case RegistrationStateEnum.REGISTERED:
        _safeSetState((st) =>
            st.copyWith(registrationStatus: SipRegistrationStatus.registered));
      case RegistrationStateEnum.UNREGISTERED:
        _safeSetState((st) =>
            st.copyWith(registrationStatus: SipRegistrationStatus.unregistered));
      case RegistrationStateEnum.REGISTRATION_FAILED:
        _safeSetState((st) =>
            st.copyWith(registrationStatus: SipRegistrationStatus.failed));
      default:
        break;
    }
  }

  @override
  void callStateChanged(Call call, CallState callState) {
    // If a call ends/fails, check if it's the waiting call
    if (_waitingCall != null && _waitingCall!.id == call.id) {
      if (callState.state == CallStateEnum.ENDED || callState.state == CallStateEnum.FAILED) {
        _waitingCall = null;
        state = state.copyWith(
          hasIncomingCallWaiting: false,
          callerNumberWaiting: null,
          isVideoWaiting: false,
        );
      }
      return;
    }

    // If a call ends/fails, check if it's the held call
    if (_heldCall != null && _heldCall!.id == call.id) {
      if (callState.state == CallStateEnum.ENDED || callState.state == CallStateEnum.FAILED) {
        _heldCall = null;
        state = state.copyWith(
          hasHeldCall: false,
          callerNumberHeld: null,
          isConferenceActive: false,
        );
      }
      return;
    }

    // If it's a completely new call, and we already have an active call, treat it as a waiting call
    if (_currentCall != null && _currentCall!.id != call.id) {
      if (callState.state == CallStateEnum.CALL_INITIATION && call.direction == Direction.incoming) {
        _waitingCall = call;
        final caller = call.remote_identity ?? 'مجهول';
        _ringtone.playRingtone();
        state = state.copyWith(
          hasIncomingCallWaiting: true,
          callerNumberWaiting: caller,
          isVideoWaiting: call.remote_has_video,
        );
      }
      return;
    }

    _currentCall = call;
    switch (callState.state) {
      case CallStateEnum.CALL_INITIATION:
        if (call.direction == Direction.incoming) {
          final caller = call.remote_identity ?? 'مجهول';
          _ringtone.playRingtone();
          state = state.copyWith(
            status: CallStatus.incoming,
            callerNumber: caller,
            isVideoEnabled: call.remote_has_video,
          );
        }
      case CallStateEnum.STREAM:
        _handleStream(callState);
      case CallStateEnum.PROGRESS:
        if (call.direction == Direction.outgoing) {
          state = state.copyWith(status: CallStatus.ringing);
        }
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        _ringtone.stop();
        Helper.setSpeakerphoneOn(false);
        state = state.copyWith(status: CallStatus.active);
      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
        _ringtone.stop();
        Helper.setSpeakerphoneOn(true);
        _currentCall = null;
        _disposeRenderers();

        // If we have a held call, resume it!
        if (_heldCall != null) {
          _currentCall = _heldCall;
          _heldCall = null;
          _currentCall!.unhold();
          state = SipState(
            status: CallStatus.active,
            registrationStatus: state.registrationStatus,
            callerNumber: _currentCall!.remote_identity,
            isVideoEnabled: _currentCall!.remote_has_video,
            hasHeldCall: false,
            callerNumberHeld: null,
            isConferenceActive: false,
          );
        } else {
          state = SipState(registrationStatus: state.registrationStatus);
        }
      default:
        break;
    }
  }

  void _handleStream(CallState callState) {
    if (callState.stream == null) return;
    final stream = callState.stream!;

    if (callState.originator == Originator.local && _localRenderer != null) {
      _localRenderer!.srcObject = stream;
      state = state.copyWith(localRenderer: _localRenderer);
    } else if (callState.originator == Originator.remote &&
        _remoteRenderer != null) {
      _remoteRenderer!.srcObject = stream;
      state = state.copyWith(remoteRenderer: _remoteRenderer);
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}
  @override
  void onNewNotify(Notify ntf) {}
  @override
  void onNewReinvite(ReInvite event) {}
  @override
  void transportStateChanged(TransportState s) {
    switch (s.state) {
      case TransportStateEnum.CONNECTING:
        _safeSetState((st) =>
            st.copyWith(registrationStatus: SipRegistrationStatus.registering));
      case TransportStateEnum.CONNECTED:
        final bool isAnonymous = UcmConfig.clientMode == 'anonymous';
        if (isAnonymous) {
          _safeSetState((st) =>
              st.copyWith(registrationStatus: SipRegistrationStatus.registered));
        }
      case TransportStateEnum.DISCONNECTED:
        _safeSetState((st) => st.copyWith(
              registrationStatus: st.registrationStatus == SipRegistrationStatus.registered
                  ? SipRegistrationStatus.unregistered
                  : SipRegistrationStatus.failed,
            ));
      default:
        break;
    }
  }

  void _safeSetState(SipState Function(SipState) updater) {
    try {
      state = updater(state);
    } catch (_) {
      // provider not yet initialized — callback fired during build(), ignore
    }
  }
}

final sipProvider = NotifierProvider<SipNotifier, SipState>(SipNotifier.new);
