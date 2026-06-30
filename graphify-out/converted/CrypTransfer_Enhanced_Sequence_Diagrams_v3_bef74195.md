<!-- converted from CrypTransfer_Enhanced_Sequence_Diagrams_v3.docx -->

SD001: Login Account

User              SystemController             Database
      |                      |                        |
      |--enterCredentials()-->|                        |
      |                      |----validate(creds)---->|
      |                      |                        |
      |                      |<---authStatus(valid)---|
      |                      |                        |
      |<---accessGranted()---|                        |
      |                      |                        |

SD002: Register Account

User              SystemController             Database
      |                      |                        |
      |---provideInfo()----->|                        |
      |                      |---checkUniqueness()--->|
      |                      |                        |
      |                      |<------unique(true)-----|
      |                      |                        |
      |                      |----createAccount()---->|
      |                      |                        |
      |                      |<----accountCreated()---|
      |                      |                        |
      |<---regSuccess()------|                        |
      |                      |                        |

SD003: Choose File

User              SystemController             FileSystem
      |                      |                        |
      |--selectFileRequest()->|                        |
      |                      |------openPicker()----->|
      |                      |                        |
      |                      |<----fileSelected()-----|
      |                      |                        |
      |<---displayFile()-----|                        |
      |                      |                        |

SD004: Generate AES Key

SystemController       EncryptionService
      |                            |
      |-----requestAESKey()------->|
      |                            |
      |                            |---generateRandomBytes()
      |                            |
      |<---------aesKey()----------|
      |                            |

SD005: Encrypt File

SystemController       EncryptionService
      |                            |
      |-------encrypt(file)------->|
      |                            |
      |                            |---aesGcmProcess()
      |                            |
      |<------encryptedFile--------|
      |                            |

SD006: Generate RSA Key

SystemController       EncryptionService         SecureStorage
      |                            |                        |
      |----requestRSAKeyPair()---->|                        |
      |                            |                        |
      |                            |---generateRSA(2048)    |
      |                            |                        |
      |<--------keyPair()----------|                        |
      |                            |                        |
      |-----------savePrivate(priv)------------------------>|
      |                            |                        |

SD007: Transfer File

SystemController       EncryptionService     FirebaseStorage         Firestore
      |                            |                    |                    |
      |---rsaEncrypt(aesKey)------>|                    |                    |
      |                            |                    |                    |
      |<-------encryptedAESKey-----|                    |                    |
      |                            |                    |                    |
      |-------putData(encrypted)----------------------->|                    |
      |                            |                    |                    |
      |<-----------downloadUrl------------------------------|                |
      |          [upload progress stream: 0.0 to 1.0]  |                    |
      |                            |                    |                    |
      |---transfers.set(encryptedAESKey, iv, downloadUrl)------------------>|
      |                            |                    |                    |
      |<-----------status(stored)-------------------------------------------|
      |                            |                    |                    |

SD008: Receive File

