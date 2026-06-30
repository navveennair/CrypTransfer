<!-- converted from CrypTransfer_Sequence_Diagrams_v4.docx -->

CrypTransfer
Enhanced Sequence Diagrams (v4)
This revision redraws SD001-SD015 as UML sequence diagrams generated from the current CrypTransfer codebase (verified against lib/data, lib/presentation and lib/core sources). All diagrams are rendered in black and white only.

# SD001: Login Account



# SD002: Register Account



# SD003: Choose File



# SD004: Generate AES Key



# SD005: Encrypt File



# SD006: Generate RSA Key (Vault)



# SD007: Transfer File



# SD008: Receive File



# SD009: Decrypt File



# SD010: Cleanup Temporary Memory



# SD011: Generate and Transfer RSA Public Key (Mailbox Setup)



# SD012: Manage User Profiles



# SD013: Biometric Authentication Gate



# SD014: Silent Guardian Session Kill-Switch



# SD015: Zero-Remanence RAM Wiping Protocol


| Diagram ID | SD001 |
| --- | --- |
| Description | Username/email + password sign-in via FirebaseAuth, with a Google Sign-In alternative path and first-time-user onboarding branch. |
| Diagram ID | SD002 |
| --- | --- |
| Description | New account creation: username uniqueness check, FirebaseAuth user creation, and an atomic WriteBatch creating the user profile + preferences documents. |
| Diagram ID | SD003 |
| --- | --- |
| Description | Sender picks a file via file_picker after a pre-flight wipe of any previously held sensitive buffers (SecurityLifecycleMixin). |
| Diagram ID | SD004 |
| --- | --- |
| Description | AES-256 key and 96-bit GCM IV generation via PointyCastle FortunaRandom, invoked as part of encryptAesGcm(). |
| Diagram ID | SD005 |
| --- | --- |
| Description | Full sender-side encryption pipeline: FLAG_SECURE pre-flight check, 64 KB chunked file read via TransferService, AES-GCM encryption in a compute() isolate, and eager zero-wipe of the plaintext buffer. |
| Diagram ID | SD006 |
| --- | --- |
| Description | Biometric-gated RSA-2048 key vault: keypair generation in a compute() isolate, secure storage of the private key, and an atomic WriteBatch updating the public key plus key-manager audit trail. Includes the separate Delete Keys flow. |
| Diagram ID | SD007 |
| --- | --- |
| Description | Sender encrypts the AES key with the receiver's RSA public key (with a TOFU freshness re-check and biometric gate), then uploads the ciphertext to Firebase Storage and writes the transfer descriptor document to Firestore with progress streaming. |
| Diagram ID | SD008 |
| --- | --- |
| Description | Receiver-side reactive detection of an incoming transfer via a Firestore stream, automatic session locking, and navigation through the connection-establishing screen into the decrypt screen. |
| Diagram ID | SD009 |
| --- | --- |
| Description | Receiver downloads the ciphertext, unwraps the AES key with its RSA private key, performs AES-GCM decryption in a compute() isolate, writes the plaintext to a temp file, and runs a 120-second watchdog for connection-loss handling. |
| Diagram ID | SD010 |
| --- | --- |
| Description | Two-part zero-remanence cleanup: (A) the 'Save & Suicide' pattern that saves the file then wipes RAM/temp files, and (B) the synchronized four-turn session-end protocol between receiver and sender that deletes Firestore/Storage artifacts in a strict security order. |
| Diagram ID | SD011 |
| --- | --- |
| Description | Receiver opens its 'mailbox' (RSA keypair generation + publish to Firestore), the receiver explicitly authorizes a sender via an atomic handshake WriteBatch, the sender reactively detects the handshake with TOFU verification, and the mailbox-close kill-switch path. |
| Diagram ID | SD012 |
| --- | --- |
| Description | No dedicated profile-management feature exists in the current codebase. The closest implemented flow is Settings -> Appearance -> Theme, shown here, alongside a note on the profile-adjacent Firestore fields that currently have no edit UI. |
| Diagram ID | SD013 |
| --- | --- |
| Description | There is no app-launch biometric gate. BiometricHelper.authenticate() is invoked at three distinct points: RSA Key Vault entry (twice, defense in depth) and AES-key encryption before sending a file. |
| Diagram ID | SD014 |
| --- | --- |
| Description | Reactive kill-switch: any of (app backgrounded/killed, back navigation, manual mailbox close) drives SessionManager into the 'terminated' state, which EncryptionService.bindSession() picks up to atomically wipe Firestore key material, secure storage, handshakes and notifications, and write a security audit log. |
| Diagram ID | SD015 |
| --- | --- |
| Description | The SecurityLifecycleMixin buffer registry: registration of sensitive Uint8List buffers, the wipeAll() zero-fill sweep triggered from multiple lifecycle points, native FLAG_SECURE pre-flight checks, and the documented compute()-isolate remanence limitation. |