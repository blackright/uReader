import 'package:flutter/material.dart';

import 'app/dependencies.dart';
import 'app/prototype_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.createDependencies});
  final Future<AppDependencies> Function()? createDependencies;

  @override
  Widget build(BuildContext context) =>
      PrototypeApp(createDependencies: createDependencies);
}
