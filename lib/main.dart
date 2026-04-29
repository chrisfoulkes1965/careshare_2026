import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "app.dart";
import "core/avatars/avatar_choices.dart";
import "core/invite/pending_invitation_store.dart";
import "core/medication_reminders/medication_notification_service.dart";
import "core/push/careshare_push_service.dart";
import "firebase_options.dart";

@pragma("vm:entry-point")
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage _) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAvatarAssetPaths();
  await PendingInvitationStore.primeFromStartupUrlIfWeb();

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
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await CaresharePushService.instance.start();
    }
  }

  runApp(CareShareRoot(firebaseReady: firebaseReady));
}
