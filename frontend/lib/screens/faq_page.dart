import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/app_properties.dart';

class FaqPage extends StatefulWidget {
  const FaqPage({super.key});

  @override
  _FaqPageState createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  List<Panel> panels = [
    Panel(
      'What are the key features of the SOS service?',
      'The SOS service provides various features such as location sharing, distress signal broadcasting, and automatic scream detection.',
      false,
    ),
    Panel(
      'How do I activate the emergency signal?',
      'You can activate the emergency signal by tapping the SOS button in the app or by shaking your device vigorously.',
      false,
    ),
    Panel(
      'Will my location be shared when I activate the SOS signal?',
      'Yes, your location will be shared with your trusted contacts and emergency services when you activate the SOS signal.',
      false,
    ),
    Panel(
      'How can I add emergency contacts?',
      'You can add emergency contacts in the settings section of the app. These contacts will be notified when you activate the SOS signal.',
      false,
    ),
    Panel(
      'Can I customize the SOS message?',
      'Yes, you can customize the SOS message to include relevant information such as medical conditions and allergies.',
      false,
    ),
    Panel(
      'How do I test the SOS signal?',
      'You can test the SOS signal by activating it in a safe environment. Please note that testing the signal will trigger notifications to your emergency contacts.',
      false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        iconTheme: const IconThemeData(
          color: Colors.black,
        ),
        backgroundColor: Colors.transparent,
        title: const Text(
          'FAQ',
          style: TextStyle(color: darkGrey),
        ),
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 24.0),
          child: ListView(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(
                    left: 24.0, right: 24.0, bottom: 16.0),
                child: Text(
                  'Frequently Asked Questions',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 18.0,
                  ),
                ),
              ),
              ...panels
                  .map(
                    (panel) => ExpansionTile(
                      title: Text(
                        panel.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16.0),
                          color: Colors.black12,
                          child: Text(
                            panel.content,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  ,
            ],
          ),
        ),
      ),
    );
  }
}

class Panel {
  String title;
  String content;
  bool expanded;

  Panel(this.title, this.content, this.expanded);
}
