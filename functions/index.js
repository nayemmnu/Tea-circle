const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { FieldValue } = require("firebase-admin/firestore");

admin.initializeApp();
const db = admin.firestore();

// IMPORTANT: must be the same location as your Firestore database.
//   asia-south1 = Mumbai. If you created Firestore in another location,
//   change this (e.g. "us-central1" for nam5, "europe-west1" for eur3).
const REGION = "asia-south1";

// How long we wait for a phone to confirm "I received it" before marking the
// person as unavailable (offline).
const DELIVERY_WAIT_MS = 45 * 1000;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

exports.onCallCreated = onDocumentCreated(
  {
    document: "groups/{groupId}/calls/{callId}",
    region: REGION,
    timeoutSeconds: 120,
  },
  async (event) => {
    const { groupId, callId } = event.params;
    const call = event.data.data();

    const groupSnap = await db.doc(`groups/${groupId}`).get();
    if (!groupSnap.exists) return;
    const group = groupSnap.data();
    const memberIds = group.memberIds || [];
    const names = group.memberNames || {};

    // Never trust the client-supplied member list.
    await event.data.ref.update({ memberIds });

    // 1) one response document per member (caller counts as "coming")
    const responses = db.collection(`groups/${groupId}/calls/${callId}/responses`);
    const batch = db.batch();
    for (const uid of memberIds) {
      batch.set(responses.doc(uid), {
        name: names[uid] || "",
        status: uid === call.createdBy ? "accepted" : "pending",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    // 2) push notification to everybody except the caller
    const targets = memberIds.filter((u) => u !== call.createdBy);
    const tokenSnaps = await Promise.all(
      targets.map((u) => db.doc(`tokens/${u}`).get())
    );

    const messages = [];
    const owners = [];
    tokenSnaps.forEach((snap, i) => {
      const token = snap.exists ? snap.data().token : null;
      if (!token) return; // never registered a phone -> will be "unavailable"
      owners.push(targets[i]);
      messages.push({
        token,
        // data-only message: the app shows the notification itself so it can
        // add the ✅ / ❌ buttons and confirm delivery.
        data: {
          type: "tea_call",
          groupId,
          callId,
          uid: targets[i],
          groupName: String(group.name || ""),
          callerName: String(call.createdByName || ""),
          message: String(call.message || ""),
        },
        android: {
          priority: "high",
          ttl: 60 * 1000, // an offline phone must NOT get a stale invite later
        },
      });
    });

    if (messages.length > 0) {
      const res = await admin.messaging().sendEach(messages);
      // remove tokens that are dead
      await Promise.all(
        res.responses.map((r, i) => {
          const code = r.error && r.error.code;
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token"
          ) {
            return db.doc(`tokens/${owners[i]}`).delete();
          }
          return null;
        })
      );
    }

    // 3) anyone who has not confirmed delivery in time is "unavailable"
    await sleep(DELIVERY_WAIT_MS);
    const stillPending = await responses.where("status", "==", "pending").get();
    await Promise.all(
      stillPending.docs.map((d) =>
        db.runTransaction(async (tx) => {
          const cur = await tx.get(d.ref);
          if (cur.exists && cur.data().status === "pending") {
            tx.update(d.ref, {
              status: "unavailable",
              updatedAt: FieldValue.serverTimestamp(),
            });
          }
        })
      )
    );
  }
);
