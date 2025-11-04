import 'package:flutter/material.dart';

const Color green = Color(0xffA8ED50);
const Color mediumGreen = Color(0xff9DDC4E);
const Color darkGreen = Color(0xff7EBE4B);
const Color transparentGreen = Color.fromRGBO(168, 237, 80, 0.7);
const Color darkGrey = Color(0xff202020);

const LinearGradient mainButton = LinearGradient(colors: [
  Color.fromRGBO(236, 60, 3, 1),
  Color.fromRGBO(234, 60, 3, 1),
  Color.fromRGBO(216, 78, 16, 1),
], begin: FractionalOffset.topCenter, end: FractionalOffset.bottomCenter);

const List<BoxShadow> shadow = [
  BoxShadow(color: Colors.transparent, offset: Offset(0, 3), blurRadius: 6)
];

double screenAwareSize(int size, BuildContext context) {
  double baseHeight = 640.0;
  return size * MediaQuery.of(context).size.height / baseHeight;
}
