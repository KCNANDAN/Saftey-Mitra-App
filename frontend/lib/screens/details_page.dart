import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend/app_properties.dart';
import 'package:frontend/custom_background.dart';

class DetailsPage extends StatelessWidget {
  const DetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: MainBackground(),
      child: Scaffold(
        appBar: AppBar(
          iconTheme: const IconThemeData(color: Colors.black),
          backgroundColor: Colors.transparent,
          title: const Text(
            'Details & Medical Info',
            style: TextStyle(color: darkGrey),
          ),
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        body: SafeArea(
          bottom: true,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(75),
                      ),
                      child: const Icon(Icons.person, size: 100, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 24.0),
                  const Text(
                    'Personal Details',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18.0,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  const ListTile(
                    title: Text('Name: ABC'),
                  ),
                  const ListTile(
                    title: Text('Age: 30'),
                  ),
                  const ListTile(
                    title: Text('Gender: Male'),
                  ),
                  const ListTile(
                    title: Text('Address: XYZ Area, City'),
                  ),
                  const SizedBox(height: 24.0),
                  const Text(
                    'Contact Details',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18.0,
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  const ListTile(
                    title: Text('Phone: +1234567890'),
                  ),
                  const ListTile(
                    title: Text('Email: abc@example.com'),
                  ),
                  const ListTile(
                    title: Text('Guardian No.: +9876543210'),
                  ),
                  const SizedBox(height: 24.0),
                  const Text(
                    'Medical Info',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18.0,
                    ),
                  ),
                  const ListTile(
                    title: Text('Blood Type: O+'),
                  ),
                  const ListTile(
                    title: Text('Allergies: None'),
                  ),
                  const ListTile(
                    title: Text('Medical Conditions: None'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
