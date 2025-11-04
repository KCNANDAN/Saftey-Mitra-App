import 'package:frontend/app_properties.dart';
import 'package:frontend/screens/details_page.dart';
import 'package:frontend/screens/faq_page.dart';
// import 'package:frontend/screens/settings/settings_page.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF9F9F9),
      body: SafeArea(
        top: true,
        child: SingleChildScrollView(
          child: Padding(
            padding:
                const EdgeInsets.only(left: 16.0, right: 16.0, top: kToolbarHeight),
            child: Column(
              children: <Widget>[
                const CircleAvatar(
                  maxRadius: 48,
                  backgroundImage: AssetImage('assets/icons/logo.png'),
                ),
                const Padding(
                  padding: EdgeInsets.only(
                      bottom: 18.0, left: 8.0, right: 8.0, top: 8.0),
                  child: Text(
                    'Voyage',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  title: const Text('Details'),
                  subtitle: const Text('Your Personal Details and Medical Info'),
                  leading: Image.asset(
                    'assets/icons/settings_icon.png',
                    fit: BoxFit.scaleDown,
                    width: 30,
                    height: 30,
                  ),
                  trailing: const Icon(Icons.chevron_right, color: green),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => DetailsPage())),
                ),
                const Divider(),
                ListTile(
                  title: const Text('Emergency Contacts'),
                  subtitle: const Text(
                      'Set Emergency Contacts to inform in case of an Emergency'),
                  leading: Image.asset(
                    'assets/icons/settings_icon.png',
                    fit: BoxFit.scaleDown,
                    width: 30,
                    height: 30,
                  ),
                  trailing: const Icon(Icons.chevron_right, color: green),
                  onTap: () => {},
                ),
                const Divider(),
                ListTile(
                  title: const Text('Temp Details'),
                  subtitle: const Text(
                      'Add Extra Details Temporarily to be sent with the Distress Call'),
                  leading: Image.asset(
                    'assets/icons/settings_icon.png',
                    fit: BoxFit.scaleDown,
                    width: 30,
                    height: 30,
                  ),
                  trailing: const Icon(Icons.chevron_right, color: green),
                  onTap: () => {},
                ),
                const Divider(),
                ListTile(
                  title: const Text('Settings'),
                  subtitle: const Text('Privacy and logout'),
                  leading: Image.asset(
                    'assets/icons/settings_icon.png',
                    fit: BoxFit.scaleDown,
                    width: 30,
                    height: 30,
                  ),
                  trailing: const Icon(Icons.chevron_right, color: green),
                  onTap: () => {},
                ),
                const Divider(),
                ListTile(
                  title: const Text('Help & Support'),
                  subtitle: const Text('Help center and legal support'),
                  leading: Image.asset('assets/icons/support.png'),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: green,
                  ),
                ),
                const Divider(),
                ListTile(
                  title: const Text('FAQ'),
                  subtitle: const Text('Questions and Answer'),
                  leading: Image.asset('assets/icons/faq.png'),
                  trailing: const Icon(Icons.chevron_right, color: green),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => FaqPage())),
                ),
                const Divider(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
