/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */
require("dotenv").config();
const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const twilio = require("twilio");

admin.initializeApp();

const client = twilio(
  process.env.TWILIO_SID,
  process.env.TWILIO_TOKEN
);
exports.triggerTwilioAfter10Overspeed = functions.firestore
  .document("users/{userId}/overspeed_logs/{logId}")
  .onCreate(async (snapshot, context) => {

    const userId = context.params.userId;

    const logsRef = admin.firestore()
      .collection("users")
      .doc(userId)
      .collection("overspeed_logs");

    const logsSnapshot = await logsRef.get();
    const overspeedCount = logsSnapshot.size;

    console.log("Overspeed count:", overspeedCount);

    if (overspeedCount === 10) {

      console.log("🚨 10 violations reached. Triggering call...");

      await client.calls.create({
        to: process.env.TWILIO_TO,
        from: process.env.TWILIO_PHONE,
        url: process.env.TWIML_URL
      });

      console.log("✅ Call triggered successfully.");
    }

  });

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
