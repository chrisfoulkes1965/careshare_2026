import "package:firebase_core/firebase_core.dart";
import "package:flutter/material.dart";

import "app.dart";
import "core/medication_reminders/medication_notification_service.dart";
import "firebase_options.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (e, st) {
    debugPrint("Firebase init failed: $e\n$st");
  }
  if (firebaseReady) {
    await MedicationNotificationService.instance.init();
  }

  runApp(CareShareRoot(firebaseReady: firebaseReady));
}
