import 'package:flutter/material.dart';
import 'package:frontend/app_properties.dart';
// import 'package:frontend/screens/main/main_page.dart';

class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  @override
  _IntroPageState createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  PageController controller = PageController();
  int pageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: <Widget>[
          PageView(
            onPageChanged: (value) {
              setState(() {
                pageIndex = value;
              });
            },
            controller: controller,
            children: <Widget>[
              _buildPage(
                'assets/firstScreen.png',
                'Empowering Women Through Safety',
                'Join us today and be part of a community dedicated to empowering women through safety. Together, we can create a safer environment for all women, one step at a time.',
              ),
              _buildPage(
                'assets/secondScreen.png',
                'Ensuring Safety and Security',
                'Our platform prioritizes your safety and security, providing peace of mind to all users. Join us in our mission to empower women through safety.',
              ),
              _buildPage(
                'assets/thirdScreen.png',
                'Stay Safe and Informed, Always',
                'We are committed to ensuring that you receive timely updates and information to help you stay safe and informed at all times. Your safety matters to us!',
              ),
            ],
          ),
          Positioned(
            bottom: 16.0,
            left: 0,
            right: 0,
            child: Column(
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                    (index) => Container(
                      margin: const EdgeInsets.all(8.0),
                      height: 12,
                      width: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.deepPurpleAccent,
                          width: 2,
                        ),
                        color: pageIndex == index ? green : Colors.transparent,
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    Opacity(
                      opacity: pageIndex != 2 ? 1.0 : 0.0,
                      child: TextButton(
                        onPressed: () {},
                        child: const Text(
                          'SKIP',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    pageIndex != 2
                        ? TextButton(
                            onPressed: () {
                              if (!(controller.page == 2.0)) {
                                controller.nextPage(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.linear,
                                );
                              }
                            },
                            child: const Text(
                              'NEXT',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          )
                        : TextButton(
                            onPressed: () {},
                            child: const Text(
                              'FINISH',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          )
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(String imagePath, String title, String description) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        GestureDetector(
          onTap: () {
            // Add image selection logic here
          },
          child: Center(
            child: Image.asset(
              imagePath,
              height: 200,
              width: 200,
            ),
          ),
        ),
        const SizedBox(height: 16.0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: darkGrey,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16.0),
          child: Text(
            description,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.black, fontSize: 12.0),
          ),
        ),
      ],
    );
  }
}
