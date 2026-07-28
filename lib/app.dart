import 'package:flutter/material.dart';
import 'features/board/board_screen.dart';
import 'theme.dart';

class BoloApp extends StatelessWidget {
  const BoloApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bolo',
        debugShowCheckedModeBanner: false,
        theme: boloThemeData(),
        home: const BoardScreen(),
      );
}
