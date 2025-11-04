// lib/screens/home_page.dart
import 'package:flutter/material.dart';
import 'package:frontend/screens/daily_tip_page.dart';
import 'package:frontend/screens/emergency_page.dart';
import 'package:frontend/screens/settings_page.dart';
import 'package:frontend/screens/travel_partner_page.dart';
import 'package:frontend/utils/utils.dart'; // AppConstant + AppData
import 'dart:developer' as dev;
// add alongside your other imports
import 'package:frontend/screens/relationships_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // debug print to ensure AppData list exists
    dev.log('HomeScreen init - live options: ${AppData.liveSelectOptions}',
        name: 'HomeScreen');
  }

  void _handleLiveSelectTap(String label) {
    final v = label.trim().toLowerCase();
    dev.log('LiveSelect tapped: $label', name: 'HomeScreen');

    // show immediate visual feedback
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Tapped: $label')),
    );

    // Navigation rules (case-insensitive)
    if (v.contains('setting')) {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => SettingsScreen()));
      return;
    }

    if (v.contains('tip')) {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => DailyTipsPage()));
      return;
    }

    if (v.contains('emergency')) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const EmergencyCallScreen()));
      return;
    }

    if (v.contains('relationship')) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const RelationshipsPage()));
      return;
    }

    if (v.contains('travel')) {
      // quick navigation to travel partner (test)
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const TravelPartnerPage()));
      return;
    }

    // fallback: small dialog
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Not wired'),
        content: Text('No action wired for: $label'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final liveOptions = AppData.liveSelectOptions; // must be List<String>
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppConstant.horizontalPadding,
                right: AppConstant.horizontalPadding,
                top: AppConstant.verticalPadding,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/images/menu.png',
                      height: 30, color: Colors.black),
                  const Icon(Icons.person, size: 30, color: Colors.black),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppConstant.horizontalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: Image.asset('assets/icons/logo.png',
                          height: 100, width: 100)),
                  const SizedBox(height: 10),
                  Text(
                    'Safety Mitra',
                    style: TextStyle(
                      fontFamily:
                          'Roboto', // safe system fallback; change if you included another local font
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    'Stay in control with Safety Mitra\'s \'Live Select\' - Your personalized safety solution for peace of mind on the go!',
                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            const Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: AppConstant.horizontalPadding),
              child: Divider(color: Colors.grey, thickness: 1),
            ),
            const SizedBox(height: 10),

            // Live Select list (robust tappable list)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppConstant.horizontalPadding),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 2,
                          blurRadius: 5,
                          offset: const Offset(0, 3))
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12)),
                        ),
                        child: Text('Live Select',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[800])),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: liveOptions.length,
                          separatorBuilder: (_, __) =>
                              Divider(color: Colors.green.shade100, height: 1),
                          itemBuilder: (context, idx) {
                            final label = liveOptions[idx];
                            return InkWell(
                              onTap: () => _handleLiveSelectTap(label),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12.0, vertical: 16),
                                child: Row(
                                  children: [
                                    Expanded(
                                        child: Text(label,
                                            style:
                                                const TextStyle(fontSize: 16))),
                                    const Icon(Icons.chevron_right,
                                        size: 20, color: Colors.grey),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppConstant.horizontalPadding),
                child: Text(
                  'Swift support when you need it the most!',
                  style: TextStyle(fontSize: 16, color: Colors.grey[800]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
