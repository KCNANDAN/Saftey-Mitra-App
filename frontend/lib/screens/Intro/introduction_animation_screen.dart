// lib/introduction_animation_screen.dart
// Replaces the onboarding / intro animation screen to precache images
// and use FadeInImage so the red X doesn't show while images load.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

// package import for your component
import 'package:frontend/screens/Intro/components/center_next_button.dart';

class IntroductionAnimationScreen extends StatefulWidget {
  const IntroductionAnimationScreen({super.key});

  @override
  State<IntroductionAnimationScreen> createState() =>
      _IntroductionAnimationScreenState();
}

class _IntroductionAnimationScreenState
    extends State<IntroductionAnimationScreen> with TickerProviderStateMixin {
  late final AnimationController animationController;
  final PageController _pageController = PageController();
  int _pageIndex = 0;

  // Use assets you already have to avoid missing-asset build errors
  final List<String> _slideImages = [
    'assets/images/menu.png', // existed in your project earlier
    'assets/icons/logo.png', // existed in your project earlier
    'assets/images/menu.png', // reuse menu for third slide (replace later if you add new images)
  ];

  // Small local asset used as placeholder; must exist in pubspec.yaml
  final String _placeholder = 'assets/icons/logo.png';

  @override
  void initState() {
    super.initState();

    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..value = 0.0;

    // Precache images after first frame so `context` is valid.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheImages();
    });
  }

  @override
  void dispose() {
    animationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _precacheImages() async {
    // Precache placeholder first (safe small asset)
    try {
      await precacheImage(AssetImage(_placeholder), context);
      debugPrint('Precached placeholder $_placeholder');
    } catch (e) {
      debugPrint('Precache placeholder failed: $e');
    }

    // Precache slide images (log exceptions but continue)
    for (final path in _slideImages) {
      try {
        await precacheImage(AssetImage(path), context);
        debugPrint('Precached $path');
      } catch (e) {
        debugPrint('Precache failed for $path: $e');
      }
    }
  }

  void _onNextPressed() {
    if (_pageIndex < _slideImages.length - 1) {
      _pageIndex++;
      _pageController.animateToPage(_pageIndex,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);

      final progress = (_pageIndex + 1) / (_slideImages.length);
      animationController.animateTo(progress.clamp(0.0, 1.0),
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      // Finished onboarding — navigate to your main screen (adjust route if needed)
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  void _onPageChanged(int p) {
    setState(() => _pageIndex = p);
    final progress = (_pageIndex + 1) / (_slideImages.length);
    animationController.animateTo(progress.clamp(0.0, 1.0),
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Widget _buildSlide(String assetPath, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 24.0),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: FadeInImage(
                placeholder: AssetImage(_placeholder),
                image: AssetImage(assetPath),
                fit: BoxFit.contain,
                fadeInDuration: const Duration(milliseconds: 320),
                fadeOutDuration: const Duration(milliseconds: 150),
                placeholderErrorBuilder: (c, e, s) =>
                    const Icon(Icons.image_not_supported, size: 64),
                imageErrorBuilder: (c, e, s) =>
                    const Icon(Icons.broken_image, size: 64),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slides = [
      {
        'title': 'Welcome to Safety Mitra',
        'subtitle': 'Keep safe, stay connected with trusted companions.',
        'image': _slideImages[0],
      },
      {
        'title': 'Share Live Location',
        'subtitle': 'Create or join sessions and share location securely.',
        'image': _slideImages[1],
      },
      {
        'title': 'Get Safety Tips',
        'subtitle': 'Daily tips and emergency features at your fingertips.',
        'image': _slideImages[2],
      },
    ];

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: slides.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final s = slides[index];
                  return _buildSlide(s['image']!, s['title']!, s['subtitle']!);
                },
              ),
            ),

            // Dots indicator
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(slides.length, (i) {
                  final selected = i == _pageIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: selected ? 18 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color:
                          selected ? const Color(0xff132137) : Colors.grey[300],
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                }),
              ),
            ),

            Padding(
              padding: EdgeInsets.only(
                  bottom: 16 + MediaQuery.of(context).padding.bottom),
              child: CenterNextButton(
                animationController: animationController,
                onNextClick: _onNextPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
