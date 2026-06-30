<!-- converted from Abstract_IURC2026_CrypTransfer.docx -->

CRYPTRANSFER - FILE TRANSFER USING HYBRID ENCRYPTION/DECRYPTION TECHNIQUE
(AES & RSA ALGORITHM)
Navveen Nair A/L Manoharan 1, Dr. Rashidah Binti Kadir 2
1Universiti Teknologi Malaysia, Jalan Iman, 81310 Skudai,
Johor Darul Ta'zim, Malaysia.
2Universiti Teknologi Malaysia, Jalan Iman, 81310 Skudai,
Johor Darul Ta'zim, Malaysia.



ABSTRACT
Mobile file-sharing platforms commonly expose sensitive data to interception and cryptographic remanence due to inadequate session security and server-side key handling. CrypTransfer was developed as a peer-to-peer secure mobile file transfer application employing a hybrid RSA-2048 and AES-256-GCM encryption scheme to ensure end-to-end confidentiality. The developed system was implemented using Flutter and Firebase, with all cryptographic operations performed exclusively on the client device. A receiver-authorized session model was designed, requiring an explicit atomic handshake before any key material or file data was exchanged. A reactive kill-switch mechanism was integrated into the developed system to purge public keys from the server, wipe private keys from local secure storage, and zero-fill in-memory plaintext buffers upon session termination. Biometric authentication, Android FLAG_SECURE enforcement, and an immutable audit trail were incorporated to further strengthen the security posture. Evaluation demonstrated that the developed system successfully fulfilled all encryption, zero-remanence, and session-isolation requirements across tested transfer scenarios.
Keywords: Hybrid Encryption; RSA; AES; Mobile Security; Secure File Transfer; Session Management
