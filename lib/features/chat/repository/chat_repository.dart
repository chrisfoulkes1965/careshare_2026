import "dart:async";

import "package:cloud_firestore/cloud_firestore.dart";
import "package:firebase_auth/firebase_auth.dart";

import "../models/chat_channel.dart";
import "../models/chat_message.dart";

class ChatRepository {
  ChatRepository({required bool firebaseReady})
      : _firebaseReady = firebaseReady;

  final bool _firebaseReady;

  static const Duration _opTimeout = Duration(minutes: 2);
  static const int _unreadQueryCap = 100;

  bool get isAvailable => _firebaseReady;

  Future<T> _withTimeout<T>(Future<T> f) {
    return f.timeout(
      _opTimeout,
      onTimeout: () {
        throw TimeoutException(
          "This is taking too long. Check your network and try again.",
        );
      },
    );
  }

  CollectionReference<Map<String, dynamic>> _channels(String careGroupId) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("chatChannels");
  }

  CollectionReference<Map<String, dynamic>> _messages(
    String careGroupId,
    String channelId,
  ) {
    return _channels(careGroupId).doc(channelId).collection("messages");
  }

  DocumentReference<Map<String, dynamic>> _readStateDoc(
    String careGroupId,
    String userId,
    String channelId,
  ) {
    return FirebaseFirestore.instance
        .collection("careGroups")
        .doc(careGroupId)
        .collection("userChannelRead")
        .doc(userId)
        .collection("channels")
        .doc(channelId);
  }

  /// Channels the user belongs to.
  Stream<List<ChatChannel>> watchMyChannels(
    String careGroupId, {
    required String myUid,
  }) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _channels(careGroupId)
        .where("memberUids", arrayContains: myUid)
        .snapshots()
        .map(
      (s) {
        final list = s.docs
            .map(
              (d) => ChatChannel.fromDoc(
                d.id,
                d.data(),
              ),
            )
            .toList();
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return list;
      },
    );
  }

  /// Messages newest first.
  Stream<List<ChatMessage>> watchMessages(
    String careGroupId,
    String channelId, {
    int limit = 80,
  }) {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return _messages(careGroupId, channelId)
        .orderBy("createdAt", descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (s) => s.docs
              .map(
                (d) => ChatMessage.fromDoc(d.id, d.data()),
              )
              .toList(),
        );
  }

  /// Counts non-self messages with [createdAt] after [lastRead] (inclusive of edge handled by client).
  Future<int> countUnread(
    String careGroupId,
    String channelId, {
    required String myUid,
    DateTime? lastRead,
  }) async {
    if (!_firebaseReady) {
      return 0;
    }
    final q = _messages(careGroupId, channelId);
    Query<Map<String, dynamic>> query = lastRead != null
        ? q
            .where(
              "createdAt",
              isGreaterThan: Timestamp.fromDate(
                lastRead,
              ),
            )
            .orderBy("createdAt", descending: false)
        : q.orderBy("createdAt", descending: true);
    final snap = await _withTimeout(
      query.limit(_unreadQueryCap).get(),
    );
    var n = 0;
    for (final d in snap.docs) {
      final by = d.data()["createdBy"] as String?;
      if (by != null && by != myUid) {
        n++;
      }
    }
    return n;
  }

  Future<DateTime?> getLastRead(
    String careGroupId, {
    required String myUid,
    required String channelId,
  }) async {
    if (!_firebaseReady) {
      return null;
    }
    final s = await _readStateDoc(careGroupId, myUid, channelId).get();
    if (!s.exists) {
      return null;
    }
    final t = s.data()?["lastReadAt"];
    if (t is Timestamp) {
      return t.toDate();
    }
    return null;
  }

  Future<void> markRead(
    String careGroupId, {
    required String myUid,
    required String channelId,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    await _withTimeout(
      _readStateDoc(careGroupId, myUid, channelId).set(
        {"lastReadAt": FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      ),
    );
  }

  Future<String> createChannel({
    required String careGroupId,
    required String name,
    String description = "",
    String topic = "general",
    required List<String> memberUids,
  }) async {
    if (!_firebaseReady) {
      return "";
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final n = name.trim();
    if (n.isEmpty) {
      throw ArgumentError("Channel name is required.");
    }
    if (!memberUids.contains(uid)) {
      throw ArgumentError("Include yourself in the member list.");
    }
    if (memberUids.isEmpty) {
      throw ArgumentError("Add at least one member.");
    }
    final data = <String, dynamic>{
      "name": n,
      "description": description.trim(),
      "topic": topic.trim().isEmpty ? "general" : topic.trim(),
      "memberUids": memberUids.toList(),
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
    };
    final ref = await _withTimeout(_channels(careGroupId).add(data));
    return ref.id;
  }

  Future<void> sendTextMessage(
    String careGroupId, {
    required String channelId,
    required String text,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError("Not signed in.");
    }
    final t = text.trim();
    if (t.isEmpty) {
      throw ArgumentError("Message is empty.");
    }
    final batch = FirebaseFirestore.instance.batch();
    final msg = _messages(careGroupId, channelId).doc();
    batch.set(msg, {
      "text": t,
      "createdBy": uid,
      "createdAt": FieldValue.serverTimestamp(),
    });
    batch.set(
      _readStateDoc(careGroupId, uid, channelId),
      {"lastReadAt": FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    await _withTimeout(batch.commit());
  }

  /// Removes [myUid] from the channel [memberUids] list.
  /// Sets or clears the optional WhatsApp group invite URL (`https://chat.whatsapp.com/...`).
  /// Carers / principal only (see Firestore rules).
  Future<void> setChannelWhatsappInviteUrl(
    String careGroupId, {
    required String channelId,
    String? whatsappInviteUrl,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final t = whatsappInviteUrl?.trim() ?? "";
    await _withTimeout(
      _channels(careGroupId).doc(channelId).update(
            t.isEmpty
                ? {"whatsappInviteUrl": FieldValue.delete()}
                : {"whatsappInviteUrl": t},
          ),
    );
  }

  Future<void> leaveChannel(
    String careGroupId, {
    required String channelId,
    required String myUid,
  }) async {
    if (!_firebaseReady) {
      return;
    }
    final ch = _channels(careGroupId).doc(channelId);
    await _withTimeout(
      FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ch);
        if (!snap.exists) {
          return;
        }
        final m = (snap.data()?["memberUids"] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            <String>[];
        if (!m.contains(myUid)) {
          return;
        }
        final next = m.where((id) => id != myUid).toList();
        // Delete read cursor while we are still a member (rules check membership).
        tx.delete(_readStateDoc(careGroupId, myUid, channelId));
        tx.update(ch, {"memberUids": next});
      }),
    );
  }
}
