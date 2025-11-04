import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/app_properties.dart';
import 'package:frontend/custom_background.dart';
import 'package:frontend/utils/api_requests.dart'; // getSafetyTip + ApiException

class DailyTipsPage extends StatefulWidget {
  const DailyTipsPage({super.key});

  @override
  State<DailyTipsPage> createState() => _DailyTipsPageState();
}

class _DailyTipsPageState extends State<DailyTipsPage> {
  bool _loading = false;
  String? _error;
  String? _tip;

  @override
  void initState() {
    super.initState();
    _fetchTip();
  }

  Future<void> _fetchTip() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Add a short timeout so we don't wait forever and risk ANR symptomatically.
      final res = await getSafetyTip().timeout(const Duration(seconds: 8));
      final tip = (res is Map && res['tip'] is String)
          ? res['tip'] as String
          : res.toString();
      if (!mounted) return;
      setState(() => _tip = tip);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } on TimeoutException {
      if (!mounted) return;
      setState(
          () => _error = 'Request timed out. Make sure backend is running.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load tip. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Small helper to avoid crash when an image asset is missing — shows a placeholder.
  Widget _assetOrPlaceholder(String assetPath, {BoxFit fit = BoxFit.cover}) {
    return Image.asset(
      assetPath,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 180,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text('Image not found', style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: MainBackground(),
      child: Scaffold(
        appBar: AppBar(
          iconTheme: const IconThemeData(color: Colors.black),
          backgroundColor: Colors.transparent,
          title: const Text('Daily Tips', style: TextStyle(color: darkGrey)),
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          actions: [
            IconButton(
              tooltip: 'Refresh tip',
              onPressed: _loading ? null : _fetchTip,
              icon: const Icon(Icons.refresh, color: Colors.black),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(
                right: 24.0, left: 24.0, bottom: 24.0, top: 7.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // ---------- Today's Tip Card (now dynamic) ----------
                Card(
                  elevation: 10,
                  color: Colors.orange[200],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Today's Tip",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 26.0,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Title (static headline)
                        const Text(
                          'Trust Your Instincts',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 22.0,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Tip content area: loading / error / tip text
                        if (_loading) ...[
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ] else if (_error != null) ...[
                          Text(
                            _error!,
                            style: const TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _fetchTip,
                            child: const Text('Retry'),
                          ),
                        ] else ...[
                          Text(
                            _tip ??
                                'Always trust your instincts when making decisions. Explore all features and apply the tips to enhance your experience. Small, consistent improvements can lead to significant progress.',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.black87,
                              height: 1.5,
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),
                        // Image (uses safe helper)
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16.0),
                            child: SizedBox(
                              height: 180,
                              width: double.infinity,
                              child: _assetOrPlaceholder(
                                'assets/im7.jpg',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ---------- Daily Quotes ----------
                Text(
                  'Daily Quotes',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800]),
                ),
                const SizedBox(height: 10),
                _buildQuotesSection(),

                const SizedBox(height: 20),

                // ---------- More Tips ----------
                Text(
                  'More Tips',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800]),
                ),
                const SizedBox(height: 10),
                _buildAdditionalTips(),

                const SizedBox(height: 20),

                // ---------- Latest News ----------
                Text(
                  'Latest News',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800]),
                ),
                const SizedBox(height: 10),
                _buildNewsSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Horizontal Scroll for Quotes
  Widget _buildQuotesSection() {
    final quotes = [
      '“Believe in yourself and all that you are.”',
      '“You are stronger than you think.”',
      '“Success is not final, failure is not fatal.”',
      '“Keep pushing forward, no matter what.”',
    ];

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: quotes.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              width: 250,
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(
                  quotes[index],
                  style: TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: Colors.green[900],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Horizontal Scroll for Additional Tips
  Widget _buildAdditionalTips() {
    final tips = [
      'Always be aware of your surroundings, especially in unfamiliar areas.',
      'Keep your phone fully charged and easily accessible.',
      'Share your location with a trusted friend or family member when going out.',
      'Trust your instincts—if something feels off, remove yourself from the situation.',
      'Learn basic self-defense techniques and practice them regularly.',
    ];

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tips.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              width: 300,
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Text(
                tips[index],
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNewsSection() {
    final news = [
      'Stay safe during your travels — carry essential numbers.',
      'Always keep a power bank while going out for long durations.',
      'Be mindful of your surroundings at night.',
    ];

    return Column(
      children: news
          .map((n) => Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(n),
                ),
              ))
          .toList(),
    );
  }
}
