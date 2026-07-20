const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Cloud Function: onNewMessage
 *
 * Triggers when a new message document is created in any conversation.
 * Looks up the receiver's FCM token from the 'users' collection and
 * sends a high-priority push notification so it arrives even when
 * the app is completely killed / cleared from recents.
 */
exports.onNewMessage = functions.firestore
  .document("conversations/{connectionId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return null;

    const receiverUid = data.receiverUid;
    const senderPhone = data.senderPhone || "Unknown";
    const mediaType = data.mediaType || "text";

    if (!receiverUid) {
      console.log("No receiverUid found, skipping.");
      return null;
    }

    // Look up receiver's FCM token
    const userDoc = await admin.firestore().collection("users").doc(receiverUid).get();
    if (!userDoc.exists) {
      console.log(`User ${receiverUid} not found.`);
      return null;
    }

    const userData = userDoc.data();
    const fcmToken = userData.fcmToken;

    if (!fcmToken) {
      console.log(`No FCM token for user ${receiverUid}.`);
      return null;
    }

    // Build notification payload
    const notificationBody = mediaType === "audio"
      ? "🎤 Voice Note"
      : "New encrypted message";

    const message = {
      token: fcmToken,
      notification: {
        title: `${senderPhone}`,
        body: notificationBody,
      },
      data: {
        senderUid: data.senderUid || "",
        senderPhone: senderPhone,
        messageId: data.id || "",
        connectionId: context.params.connectionId,
        type: "new_message",
      },
      android: {
        priority: "high",
        notification: {
          channelId: "whisper_msg_channel",
          priority: "max",
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
    };

    try {
      await admin.messaging().send(message);
      console.log(`Push notification sent to ${receiverUid} (${senderPhone})`);
    } catch (error) {
      console.error(`Error sending notification to ${receiverUid}:`, error);
      // If token is invalid/expired, clean it up
      if (
        error.code === "messaging/invalid-registration-token" ||
        error.code === "messaging/registration-token-not-registered"
      ) {
        await admin.firestore().collection("users").doc(receiverUid).update({
          fcmToken: admin.firestore.FieldValue.delete(),
        });
        console.log(`Cleaned up invalid FCM token for ${receiverUid}`);
      }
    }

    return null;
  });
