import 'package:flutter/material.dart';
import 'package:frontend/screens/contacts_page.dart';
import 'package:frontend/utils/api_requests.dart';
import 'package:frontend/utils/user_prefs.dart'; // 👈 NEW: read saved phone
import 'package:geolocator/geolocator.dart';

class EmergencyCallScreen extends StatefulWidget {
  const EmergencyCallScreen({super.key});

  @override
  State<EmergencyCallScreen> createState() => _EmergencyCallScreenState();
}

class _EmergencyCallScreenState extends State<EmergencyCallScreen> {
  bool _sending = false;

  // --------- Location helpers ---------
  Future<bool> _ensureLocationReady(BuildContext context) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnack(context, 'Location services are disabled.');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      _showSnack(context, 'Location permission denied.');
      return false;
    }
    if (permission == LocationPermission.deniedForever) {
      _showSnack(context,
          'Location permission denied forever. Enable it in Settings.');
      return false;
    }
    return true;
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --------- Open bottom sheet to collect phone + message and send SOS ---------
  void _openSendSOSSheet(BuildContext context) {
    // 👇 Prefill with saved user phone (if any)
    final phoneCtrl = TextEditingController(text: UserPrefs.userPhone ?? '');
    final msgCtrl = TextEditingController(text: 'Need help!');
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const Text(
                  'Send SOS',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Form(
                  key: formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Your Phone / Username',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your phone/username'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: msgCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Message (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.warning_amber_rounded),
                          label: Text(_sending ? 'Sending...' : 'Send SOS'),
                          onPressed: _sending
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;

                                  // Attempt to get phone from field first, else fall back to prefs
                                  String userPhone = phoneCtrl.text.trim();
                                  if (userPhone.isEmpty) {
                                    userPhone = UserPrefs.userPhone ?? '';
                                  }

                                  if (userPhone.isEmpty) {
                                    // Still empty -> show error and don't send
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Please enter your phone/username before sending SOS.')),
                                    );
                                    return;
                                  }

                                  setState(() => _sending = true);
                                  setSheetState(() {});

                                  // Ensure permissions
                                  if (!await _ensureLocationReady(context)) {
                                    setState(() => _sending = false);
                                    setSheetState(() {});
                                    return;
                                  }

                                  try {
                                    final pos =
                                        await Geolocator.getCurrentPosition(
                                      desiredAccuracy: LocationAccuracy.high,
                                      timeLimit: const Duration(seconds: 10),
                                    );

                                    await sendSOS(
                                      latitude: pos.latitude,
                                      longitude: pos.longitude,
                                      message: msgCtrl.text.trim().isEmpty
                                          ? 'Need help!'
                                          : msgCtrl.text.trim(),
                                      userPhoneNumber:
                                          userPhone, // IMPORTANT: pass user
                                    );

                                    if (!mounted) return;
                                    Navigator.pop(ctx); // close sheet
                                    _showSnack(
                                        context, 'SOS sent successfully');
                                  } on ApiException catch (e) {
                                    _showSnack(context, e.message);
                                  } catch (e) {
                                    _showSnack(context,
                                        'Failed to send SOS. Please try again.');
                                  } finally {
                                    if (mounted) {
                                      setState(() => _sending = false);
                                      setSheetState(() {});
                                    }
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset('assets/icons/logo.png',
                            height: 80, width: 80),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            'Emergency Call Settings',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[800],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Set up your preferred way to trigger an emergency call quickly and easily.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Trigger Options',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _showGestureModal(context),
                      child: ListTile(
                        leading: Icon(Icons.gesture, color: Colors.green[800]),
                        title: const Text('Set Gesture'),
                        subtitle: const Text(
                            'Activate an emergency call with a gesture.'),
                        trailing:
                            Icon(Icons.chevron_right, color: Colors.green[800]),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showVoiceCommandModal(context),
                      child: ListTile(
                        leading: Icon(Icons.mic, color: Colors.green[800]),
                        title: const Text('Set Voice Command'),
                        subtitle: const Text(
                            'Initiate an emergency call with a voice command.'),
                        trailing:
                            Icon(Icons.chevron_right, color: Colors.green[800]),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _showHardwareButtonModal(context),
                      child: ListTile(
                        leading: Icon(Icons.hardware, color: Colors.green[800]),
                        title: const Text('Set Hardware Button Combination'),
                        subtitle: const Text(
                            'Start an emergency call using your phone’s hardware buttons.'),
                        trailing:
                            Icon(Icons.chevron_right, color: Colors.green[800]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Emergency Contacts',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        debugPrint('[NAV] Opening EmergencyContactsScreen');
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const EmergencyContactsScreen(),
                          ),
                        ).then((_) {
                          debugPrint(
                              '[NAV] Returned from EmergencyContactsScreen');
                        });
                      },
                      child: ListTile(
                        leading: Icon(Icons.contacts, color: Colors.green[800]),
                        title: const Text('Manage Emergency Contacts'),
                        subtitle: const Text(
                            'Add, edit, or remove your emergency contact numbers.'),
                        trailing:
                            Icon(Icons.chevron_right, color: Colors.green[800]),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Floating pulse SOS button (opens the send sheet)
            Positioned(
              bottom: 20,
              right: 20,
              child: GestureDetector(
                onTap: _sending ? null : () => _openSendSOSSheet(context),
                child: PulseAnimation(
                  child: Container(
                    height: 70,
                    width: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _sending ? Colors.grey : Colors.green[800],
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child:
                        const Icon(Icons.call, color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== existing modals (kept as-is for your UI) =====
  void _showGestureModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Set Gesture',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800]),
              ),
              const SizedBox(height: 10),
              Text(
                'Swipe across the dots to create your gesture pattern.',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onPanUpdate: (details) {},
                child: SizedBox(
                  height: 200,
                  width: 200,
                  child: GridView.builder(
                    itemCount: 9,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemBuilder: (context, index) {
                      return Container(
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: Colors.green[800]),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[800]),
                child: const Center(child: Text('Save Gesture')),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVoiceCommandModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Set Voice Command',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800]),
              ),
              const SizedBox(height: 10),
              Text(
                'Press the mic to record your voice command.',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              const SizedBox(height: 20),
              IconButton(
                icon: Icon(Icons.mic, size: 50, color: Colors.green[800]),
                onPressed: () {},
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[800]),
                child: const Center(child: Text('Save Voice Command')),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHardwareButtonModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Set Hardware Button Combination',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800]),
              ),
              const SizedBox(height: 10),
              Text(
                'Select a combination of hardware buttons to trigger the emergency call.',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Choose Button Combination',
                  labelStyle: TextStyle(color: Colors.green[800]),
                  border: const OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'Volume Up + Power',
                      child: Text('Volume Up + Power')),
                  DropdownMenuItem(
                      value: 'Volume Down + Power',
                      child: Text('Volume Down + Power')),
                  DropdownMenuItem(
                      value: 'Power Button (Triple Press)',
                      child: Text('Power Button (Triple Press)')),
                ],
                onChanged: (value) {},
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[800]),
                child: const Center(child: Text('Save Hardware Setting')),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PulseAnimation extends StatefulWidget {
  final Widget child;
  const PulseAnimation({super.key, required this.child});

  @override
  _PulseAnimationState createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: const Duration(seconds: 1), vsync: this)
          ..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _animation, child: widget.child);
  }
}