User             SystemController             Firestore         FirebaseStorage
      |                      |                        |                    |
      |--requestReceive()---->|                        |                    |
      |                      |                        |                    |
      |                      |---stream(transfers,--->|                    |
      |                      |   status==pending)     |                    |
      |                      |                        |                    |
      |                      |<----onSnapshot(doc)----|                    |
      |                      |   (encryptedAESKey,    |                    |
      |                      |    iv, encryptedFileUrl|                    |
      |                      |                        |                    |
      |                      |---download(encryptedFileUrl)--------------->|
      |                      |                        |                    |
      |                      |<---------------encryptedBytes---------------|
      |                      |                        |                    |
      |<--deliver(encryptedBytes, metadata)-----------|                    |
      |                      |                        |                    |

SD009: Decrypt File

SystemController       SecureStorage       EncryptionService
      |                            |                    |
      |----getRSAPrivateKey()----->|                    |
      |                            |                    |
      |<-------privateKey----------|                    |
      |                            |                    |
      |----decryptAESKey(key)-------------------------->|
      |                            |                    |
      |<----------aesKey--------------------------------|
      |                            |                    |
      |----decryptFile(file)--------------------------->|
      |                            |                    |
      |<---------plainFile------------------------------|
      |                            |                    |

SD010: Cleanup Temporary Memory

SystemController      SecurityLifecycleMixin       FileSystem
      |                            |                        |
      |-----wipeSession()--------->|                        |
      |   (via onBuffersWipe())    |                        |
      |                            |                        |
      |                            |---wipeAll()            |
      |                            |   fillRange(0) on all  |
      |                            |   registered Uint8List |
      |                            |                        |
      |                            |---clearRegistry()      |
      |                            |                        |
      |-----deleteTempFiles()------------------------------>|
      |                            |                        |
      |<-------status(secure)------|                        |
      |                            |                        |

SD011: Generate and Transfer RSA Public Key

User              SystemController       EncryptionService       Firestore
      |                      |                        |                    |
      |----openMailbox()---->|                        |                    |
      |                      |                        |                    |
      |                      |---setupReceiverSession(uid)------------>|   |
      |                      |                        |                    |
      |                      |                        |---generateRSA(2048)|
      |                      |                        |                    |
      |                      |                        |---savePrivateKey() |
      |                      |                        |   [FlutterSecureStorage]
      |                      |                        |                    |
      |                      |                        |---update users/{uid}|
      |                      |                        |   {publicKey,      |
      |                      |                        |   isReadyToReceive}|
      |                      |                        |                    |
      |                      |                        |<---status(stored)--|
      |                      |                        |                    |
      |                      |<----sessionReady()-----|                    |
      |                      |                        |                    |
      |<---mailboxReady()----|                        |                    |
      |                      |                        |                    |

SD012: Manage User Profiles

User              SystemController             Database
      |                      |                        |
      |----viewProfile()---->|                        |
      |                      |---fetchUserDetails()-->|
      |                      |                        |
      |                      |<-------userData--------|
      |                      |                        |
      |---updateProfile()--->|                        |
      |                      |-----saveChanges()----->|
      |                      |                        |
      |                      |<------updateOK---------|
      |                      |                        |

SD013: Biometric Authentication Gate

User              SystemController          BiometricModule        SecureStorage
      |                      |                        |                     |
      |--requestSensitive()->|                        |                     |
      |                      |---triggerBiometrics()->|                     |
      |                      |                        |                     |
      |---[Fingerprint/Face]-|                        |                     |
      |                      |                        |                     |
      |                      |<------authSuccess()----|                     |
      |                      |                        |                     |
      |                      |----accessKeyMaterial()---------------------->|
      |                      |                        |                     |
      |<---actionUnlocked()--|                        |                     |

SD014: Silent Guardian Session Kill-Switch

ReceiverSession       SessionManager        EncryptionService          Firestore
      |                        |                      |                        |
      |---wipeSession()------->|                      |                        |
      |  [toggle / back-nav /  |                      |                        |
      |   lifecycle trigger]   |                      |                        |
      |                        |                      |                        |
      |                        |---_set(terminated)-->|  [via stateStream]     |
      |                        |                      |                        |
      |                        |                      |---delete(publicKey,    |
      |                        |                      |  selectedSenderUid)--->|
      |                        |                      |                        |
      |                        |                      |---delete(privateKey)   |
      |                        |                      |  [FlutterSecureStorage]|
      |                        |                      |                        |
      |                        |                      |---batch.delete(handshakes WHERE receiverId)-->|
      |                        |                      |                        |
      |                        |                      |---writeAuditLog(kill_switch)---------------->|
      |                        |                      |                        |
      |                        |                      |  [Sender Firestore stream detects deletion   |
      |                        |                      |   → _revertToWaiting() — no push notification|
      |                        |                      |                        |
      |                        |---onBuffersWipe()--->|                        |
      |                        |                      |---wipeAll()            |
      |                        |                      |   fillRange(0, all     |
      |                        |                      |   Uint8List buffers)   |
      |                        |                      |---requestNativeClear() |
      |                        |                      |   [System.gc() hint]   |
      |                        |                      |                        |

SD015: Zero-Remanence RAM Wiping Protocol

SystemController       SecurityMixin          DartHeap (RAM)        NativeOS (GC)
      |                        |                      |                     |
      |---onDispose()--------->|                      |                     |
      |                        |                      |                     |
      |                        |---wipeAll()          |                     |
      |                        |   fillRange(0)------>|                     |
      |                        |                      |                     |
      |                        |---clearRegistry()--->|                     |
      |                        |                      |                     |
      |                        |---requestNativeClear() [fire-and-forget]-->|
      |                        |                      |   System.gc() hint  |
      |                        |                      |                     |
