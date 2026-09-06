import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Step-by-step permission education — denial paths are explicit so users understand risk.
class PermissionOnboardingScreen extends StatefulWidget {
  const PermissionOnboardingScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<PermissionOnboardingScreen> createState() =>
      _PermissionOnboardingScreenState();
}

class _PermissionOnboardingScreenState
    extends State<PermissionOnboardingScreen> {
  final _pages = const <_PermPage>[
    _PermPage(
      title: 'Why RoadSOS asks for access',
      body:
          'In a crash or medical emergency, responders only know what your phone can send. '
          'Each permission below maps to a real alert path. Denying one does not silently fix anything — '
          'that channel simply stops working.',
      actionLabel: null,
      request: null,
    ),
    _PermPage(
      title: 'Location',
      body:
          'Location is needed so responders know where you are. Without it, SMS and mesh alerts '
          'cannot include GPS — insurers and police cannot verify where the incident occurred.',
      actionLabel: 'Allow location',
      request: _PermRequest.location,
    ),
    _PermPage(
      title: 'Location in the background',
      body:
          'Crises do not wait for the app to stay open. “Always” / background location lets RoadSOS '
          'keep a fix if you switch apps or the screen locks during an SOS. Denying this still allows '
          'SOS while the app is visible — but updates may pause when RoadSOS is not in the foreground.',
      actionLabel: 'Allow background location',
      request: _PermRequest.locationAlways,
    ),
    _PermPage(
      title: 'Bluetooth',
      body:
          'Bluetooth broadcasts a short SOS beacon to nearby RoadSOS users when towers fail. '
          'If Bluetooth stays off, mesh relay to bystanders may not start.',
      actionLabel: 'Allow Bluetooth',
      request: _PermRequest.bluetooth,
    ),
    _PermPage(
      title: 'SMS',
      body:
          'RoadSOS can send an emergency alert via a secure server relay (recommended) and can also '
          'open your phone\\\'s SMS app with the message pre-filled as a fallback when the relay is unavailable. '
          'On modern Android versions, direct background SMS sending permissions are often restricted. '
          'For reliability, enable the cloud relay (Twilio / Edge Function) and keep emergency dial available.',
      actionLabel: null,
      request: null,
    ),
    _PermPage(
      title: 'Camera',
      body:
          'When a bystander stops to help, they can capture a crash-scene photo. '
          'Gemma 4 analyzes the image for fire, smoke, trapped persons, and '
          'damage — improving triage accuracy without describing the scene in words. '
          'Camera is NOT accessed automatically during SOS; only when you tap '
          '"Capture Scene" in the bystander flow.',
      actionLabel: 'Allow camera',
      request: _PermRequest.camera,
    ),
    _PermPage(
      title: 'Microphone',
      body:
          'Voice capture drives hands-free triage and scene notes after impact. '
          'If denied, you must type — impossible for some injuries.',
      actionLabel: 'Allow microphone',
      request: _PermRequest.microphone,
    ),
    _PermPage(
      title: 'Notifications',
      body:
          'Notifications keep SOS and sync status visible when the app is in the background. '
          'Without them, you may miss recovery prompts.',
      actionLabel: 'Allow notifications',
      request: _PermRequest.notification,
    ),
    _PermPage(
      title: 'Battery / background',
      body:
          'Android may kill apps under heavy load. Reducing battery restrictions helps mesh scanning '
          'and background tasks survive — not guaranteed on all OEM skins.',
      actionLabel: 'Open settings',
      request: _PermRequest.battery,
    ),
  ];

  late final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runRequest(_PermRequest r) async {
    switch (r) {
      case _PermRequest.location:
        await Permission.locationWhenInUse.request();
        break;
      case _PermRequest.locationAlways:
        await Permission.locationAlways.request();
        break;
      case _PermRequest.bluetooth:
        if (Platform.isAndroid) {
          await Permission.bluetoothScan.request();
          await Permission.bluetoothConnect.request();
        } else {
          await Permission.bluetooth.request();
        }
        break;
      case _PermRequest.sms:
        // Direct SEND_SMS is intentionally not requested here: modern Android/Play
        // policies often restrict it, and RoadSOS prefers server relay + SMS intent fallback.
        break;
      case _PermRequest.camera:
        await Permission.camera.request();
        break;
      case _PermRequest.microphone:
        await Permission.microphone.request();
        break;
      case _PermRequest.notification:
        await Permission.notification.request();
        break;
      case _PermRequest.battery:
        await openAppSettings();
        break;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onComplete,
                child: const Text(
                  'SKIP FOR NOW',
                  style: TextStyle(color: Colors.white38),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final page = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        Text(
                          page.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              page.body,
                              style: const TextStyle(
                                color: Colors.white70,
                                height: 1.45,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Builder(
                    builder: (context) {
                      final page = _pages[_index];
                      if (page.actionLabel == null || page.request == null) {
                        return const SizedBox(height: 52);
                      }
                      return SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => _runRequest(page.request!),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            page.actionLabel!,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _index == 0
                            ? null
                            : () => _controller.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              ),
                        child: const Text('BACK'),
                      ),
                      const Spacer(),
                      Text(
                        '${_index + 1} / ${_pages.length}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          if (_index >= _pages.length - 1) {
                            widget.onComplete();
                          } else {
                            _controller.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                        child: Text(
                          _index >= _pages.length - 1 ? 'DONE' : 'NEXT',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PermRequest {
  location,
  locationAlways,
  bluetooth,
  sms,
  camera,
  microphone,
  notification,
  battery,
}

class _PermPage {
  final String title;
  final String body;
  final String? actionLabel;
  final _PermRequest? request;

  const _PermPage({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.request,
  });
}
