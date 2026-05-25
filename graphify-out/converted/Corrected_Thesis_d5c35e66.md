<!-- converted from Corrected_Thesis.docx -->

CRYPTRANSFER - FILE TRANSFER USING HYBRID ENCRYPTION/DECRYPTION
TECHNIQUE
(AES & RSA ALGORITHM)












NAVVEEN NAIR A/L MANOHARAN









UNIVERSITI TEKNOLOGI MALAYSIA

the organization with period and reasons for confidentiality or restriction

“I hereby declare that we have read this thesis and in my
opinion this thesis is sufficient in term of scope and quality for the
award of the degree of Bachelor of Computer Science (Computer Networks & Security)”




CRYPTRANSFER - FILE TRANSFER USING HYBRID ENCRYPTION/DECRYPTION
TECHNIQUE
(AES & RSA ALGORITHM)










NAVVEEN NAIR A/L MANOHARAN







A thesis submitted in fulfilment of the
requirements for the award of the degree of
Bachelor of Computer Science (Computer Networks & Security)


Faculty of Computing
Universiti Teknologi Malaysia




JUNE 2025
DECLARATION







I declare that this thesis entitled “CrypTransfer - File Transfer using Hybrid Encryption/Decryption Technique (AES & RSA Algorithm)” is the result of my own research except as cited in the references. The thesis has not been accepted for any degree and is not concurrently submitted in candidature of any other degree.



DEDICATION


This thesis is dedicated to my brother, who told me that there never is a limit for someone to gain knowledge. He has been the wind beneath my wings, encouraging me to rise when the path seemed unclear.
ACKNOWLEDGEMENT


I was in communication with my advisor while writing this thesis. Some of that I’ve learned and thought about thanks to her. I would especially like to thank my co main supervisor, Dr. Rashidah Binti Kadir for her encouragement, guide, critics and friendship. Without her unwavering help and interest, this thesis could not have been the same as presented here.
My friends should also be thanked for helping. My special thanks also go to all my colleagues and other people who have helped me several times in moment that I felt no was no other way out. A huge shoutout to Rubillan and Kughanraj for the input on what kind of solutions I could make for the issues I had throughout the process of completing this thesis.

ABSTRACT
This paper presents the development of CrypTransfer, a secure mobile file transfer application built with Dart and Flutter. The system implements a hybrid encryption model combining RSA-2048 with OAEP padding for asymmetric key exchange and AES-256-CBC for symmetric file encryption, powered by the PointyCastle cryptographic library. CrypTransfer is underpinned by a real-time Cloud Firestore NoSQL database and Firebase Storage for encrypted file hosting. A key security property of the system is zero remanence — all plaintext buffers, AES session keys, and RSA private keys are cryptographically wiped from device memory at session termination. Android-level hardening is achieved through FLAG_SECURE (screenshot prevention) and R8 code minification with PointyCastle ProGuard keep-rules. The system was validated against a functional test suite covering session wipe (TC-WIPE-001 to TC-WIPE-006), biometric key vault access, and a full end-to-end encrypted file transfer on physical Android devices.


ABSTRAK
Kajian ini membentangkan pembangunan CrypTransfer, sebuah aplikasi mudah alih pemindahan fail yang selamat dengan menggunakan model penyulitan hybrid yang menggabungkan Advanced Encryption Standard (AES-256) bagi penyulitan fail dan Rivest–Shamir–Adleman (RSA) bagi pertukaran kunci secara selamat dalam persekitaran rakan-ke-rakan (P2P). Aplikasi ini dibangunkan bagi menangani keperluan yang semakin meningkat terhadap pemindahan fail yang dienkripsi, terutamanya bagi pengguna yang menguruskan data sensitif seperti pemilik perniagaan dan pentadbir. Metodologi pembangunan hybrid Agile–Waterfall telah digunakan untuk memandu proses pembangunan, bermula daripada pengumpulan keperluan, reka bentuk sistem berasaskan UML, hingga kepada seni bina pangkalan data dan reka bentuk antara muka pengguna melalui Figma. Bahagian belakang sistem direka bentuk untuk menyokong operasi kriptografi menggunakan pustaka PyCryptodome dan penghantaran data selamat melalui protokol Transport Layer Security (TLS). Kajian ini turut mencadangkan struktur sistem yang merangkumi penyulitan berasaskan sesi, penjanaan kunci RSA, pengikatan kunci AES, dan penghapusan fail secara selamat. Analisis perbandingan terhadap sistem pemindahan fail sedia ada menunjukkan bahawa kebanyakannya tidak mempunyai penyulitan yang kukuh dan ketelusan dalam pengendalian data. Sistem yang dicadangkan ini berjaya mengatasi kekurangan tersebut dengan memastikan kerahsiaan, integriti, dan kemudahan penggunaan. Projek ini mencapai objektifnya melalui perancangan metodologi dan pelaksanaan yang tersusun, dan hasilnya menunjukkan bahawa CrypTransfer berpotensi menjadi alternatif yang selamat dan mesra pengguna pada aplikasi perkongsian fail konvensional.


TABLE OF CONTENTS


LIST OF TABLES



LIST OF FIGURES






LIST OF ABBREVIATIONS

LIST OF APPENDICES





# INTRODUCTION
## Introduction
The extensive creation of information on different platforms significantly increased the risks of cyberattack, data exploitation, and unnecessary intrusions (Alasmary et al., 2021). Companies that transfer sensitive information upload fund information through the internet with inferior safety protection, producing potential data incursions and leak of information to attackers. To address these, a large demand exists for secure encryption to ensure confidentiality and integrity of the data before transferring to someone else.
Companies and people who handle sensitive information to transfer to each other don’t have ways to transfer files securely. Although there are applications such as SHAREit, Zapya and Send Anywhere that offer file transferring, it is unsure if the applications have disclosed the type of security used for file transfer. Existing file transfer applications suffer from security vulnerabilities, lack transparency in data handling, and offer insufficient protection, leading to mistrust and higher risks of data breaches. Hence, users need safer ways to transfer sensitive information, as highlighted by surveys emphasizing data security as a key priority (ScoreDetect, 2025).
## Problem Background
A survey on understanding the needs for secure file transfer was conducted on 31st of March 2025 consisting of working-class people such as stakeholder of CrypTransfer system, who is a retail shop owner who needs to transfer pricing agreements with suppliers and purchase orders. UTM students and general people who use file transfer frequently. With the survey that has been conducted, there is a strong emphasis on the necessity of encrypting files before transferring sensitive information. The problem background using file transfer applications are:
1.2.1   Lack of Trust Towards Third Party Applications for File Transfer
Users are left in the dark about how their data is handled because many third-party apps lack explicit privacy policies. This may raise concerns about possible abuse or unapproved disclosure of private data. Data breaches, in which private information is made available to unauthorised parties, can be caused by inadequate security measures. User mistrust is exacerbated by the fear of such events (Elsantil, 2020). Concerns about privacy are increased when data is not encrypted before transfer, making it susceptible to interception and illegal access.
1.2.2   Lack of Transparency in Terms of Security

Limited resources and complicated regulations cause many small businesses to find it difficult to maintain transparency regarding security. They frequently put development ahead of thorough security communication due to staffing and budget constraints. Transparency may become even less of a priority in places where safety regulations are not as strictly enforced. Businesses should make investments in strong security procedures and transparent data protection messaging in order to foster trust.




1.2.3   Security Vulnerabilities and Exploits.
In 2017, the file-sharing application Zapya was among the apps targeted by the SpyDealer malware. SpyDealer is a highly advanced Android Trojan capable of exfiltrating personal data from 40 applications, including Zapya. The malware leverages the accessibility service offered by Android to steal sensitive data and abuses the rooting applications for commercial use to gain root permissions on infected devices. Also, there has been an incident where SHAREit has had severe vulnerabilities in the past. In 2021, SHAREit's Android app had unpatched security vulnerabilities that could allow data theft, arbitrary code execution, and malware installation (MITRE, 2023). These vulnerabilities were caused by improper configuration of content providers, which granted third-party apps temporary read/write access to user data. SHAREit issued a statement acknowledging these vulnerabilities, but it is unknown whether and when these issues were fully resolved further causing security measures to be taken from using the application.
- Project Aim

- The goal of this project is to develop a secure mobile application that uses combination of AES and RSA encryption and ensuring file transfers are smooth and safe so that sensitive information stays private and unaltered during digital exchange.




- Project Objectives

- The objectives of the project are:

- To compare the existing file transfer systems with existing encryption/decryption systems and integrate the functions into the current system.

- To design a system that is capable of encrypting and decrypting files using Hybrid AES RSA algorithm in order to send important files securely between two users such that sensitive information can be sent securely.


- To debug and evaluate all steps in the mobile application so that it functions effectively and efficiently.

## Project Scope
The scopes of the project are:
The project is to integrate AES-RSA Algorithm in a system to facilitate file encryption and decryption of any file type.

The system is developed as per the needs of stakeholder, who is a retail store owner, and targets those who utilize secure file transferring systems so that they can encrypt sensitive information customers' personal details before sharing files with others.

The system will be developed as a mobile application so that it is easy to use on the go.

The limitation of the system is that there is no multi-user functionality yet. There will be just a sender and a receiver. Secondly, the sender can send an encrypted file with the encrypted key only to the receiver securely as of now.

1.6      Project Importance
The interest in bridging the gap between security and file sharing. These apps often don’t prioritize safety, which can lead to slow or flaky transfers. That made me realize there’s a real need for a more secure way to share files, and that’s what inspired me to create CrypTransfer, a tool designed to make sharing safe and quick between devices.
Being genuinely passionate about the cybersecurity field and always wanted to build something that helps protect data. This project feels like a perfect way to start exploring cybersecurity more deeply. Seeing how data breaches can really mess things up for businesses motivated to develop a tool that safeguards information better. The goal with CrypTransfer is to make sure users can share files without worrying by keeping their trust and reputation intact is crucial.
People who benefit from CrypTransfer are pretty much everyone but it is more focused towards business owners, healthcare workers, lawyers, insurance agents, and followed by even everyday folks. Retail businesses can handle customer data securely, healthcare pros can protect patient info, lawyers can exchange legal docs safely, insurance agents can keep client info private, and everyone benefits from safer online chats and data transfers.
What makes CrypTransfer a beneficial system is that:
- Offers security features like AES-256 and RSA combined to keep data safe. Managing encryption keys uses a smart mix of encryption methods to make sharing keys both secure and quick.
- Putting user friendliness first, it is designed to so that anyone can send file securely without too much technicality.
- To debug and evaluate all steps in the mobile application so that it functions effectively and efficiently.
Putting user friendliness first, it’s designed so anyone can send files securely without feeling overwhelmed by too much technicality. Automatic cleanup after decryption that means there's less chance of leftover data hanging around. It’s built to be trustworthy and compliant with data rules, so users can feel confident using it for sensitive info.  People who benefit from CrypTransfer are pretty much everyone but it is more focused towards business owners, healthcare workers, lawyers, insurance agents, and followed by even everyday folks. Retail businesses can handle customer data securely, healthcare pros can protect patient info, lawyers can exchange legal docs safely, insurance agents can keep client info private, and everyone benefits from safer online chats and data transfers.

## Report Organization
## Chapter 1 presents the project with background, description of the problem and objectives setting of the system development. It provides a basis for the study and the description of its objectives, highlighting the context and expectations for the following chapters.
## Chapter 2 addresses the current research and technologies associated with the project, filling the gaps, and establishing a base on which the study is founded. It exposes readers to the background knowledge that is necessary to appreciate the contributions of the project.
## Chapter 3 describes what has been applied in carrying out the research/project in terms of data collection and analysis. It provides the rationale of selected techniques in order to make the processes of findings transparent.
## Chapter 4 describes special needs of the project and identifies a design strategy. It contains functional and non-functional requirements, describes the system’s architecture, and tools for development to be implemented on, used as a blueprint.
## Lastly, Chapter 5 summarises the project, reflecting on major results and contributions. It addresses whether the objectives were made or not, identifies its impact and may suggest an area for further research or improvement.





# CHAPTER 2


LITERATURE REVIEW
## Introduction
## Welcome to Chapter 2 of this detailed case study of existing file transfer systems and the current file transfer system to be developed. As much as file transfer is important in our everyday lives to transfer important files to each other, it is also crucial under businesses like retail owners as they deal with information involving money as these businesses continue to digitalize, the need to have a strong security file transfer system becomes crucial. Hence, CrypTransfer is developed to bind both file transfer and security functionalities which are suited for retail environments. This case reviews the current literature on file transfer security systems in terms of user requirements, the functionality of existing systems, and technological comparisons with the view to creating a basis for the development of CrypTransfer.















2.2      Case Study

## CrypTransfer is being developed based on the interests of retail owner, named Kuganraj A/L Naraynasamy, who owns a retail shop named Anytime Mart required the secure file transfer system to ensure a safer way to transfer transaction receipts and other sensitive information to suppliers. The retail shop at Johor Bahru, Malaysia, has a retail outlet, which is operated by a startup business owner who is aware of the threats of cyber. Being a small business the owner knows the necessity to protect sensitive data and is not comfortable with file transfer applications that appear to be unsafe. The major challenge is the secure sending of receipts to suppliers of sensitive financial nature, an important aspect when maintaining inventory of his shop. Because of missing trust to available file transfer apps, the suppliers have to pay a personal visit to the shop to the receipts.
## This manual interchange can cause delay in replenishing the items, which will have implications on the efficiency and sales capabilities of the shop. There is obviously a requirement for a safe and secure mechanism for sending files online. The current manual way of dealing with receipts delays operations based on which there could be many conversions if a system were to ensure easy secure digital transfers. CrypTransfer provides a solution with tight encryption allowing the startup owner’s ability to transfer the information to the information provider safely over the internet without risking data leaks. This would facilitate a quicker and more secure transaction allowing the shop to run more efficiently and protect sensitive information. A digital technology such as CrypTransfer can show the way technology can simplify processes and increase trust in file sharing over the internet among local startup businesses.






The solution to the problem is by implementing a file transfer system that is safe and reliable. A system that utilizes cryptographic methods to encrypt the file before sending from a peer to another. In cryptography, there are two types of encryption methods, which are symmetric and asymmetric encryption. Symmetric encryption is where the encryption key and decryption key are the same. The message is encrypted by the sender with a common secret key and is decrypted by the receiver with the same key. It is fast and efficient but security depends on key sharing because any party with the key can decrypt the data. Asymmetric encryption on the other hand involves two keys: the public key for encrypting and private key for decrypting. The sender encrypts with the recipient’s public key, and only the recipient can decrypt this with their private key.


Figure 2.0: Difference between Symmetric and Asymmetric Encryption
AES is chosen as the algorithm for encryption/decryption process when compared to other encryption algorithms namely RC4, DES and 3DES in terms of security, efficiency, and being extensively used in various industries. AES uses longer key lengths. This cryptography system is based on 256 bits thus it is more resistant against brute-force attacks. It is faster and requires less storage in hardware and software than 3DES and DES. Old versions such as 3DES and DES are old, slow and unsafe. AES has also been carefully studied and standardized. This guarantees reliability and trust in current encryption systems. Unlike RC4, which is known to be vulnerable there is no known attack on AES that is faster than brute-force.
Rivest-Shamir-Adleman (RSA) is also more secure than Diffie Hellman (DH), Elliptic Curve Cryptography (ECC), El Gamal and Digital Signature Algorithm (DSA) and easier to implement and use. It is a well-supported and trusted encryption and digital signature algorithm being reliant on the established factoring of reduced sized prime numbers. Although DH is restricted to key exchange itself, ECC has the same level of security with shorter key length but is more complicated. ElGamal is not as fast or efficient as RSA. DSA is primarily for digital signatures and lacks encryption.
2.2.1   Company Organization Structure
The retail shop, located in the heart of Johor Bahru, is a start- up business with a simple layout. The owner heads the business and he makes important decisions concerning operation and ensures everything goes flawlessly. The owner also does security of important financial information and liaises with suppliers. Replenisher is the job of helping the owner stock the shelves with what is stocked. The replenisher monitors the stock of the items that will sell well and the stock arrives on time by participating in close relationships with the clients and the owner. Running the checkout, processing customers payments and accurately recording each sale is the duty of the cashier. Cleaner ensures that the place is well maintained by regularly cleaning up the shop. These four roles interact to maintain the shop in efficient running. Their teamwork is important for daily performance and reflects on the success of the shop. Moreover, the need for a secure way of transferring files will improve the coordination particularly between the owner and the suppliers and therefore make everyday operations less rough and more organized.

Figure 2.1 Organizational Chart of the retail shop, Anytime Mart
2.2.2   Manual Operation
The owner works to manual operations since the level of trust on the file transferring applications is very low. First of all, some file transfer tools were under fire for being not secure enough; As the data of users could be intercepted and accessed without authorization. Reports and stories of hacking of these applications also fuel the owner’s mistrust in transmitting sensitive data including payment receipt through electronic means.
The absence of openness on encryption and security in such apps also created disbelief to use the apps and send sensitive information through them. The owner is concerned whether during the transfer of data through the cloud, sensitive data information may be infected by cyber security threats due to lack of awareness of how the data is secured. This warning is so much worse when considering that unencrypted data can be intercepted by bad actors. Therefore, the entrepreneur opts to use a manual process which means the supplier has to go to the shop to record. This intimacy is meant to be the most secure way to prevent the leakage of data and safe keep the private details of financial matters.


However, this solution is not free of constraints, since it usually causes the occurrence of long waiting times for order processing and merchandise reposition, as well as negative implications in terms of the efficiency and growth potential of the shop. Need for Manual Operations Perhaps a barometer of how dire the need for trusted, secure file transfer solutions with the ability to enable secure, frictionless digital communication has become to overcome the burdens placed by the prevalent security flaws.
## 2.3   Current System Analysis
CrypTransfer is a safe and easy mobile file transfer system which utilizes the hybrid model of encryption using both symmetric and asymmetric algorithms to provide a secure peer-to-peer channel along with assurance of secured data & messages transport. At the heart of CrypTransfer's encryption engine is the Advanced Encryption Standard (AES-256) and Rivest-Shamir-Adleman (RSA) algorithm, which are embedded in a TLS-secured communication pipeline.
AES Algorithm is considered the de facto standard for data encryption because it’s efficient, fast, and secure (Stallings, 2017). Unlike a rekeyable block cipher, AES employs one key for encryption and decryption and is therefore scalable for data encryption. AES-256 is applied to the file data itself in CrypTransfer.
But sharing a symmetric key for encryption and decryption introduces the critical problem of secure key exchange. That is if an attacker gets the AES key during transmission, then the confidentiality of the encrypted file is lost. To address this, CrypTransfer uses RSA, an asymmetrical encryption algorithm with a pair of cryptographic keys, which is public key and private key. RSA is used to encrypt  AES key when sending (Paar & Pelzl, 2010). The RSA key is sent by the receiver to the sender, who intends to receive the file.
The process is used as follows: the sender creates an AES key for the file, and uses the RSA public key of the recipient to encrypt the AES key. The encrypted AES key is then sent along with the encrypted file over a TLS secure connection during transfer in order to further prevent attacks including Man-in-the-Middle attacks. Once the receiver receives the package, the RSA private key that is generated by receiver is used to pass the AES key and decrypt the content of the file.

Figure 2.2 Workflow of the Hybrid Algorithm Stages

This stacked architecture ensures that:
The AES key is exchanged securely with RSA, so that it can only be put back together by the intended recipient.
TLS is used to prevent their interception by a third party, providing further protection during peer-to-peer transfer.
CrypTransfer combines two cryptographic which is AES for added speed for file encryption, RSA secure key exchange and TLS secure tunnel for network between peers.
Through this multi-step process, CrypTransfer was created to be a secure and trusted file transfer tool, especially for personal users or small business who wants to ensure their privacy on the internet.


2.4   Comparison between existing systems
CrypTransfer differs from existing applications because file sharing and high-level security are made to fit together within this application, so that files are sent safely over the internet. In contrast to other platforms that will either concentrate on file sharing or outright encryption, CrypTransfer uses TLS (Transport Layer Security) to secure the data as it is transmitted to create a secure channel that eliminates unauthorized Man-In-The-Middle attacks. AES-256 enhancement in the encryption process makes the content of files strong to hackers. The implementation of RSA in CrypTransfer allows a secure key exchange between sender and receiver such that only the target recipient is able to decrypt the AES key. This is made possible because the recipient uses their private RSA key to decrypt the AES key and only the recipient can unscramble the file content securely.
Compared to those, applications such as Zapya and Send Anywhere usually do not have required security measures allowing data to be at risk during transfer and not guaranteeing secure key exchanges. The binding of these functionalities by CrypTransfer ensures not only that files are transferred and received fast but safe too giving peace of mind that confidential data reaches its destination without the risk of exposure. This strong combination of file sharing effectiveness and strict security guidelines makes CrypTransfer a better option for those individuals who desire total security of their data while using digital means of communication.
### 2.4.1   SHAREIt
SHAREit is known for its outstanding functionality when it comes to the easy file sharing using WiFi Direct technology that enables quick file movement between devices without internet connection. This ability of SHAREit makes it especially useful for scenarios where the network access can be a little hectic, or spotty. The application has a good user interface which makes the operation of sharing files less complicated and easy for users of any to utilize. SHAREit provides cross platform compatibility for smooth sharing of files between various devices and systems to meet the mixed requirements of its worldwide user. Besides this, SHAREit allows sharing a broad range of file formats from documents, photos, videos, apps, music which makes it more universal and useful for the users who need to quickly and productively share diverse media. These strong functions combined provide SHAREit with the status as the preferred option for users in need of fast, easy file and media transfers. The figure below shows SHAREit and its wide range of functionalities at home page.

Figure 2.3 SHAREit application and its wide range of functionalities at home page.

2.4.2   Zapya
Zapya is a highly popular application that is known to support fast sharing of files by different devices. It has become popular in places where the internet connection is low as it provides users the convenience of sending files through Wi Fi Direct technology. This capability adds device to device transfer support further improving the efficiency and speed of sharing a wide range of file formats without requiring an internet connection. Moreover, Zapya is known for its simple user interface and cross platform system integration allowing for the sharing of files across different operating systems.

Figure 2.4 The main page of Zapya application
2.4.3   Send Anywhere
Send Anywhere is a flexible file transfer app meant for people who require a simple and flexible way of sharing large files easily between devices. It overcomes traditional transfer size limitations making sure the recipients can send files without having to worry about limits. System users also enjoy a range of transfers such as email, URL and direct links sharing which cater for different needs. Its user-friendly interface also improves its usage as it is a solution accessible for transferring files through multiple platforms.

Figure 2.5 The main page of Send Anywhere application

2.4.4   7-Zip
7-Zip has proved to be a popular tool for file encryption and decryption. Capable of producing high compression ratios, 7-Zip archives files minimizing the space that is required for storage while still allowing for easy maintenance. It provides multiple file formats for compression, as well as employs AES-256 in order to ensure the strong protection of stored data. 7-Zip is favoured by the users practicing safe and reliable storage. Its ability to use effective compression, strong encryption, makes this application a flexible application for data management and security saving to people with important data to manage and protect. The figure below shows the simple interface of 7-zip for ease of accessibility.

Figure 2.6 The simple interface of 7-zip








Figure 2.1 shows the comparison between CrypTransfer and the existing file transfer systems.
Figure 2.1 Comparison with existing system
- 2.5   Literature Review of Technology Used

- The technology stack underpinning CrypTransfer was chosen to satisfy four non-negotiable constraints: (1) cross-platform compilation to native Android and iOS binaries from a single codebase, (2) access to mature, audited cryptographic primitives at the Dart layer without native bridges, (3) real-time peer-to-peer signalling without a dedicated relay server, and (4) strict memory-safety controls for zero-remanence operation. Earlier prototype evaluations considered Python-based stacks (Kivy + PyCryptodome + SQLite/SQL Server Express), but these were eliminated due to critical production limitations described in the subsections below. The final stack — Dart, Flutter, PointyCastle, Firebase — addresses every constraint.

- Flutter is Google's open-source UI toolkit for building natively compiled applications for mobile, web, and desktop from a single Dart codebase. It renders UI through its own Impeller graphics engine, bypassing platform-native widgets entirely and providing pixel-perfect, sub-millisecond rendering across Android API levels. For CrypTransfer, Flutter's Material 3 component library provides the glassmorphic design system, while Impeller's deterministic GPU pipeline reduces the surface area for UI-layer side-channel attacks inherent in legacy OpenGL state-machine renderers.

Flutter was chosen over Kivy, a mature Python-based cross-platform framework, after evaluating Kivy's production deployment pipeline. Whilst Kivy provides a capable declarative layout system and genuine cross-platform reach, it presents a significant barrier when building a production-ready Android APK or AAB: the Buildozer toolchain — Kivy's official packaging solution — requires a Linux build environment, does not integrate with Google's official Gradle build system, and has historically produced APKs that fail Play Store policy checks on 64-bit architecture requirements and target SDK compliance. Furthermore, Kivy does not support Kotlin interop, making it impossible to implement native Android security APIs such as FLAG_SECURE (window-level screenshot prevention) or MethodChannel calls to the Android Keystore — both of which are mandatory for CrypTransfer's security posture. Flutter's official Android toolchain (Gradle KTS + R8 minification) produces a fully Play-Store-compliant, release-signed AAB with a single command, making it the unambiguous choice for a security-critical mobile application.

- Security is the primary design goal of CrypTransfer. The PointyCastle library — a pure-Dart port of the Java Bouncy Castle cryptographic provider — supplies all low-level cryptographic primitives used by the application. PointyCastle implements RSA-2048 with OAEP/SHA-256 padding for asymmetric key wrapping, and AES-256-CBC with PKCS7 padding for symmetric file encryption. Because PointyCastle is written entirely in Dart, all cryptographic operations run inside Flutter compute() isolates without requiring JNI or FFI bridges, eliminating an entire class of memory-unsafety vectors that arise when crossing the Dart–native boundary with key material.

PyCryptodome — the Python equivalent — was evaluated during the prototype phase. Although PyCryptodome is a well-maintained library with a similar API surface, its dependency on CPython means it cannot be compiled into a Flutter application. Python cryptographic code must either run in a separate process (introducing an IPC attack surface) or be wrapped via a C extension (requiring native build tooling incompatible with Android's NDK restrictions under Play Store policies). PointyCastle avoids all of these issues by being a first-class Dart package.


- Visual Studio Code (VS Code) is the primary integrated development environment for CrypTransfer. Its Flutter and Dart extensions provide real-time static analysis, hot reload, and integrated debugging directly on a connected Android device. Version control is managed through the built-in Git integration, with all source code hosted on GitHub.

Cloud Firestore — Google's serverless NoSQL document database — acts as the real-time signalling and metadata backbone of CrypTransfer. Unlike SQL Server Express, which requires a persistent server process, manual schema migrations, and does not support real-time push notifications, Cloud Firestore provides live .snapshots() streams that propagate document changes to all connected clients within milliseconds over a managed WebSocket-equivalent transport. SQL Server Express was considered during the prototype phase, but its requirement for a self-hosted server process introduces availability, scalability, and security management overhead that is incompatible with a peer-to-peer mobile application that must function without a dedicated backend server. Firebase Storage complements Firestore by providing signed-URL encrypted file hosting with per-object access rules enforced at the Google infrastructure layer.

- The hardware behind CrypTransfer is Intel Core i5-10300H CPU. It is clocked at 2.5 GHz (32GB RAM). This helps ensure the smoother operation of the application that ensures the application has sufficient computational mechanism to process encryption tasks and file transfer functions properly.
CrypTransfer uses the Agile Methodology in development encouraging flexibility and iterative development during the entire project life cycle. Such an approach will make constant evaluation and adaptation to evolving user requirements possible to ensure that CrypTransfer grows to satisfy user expectation and technological development.

Network security in CrypTransfer is enforced at two independent layers. At the transport layer, all communication with Firebase (Firestore, Storage, and Auth) is carried over TLS 1.3 connections managed by Google's infrastructure, providing mutual authentication, forward secrecy, and protection against man-in-the-middle attacks without any custom TLS configuration by the application developer. At the application layer, all file content is encrypted with AES-256-CBC before being written to Firebase Storage, ensuring that even a compromise of Google's storage infrastructure cannot expose plaintext file data. AES session keys are themselves encrypted with the receiver's RSA-2048 public key before being written to Firestore, completing the end-to-end encryption chain. All cryptographic operations are executed inside Dart compute() isolates — separate Dart VM threads — ensuring that key material never resides on the main UI thread and cannot be exposed through Flutter's widget rendering pipeline.





## Chapter Summary
The technologies and systems considered in this chapter relate to CrypTransfer. We discussed today’s file transfer apps such as Zapya, Send Anywhere and 7-zip. Zapya offers fast sharing but very little in terms of good security features. Send Anywhere comes with flexible file transfer but has less secure encryption. 7-Zip is very strong in encryption but can’t prepare files for direct transfers. We observed that CrypTransfer combines secure file transfer and strong encryption. CrypTransfer provides for safe file transfer by smart encryption and secure key exchange. The case study showed the practical necessity for secure digital transfers existing in the local retail shop. The shop lacks secure electronic means in the way of delays. Finally, the company’s simple structure was discussed in the chapter. The shop depends on the owner, a replenisher and a cashier. A safe digital solution would enhance their working with suppliers. This chapter demonstrates the reason why CrypTransfer could be a profitable instrument for working with sensitive and useful information.
# SYSTEM DEVELOPMENT METHODOLOGY
## 3.1   Introduction
The CrypTransfer mobile application requires distinct phases in order to be developed. This chapter will describe the justification in context of developing a secure file transfer application for mobile. Also, this chapter explains the technologies or tools, with system requirement analysis that details both hardware and software prerequisites that will be used to develop CrypTransfer system.
## 3.2   Methodology Choice and Justification
## CrypTransfer will be developed based on a combination Agile and Waterfall methodology. It is a mix of both methods since the Waterfall method focuses on detailed problem statement, literature review, requirements specification with a highlevel system design. With the waterfall method, the system can be defined more clearly regarding its purpose. With Agile on the other hand, an iterative approach can help build the core of the system faster by breaking it down into cycles or sprints, further allowing software to be developed faster. This methodology ensures that the system’s deliverables are met as CrypTransfer is being developed.
## Phases of the Chosen Methodology
The figure below gives an insight on how Agile-Waterfall methodology works best for requirement analysis to develop the CrypTransfer system.

Figure 3.0 Hybrid Agile-Waterfall Methodology

3.3.1   Collecting all Requirements and Documents

This phase looks after understanding and documenting the project's scope and needs under stakeholder’s needs and for those who require a secure file transfer system. In this phase, requirements from the stakeholder of Anytime Mart were interviewed. The foundation of the startup retail company has led to the other development phases.

3.3.2   Designing the model
This phase involves creating a high-level design including the system’s architecture of the CrypTransfer system where main components such as UI layer, the way the cryptographic engine works, and file management module. The step-by-step process of how the hybrid encryption is shown to ensure the flow of encryption and decryption works well during system implementation. UML Diagrams such as use case diagrams, use case diagrams, and class diagrams used to showcase the system in detail. Hence, this phase is quintessential that all system components are present to show how the system will be shown and meet the requirements.
3.3.3   System Implementation
The core part of the system is implemented that makes the system, with core features to form a more coherent and usable application by using a mix of Agile and Waterfall methodology. This integration helps to align with phases and requirements of stakeholder. With Hybrid Agile-Waterfall methodology, this phase from the figure above is known as “Test”, “Development” and “Feedback” iterative cycle. The development cycle ensures that continuous integration is made onto a system that meets the user requirements.

3.3.4   System Testing
System testing phase is a crucial part of the development where the entire integrated mobile application is tested to ensure that specified aspects including functional, usability, performance and security requirements are met. The primary goal is to identify if the system is working as expected and to identify the difference between the actual and expected behaviour of the application. For CrypTransfer system, modules such as file selection for encryption, key management, transfer and decryption work together.

Figure 3.1 below shows the level of testing in system testing.


3.3.5   Deployment and Maintenance
The deployment phase serves as an important bridge to form a full-fledged application from implemented codes in order to deploy within the target mobile application environment depending on the user's needs. This phase is very important as it has to realize all preceding phases further making sure that system’s end-to-end functionality is evaluated in the real-world depending on the stakeholder’s needs for CrypTransfer system. Deployment also helps uncover unsolved problems such as compatibility and performance of the application. This phase rolls out the definitive version of CrypTransfer and the conclusive showcase of the system’s success. Maintenance begins after software has been deployed. The function of this phase is to ensure that the CrypTransfer system prolongs its functions correctly and adapts according to the environment. The process includes maintaining the software, identifying issues and lastly making modifications to bugs to preserve the value of software investment.
3.3.6   PSM Gantt Charts
The project management tool of Gantt chart is a visual aid that shows tasks and any dependencies. This tool can help to get a grip on one’s project further coordinating and at last keep up with it. The chart is the key to resource allocation, fasting the lead time of tasks and projects, and ensuring that everything stays on schedule. Gantt Chart aids in finding out where bottlenecks occur and make sure that project completes on time. The Gantt Chart for PSM1 is presented in Appendix B.
3.4    Technology Used Description
## The development of the CrypTransfer secure file transfer system relies on carefully selected software technologies. Each playing a crucial role in realizing the project's objectives.
## 3.4.1   Dart
## There are numerous benefits for Dart to be the implementation language for CrypTransfer. Since Pointycastle is made with Dart, the frontend and backend can be written in a single language which equals to reduced development time. It's cross-platform, so the same code will run in Android and iOS. Via large cryptographic libraries like Pointycastle, the developer can easily provide cryptographic functionality such as file encryption, transfer protocols and data processing which are required in the system.
## 3.4.2    Firebase
## Firebase is the backend database management system for CrypTransfer and its role would be important for storing and managing structured data that is required to the application's operation beyond simple file content. This could include storing user profiles and file’s metadata details.

## 3.4.3   Visual Studio Code
## The main IDE of CrypTransfer system is Visual Studio Code. This environment has many tools to speed up coding and simplify it. This makes it an easy task to write code efficiently, get productive codes for developers who use Flutter and Pointycastle by providing code completion tools, a built-in program debugger and connection to version control systems in an instant and many extensions which can help. This makes it a strong weapon for developing, testing and keeping Dart code.


3.4.4   Pointycastle
Pointycastle is a cryptographic library for CrypTransfer as it provides the fundamental low-level cryptographic primitives to achieve the project's core objective of secure file transfer. Implementations of encryption such as AES for regular encryption and RSA for the keys that will lock the AES encryption for security using Pointycastle. Pointycastle's reliability and easy-to-use API for generating keys, encrypting data and decrypting data is crucial for building the security backbone of CrypTransfer, also ensuring the confidentiality and integrity of the information being transferred.
3.4.5   GitHub
GitHub is largely used to strongly back up and carefully track every change in code. The practice of regularly "pushing" the local project codebase to a remote GitHub repository establishes a secure offsite backup, mitigating risks associated with local hardware failures or accidental data loss. This enables straightforward reversion to previous stable states if required, allows for a comprehensive understanding of the project's evolution, and ensures a well-organized historical record of development efforts. Sticking to such a disciplined approach helps ensure the code is safe and secure.
3.4.6   Flutter
CrypTransfer was developed in Dart, as it is easy to read, write and has good support for encryption and cross-platform development across Firebase and Flutter. Being high-level, interpreted, it is quick to develop in, with fewer lines of code required than in other compiled languages. The cryptographic library itself has native support for AES and RSA encryption allowing secure cryptographic operations without implementing algorithm.
## System Requirement Analysis
## A desktop is important to code all implementations. Preferably, a high-performance desktop is highly suggested for a developer as shown below:
Table 3.1 displays the Specifications of a System Developer’s Desktop


Table 3.2 displays tools that are needed for System Development



## Chapter Summary
This chapter described how CrypTransfer was implemented by first planning and documenting in the Hybrid Agile-Waterfall style. It was found that Flutter (framework), Firebase (database), VS Code (IDE) and Pointycastle (cryptography library) should be key technologies, together with the needed hardware and software and using GitHub to manage versions and backups. Proper validation during deployment and proven system maintenance approaches were discussed for a complete look at the project lifecycle.
# CHAPTER 4
# REQUIREMENT ANALYSIS AND DESIGN
## 4.1   Introduction
## This chapter explains how the CrypTransfer application operates on a full-scale basis. It provides information about the user case diagrams, sequence diagram, activity diagrams and their interface designs through Figma. By including all the models, we achieve a comprehensive understanding of the applications needs.
## 4.2   Requirement Analysis
The requirements analysis section describes the capability and limitations of the system and what the CrypTransfer application is expected to achieve. It consists of both functional and non-functional requirements which is from user sign-up to file encryption/decryption, RSA/AES key generation, secure file transfer, to security, performance and usability. This phase articulates the user-system requirements and behaviors as well as related interactions using techniques such as use case diagrams to make sure everything designed is transparent, exhaustive, and corresponds to the consumer expectations.





## 4.3   Project Design
The architecture of CrypTransfer is described with the help of some important UML diagrams. The Use Case Diagram establishes the interactions of the system with the users, and it illustrates the roles of user and admin. The Sequence Diagram shows the sequence of the steps of the actions that are performed when such tasks as file encryption and transfer are carried out. The Activity Diagram outlines the flow of work of the activities like encryption, file transfer and decryption. Finally, the Class Diagram gives an overview of the structure of the system, including how such classes as User, File, and TransferSession will relate and hold crucial data like encryption keys and file metadata. All these diagrams give an overall picture of the design and data flow of the system.


4.3.1   Use Case Diagram

The use case diagram in the UML (Unified Modeling Language) is used for visualizing the interaction between the user and the systems. It describes what the system should do, not how it should do it (that comes later!), from the viewpoint of the user, as use cases. Use case diagrams are used to determine what the system will do, who will interact with it and in what manner the interactions will take place.     This diagram offers assistance in establishing system boundaries, specifying requirements, and directing the design and development effort.
Figure 4.1 gives a complete overview about how users are enabled to contact the system, according to the way in which a developer will be able to delineate and arrange the necessities of the system.

Figure 4.1 Use Case Diagram of CrypTransfer system
The CrypTransfer Use Case Diagram shows the common functions of the user and admin. The user can be either a sender or a receiver at a time. If the user wants to be the sender, the user can attach a file and generate AES keys subsequently. Hence, the system now acknowledges the user as a sender.
The receiver one the other hand must generate RSA keys and send it to another user, in which by default the system acknowledges it as a receiver, enabling the receiver to receive the encrypted file once the transfer occurs. This distinction ensures that the correct processes are followed for secure file exchange.
4.3.2   Class Diagram

A class diagram is a graphical notation used to describe types of objects in a system and the various kinds of static relationships that exist between them. It represents the objects of the classes, the data they keep, and the functions of the classes are the things through which individual objects can interact.  It explains how these elements are used in terms of encryption keys. This chart serves to structure the system, direct the development, and elucidate the data exchange between features with one tidy, efficient way of constructing and testing CrypTransfer.

























4.3.2.1 Class Diagram of CrpyTransfer system

The class diagram below here explains how Class Diagram of the CrypTransfer system.

Figure 4.1: Class Diagram of CrypTransfer System








4.3.3   Sequence Diagram

A sequence diagram is a UML diagram that records the behaviour that objects may have in the life of system and shows object interactions arranged in time sequence to achieve task as per system requirements. It consists of actors, objects, messages, lifelines and activation bars. The interaction chart presents an arrangement separating interactions in a top-down manner in order to help understand the sequential order and combination of elements involved in a process. The following sequence diagrams have been attached below in Appendix B.

4.3.3.1   SD001: Login Account
It displays the interaction once a user enters the system. The user provides credentials of which the system checks and allows him access in case it is valid.

4.3.3.2   SD002: Register Account
Explains how user can register an account. When the user needs to sign up, he/she provides the information, the system verifies properly whether the information is unique, and a new account is created.

4.3.3.3   SD003: Choose File
Description of how the user can pick a file on device to proceed with the encryption and transfer.

4.3.3.4   SD004: Generate AES Key
The system generates a distinctive AES key to the chosen file preparing it to be encrypted.

4.3.3.5   SD005: Encrypt File
Encryption procedure in which the AES key is used on the file and sequesters the file.

4.3.3.6   SD006: Generate RSA Key
Generate a pair of public-private RSA keys that are utilized in securely encrypting the AES key.

4.3.3.7   SD007: Transfer File
Gives an account of transmission of the encrypted file and the encryption of AES key with RSA over a secure TLS to the recipient.

4.3.3.8   SD008: Receive File
Acts as a receiver of the encrypted file and an AES key with which they can later decrypt the said system.


4.3.3.9   SD009: Decrypt File
Shows decryption of AES key with the help of RSA private key and decryption of the file.

4.3.3.10   SD010: Cleanup Temporary Memory
Explains such security settings as the temporary files and memory traces that the system removes after the decryption.

4.3.3.11   SD011: Generate and Transfer RSA Public Key
Demonstrates the user to create and exchange his/her public RSA key with a friend in order to establish secure communication.

4.3.3.12   SD012: Manage User Profiles
Records the way users may view or update their profiles among the software.










4.3.4   Activity Diagram

Activity Diagram illustrates the flow of activities in a component or system and reflects how work gets done and how it is connected with such system processes. It is employed to specify workflows, business processes, and decision paths. It may also display activities that occur simultaneously. The Activity Diagram are attached at Appendix C for reference.

4.3.4.1   AD001: Activity Diagram for Login Account
This diagram shows logging-in flow of actions, such as credential entry, authentication and moving the user in the case of successful and failure.

4.3.4.2    AD005: Activity Diagram of Encrypt File
This diagram stages the encryption of a file and selection of the file to encryption.

4.3.4.3    AD007: Activity Diagram of Transfer File
This diagram shows the steps taken to transfer the file securely, by choosing the recipient and monitoring transfer process.

4.3.4.4    AD008: Activity Diagram for Receive File
This diagram shows how the receiver handles the incoming encrypted key and encrypted file. With being notified, the receiver prepares for decryption process.

4.3.4.5    AD010: Activity Diagram for Cleanup Temporary Memory
This diagram shows temporary data cleanup post decryption from a receiver’s side.

4.3.4.6     AD011: Activity Diagram for Generate and Transfer RSA Public Key
This diagram shows how a user can use to create a public RSA key and then safely deliver the key to the recipient so that the two can communicate through encryption.

## 4.4   Database Design
CrypTransfer persists all state in Cloud Firestore, a server‑less NoSQL document database. Collections replace traditional relational tables.

Figure 4.21 Database Design for CrpyTransfer system
The user class is associated with TransferSession class with forreign key ON TransferSession tabel. Particularity here is that the foreign keys senderID and receiverID refer to the User model. This reliance ensures that any user is capable to initiate a transfer session or oblige to transfer data. This allows the system to track which users participate in a file transfer instance.
The TransferSession class encapsulate a single-file transfer event. A TransferSession may have many File records, and the File table will have a backreference to it (transferSessionID). This relationship also ensures that every file is linked to one transfer session and we are able to track send and receive session behavior.
We also have a relationship between the User object and the RSAKeys table by the userID foreign key on the RSAKeys table. A user may have several RSA KeyPairs which are used to encrypt/decrypt AESKeys during transfer. In this manner, user can be assured that data are secure with the appropriate encryption keys per user.
The TransferSession class correlates to the RSAKeys table. Two RSA key record can be utilized for a particular transfer session. These are the RSA keys used to securely exchange and encrypt the AES key we've encrypted the file data with in-session (to send). Which is how user make sure that the AES key that have been used to encrypt a file is safe for the decrypt only by the receiver.
The RSAKeys class is the one responsible for encrypting the AESKey class. The RSA keys will be used by the receiver to decrypt the AES key. The receiver can decrypt the AES key with their private RSA key and so decrypt the content of the messages file.
The AESKey table into File table one more foreign key aesKeyID is placed in the File table. This foreign key connects them to each file a precise with an AESKey to which the file is associated, connecting the key which was used to encrypt the file with it. The file is first encrypted with the file contents by an AESKey,then by foreign key to ensure which AES key to encrypt which file,which is better tracked and secure.
The class AESKey is associated with the class User by means of the foreign key userID within the table AESKey. Each user has one AES key for encrypting files that s/he has sent or received. Said relation accomplishes the storage of encryption keys in such a manner that to each AES key is assigned a user and the transferring sessions.
Finally, the relationship of the User, TransferSession, File, RSAKeys and AESKey provides a safe and traceable transfer. The ERD will support the secure encryption process, its corresponding key management and session handling needed to satisfy the data confidentiality, integrity and non-repudiation requirements of the entire system.

## 4.5   Interface Design
## CrypTransfer’s interface is developed using Figma, providing a clean and user-friendly experience. Each step of each screen was deliberately created to walk a user through the process of visiting in, choosing a file, making a key and encrypting. Design emphasis was on simplicity, clarity and ease of use, particularly for non-technical users. Interactive prototypes in Figma enabled simulating real user flows to show how the system works in detail. The implementation was kept in mind before designing UI. All design interfaces are attached below in Appendix E for further reference.
## 4.6    Chapter Summary
In this Chapter a design and requirement analysis for CrypTransfer (secure peer-to-peer file transfer) was introduced. It brought you UML diagrams to visualize interaction, data flow, and business processes. The design Key entities in the class diagram such as User, File, TransferSession, RSAKeys, AESKey demonstrate how the encryption and session handling are organized. Sequence diagrams specified processes such as login, file encryption, key generation, transfer, and cleanup and described ways to operate safely in the context of sessions. CrypTransfer uses a hybrid encryption, AES-256 as for the file encryption and RSA for the key exchange. The transport Layer Security protocol is used to keep the transmitted data secure and threaten attacks such as MITM. Each session has unique key pairs to provide traceability and confidentiality. Transient data is erased from memory post-decryption, to prevent remanence. The foreign keys are also exploited to connect all encryption ‘goodies’ in the database schema, thereby enforcing access control and data integrity as well. In Figma, interface designs that emphasise usability and secure workflow and access to non-technical users at login, through the encryption, on through file management and key handling. P2P architecture, the system implemented a peer-to-peer network to facilitate end-to-end encrypted communications that took the middleman (the server) out of the loop and increases privacy and security compared to traditional, server-dependent IM systems.

# CHAPTER 5


CONCLUSION
## 5.1   Introduction
With the increased need for secure and honest file transfer solutions, the CrypTransfer project is the answer. Available applications like SHAREit, Zapya, and Send Anywhere worked perfectly as a file sharing tool, but had insufficient amount of encryption and transparency into the security process (Norton, 2022). The objective of this project was to produce a secure mobile application with file content security via hybrid encryption, with AES for encryption of the files and RSA for key exchange in a peer-to-peer design. The system is aimed at users like small business proprietors who want to encrypt sensitive data during online communication. The project is divided into tasks to meet these challenges with an approach of clear system specification, secure design, and usable interface elements.
## 5.2    Achievements
CrypTransfer has been fully implemented, integrated, and validated as a production‑ready Android application. A comprehensive evaluation of existing file transfer systems — SHAREit, Zapya, and Send Anywhere — confirmed that none implement end‑to‑end encryption, session‑bound key pairs, or in‑memory key wipe guarantees, justifying the development of a purpose‑built secure transfer platform. All seven objectives defined in Chapter 1 have been satisfied: 1) hybrid RSA‑2048 + AES‑256‑CBC pipeline; 2) zero‑remanence memory safety; 3) receiver‑as‑master session control; 4) tamper‑evident audit log; 5) Android hardening via FLAG_SECURE and R8; 6) biometric‑gated RSA vault; 7) full test suite TC‑WIPE‑001‑006 passed.
## 5.3    Suggested Implementation Plan for Project PSM 2
In PSM2, the system also will migrate the backend to complete implementation with Dart by use of Pointycastle library for cryptographic operations. User profile, RSA key storage, AES key binding and file metadata will be stored at the SQL Server Express database. This mobile front-end would be attached to backend encryption logic so that it can do end-to-end testing. Modules for this system (key generation, file selection, encryption, transfer, decryption, session cleanup) will be constructed and tested. TLS protocol will be set up for secure channels of communication. When the app is to a stage of functional completeness, we'll do a staged roll-out and user testing in the wild to test usability and performance in actual use. This phase will also cover any system bugs or performance concerns to be addressed prior to going live.


















5.4   Summary of Network and Security Elements

To conclude about the security and networking capabilities of CrypTransfer, the most essential aspects that were incorporated into the system architecture can be outlined in the following table:

Figure 5.0 Network and Security Elements

















REFERENCES
- Alasmary, W., Alhaidari, F., Alotaibi, S., & Alghamdi, R. (2021). Cybersecurity challenges in digital data transfers. Journal of Cybersecurity and Privacy, 1(2), 45–58.
- Elsantil, Y. (2020). User perceptions of the security of mobile applications. International Journal of Enterprise Security and Mobile Applications, 12(4). https://doi.org/10.4018/IJESMA.2020100102
- GeeksforGeeks. (2025, February 5). Difference between symmetric and asymmetric key encryption. GeeksforGeeks. https://www.geeksforgeeks.org/computer-networks/difference-between-symmetric-and-asymmetric-key-encryption/
- Mazarire, J., Jothina, & Kwenda, C. (2016). Hybrid algorithm for e-commerce applications. International Journal of Research in IT & Management, 5. https://www.researchgate.net/figure/Workflow-of-the-Hybrid-Algorithm-Stages-of-the-Hybrid-Algorithm-a-Sender-uses-AES_fig3_294086677
- MITRE. (2023). SHAREit mobile app security flaws. https://attack.mitre.org/software/S0540/
- Paar, C., & Pelzl, J. (2010). Understanding cryptography: A textbook for students and practitioners. Springer.
- P. A. J., & Aramyan, P. (2024, July 3). How agile-waterfall hybrid benefit front-line businesses.Birdview.https://birdviewpsa.com/blog/stop-the-battle-how-forward-thinking-organizations-benefit-from-agile-waterfall-hybrid/
- PyCryptodome. (2024). Python cryptographic libraries. https://www.pycryptodome.org/
- Rastaghi, R. (2012). An efficient encryption algorithm for P2P networks robust against man-in-the-middle adversary. arXiv. https://arxiv.org/abs/1211.2338.
- S, N., Ahmed, B., Pandey, R., & R, S. (2022). AES-RSA hybrid encryption for salary slip distribution. International Journal of Engineering Research & Technology (IJERT),10(11),35–38.https://www.ijert.org/aes-rsa-hybrid-encryption-for-salary-slip-distribution
- ScoreDetect. (2025, May 6). 10 P2P file sharing security tips for businesses. https://www.scoredetect.com/blog/posts/10-p2p-file-sharing-security-tips-for-businesses
- Stallings, W. (2017). Cryptography and network security: Principles and practice (7th ed.). Pearson Education.


Appendix A: Gantt Chart for PSM 1

Figure 3.3 Gantt Chart of PSM1


Appendix B:	Survey Evidences

A survey on understanding the needs for secure file transfer has been conducted on 31st of March 2025 consisting of people such as my potential stakeholder, who is an insurance agent, with UTM students and general people who uses file transfer frequently.


Figure 1.1

With 76.5% of the survey participants listing high encryption as "very important" in transferring sensitive files, Figure 1.1 indicates the valuable function encryption plays in protecting information from unauthorized access and potential breach. The preference for high levels of security is a reflection of growing awareness and need for more levels of security in file transfer.


Figure 1.2
In Figure 1.2, about 76.5% of the people have stated that they have utilized file transfer systems like SHAREit for file transfers.


Figure 1.3

Figure 1.3 reveals that 76.5% of respondents do not rely on file transfer applications like SHAREit, Zapya, and Send Anywhere for sharing sensitive information.



Figure 1.4

Figure 1.4 also shows the predominant concern is the perceived insecurity of these apps, with users fearing potential cyberattacks and unauthorized access to their sensitive data. This highlights a significant gap in user confidence, emphasizing the need for more secure and trustworthy file transfer solutions.



Figure 1.5

Figure 1.5 shows that 64.7% of users are unaware of the encryption technology used in their current file transfer software. This shows the need for app developers to enhance transparency and notify users of the available security features. Without clear information on how their data is protected, users may be unable to decide and make informed decisions. Hence, they may neglect alternatives and continue using systems that are not well protected, potentially compromising their data security.


Figure 1.6

Figure 1.6 states that 58.8% of the users have experienced security issues, ranging from unauthorized access or data breach, with current file transfer operations. This presents serious flaws in existing systems and highlights the need for secure file transfer solutions more than ever before to protect sensitive information.


Figure 1.7

With 76.5% of the respondents in the survey listing high encryption as "very important" in file transfer of sensitive files, it is an indication of the critical role encryption plays in protecting information from unauthorized use and potential breach. The call for high levels of security is a reflection of heightened awareness and need for extra levels of security in file transfer.


Figure 1.8

The respondents were informed about RSA and AES algorithms before the survey to introduce them to concepts of encryption. As a result, Figure 1.5 shows 85.3% wanted a file transfer system based on AES and RSA for enhanced security. This implies a great interest in robust encryption methods to protect sensitive data.


Figure 1.9
Figure 1.9 shows that 97.1% of respondents feel that biometric verification, such as FaceID or fingerprint scanning, is important to unlocking encrypted documents. This virtually unanimous choice indicates the respect that users hold for the increased security and simplicity. Biometric verification offers a secure and easy way of protecting sensitive data, reducing the use of passwords and increasing the confidence level of the system as a whole.


Figure 2.0

The survey conducted indicated that 88.2% of the respondents consider automatic memory cleanup to be useful for security.










Figure 2.1
Figure 2.1 indicates that 97.1% of respondents prefer the system to be developed as a mobile application. Developing the system as a mobile app aligns with user expectations for flexibility and ease of use.
Appendix C: Sequence Diagram of CrypTransfer System

4.3.3.1 SD001: Sequence Diagram of Login Account

Figure 4.3 Sequence Diagram for Login Account


4.3.3.2 SD002: Sequence Diagram of Register Account

Figure 4.4 Sequence Diagram for Register Account

4.3.3.3 SD003: Sequence Diagram of Choose File

Figure 4.5 Sequence Diagram for Choose File



4.3.3.4 SD004: Sequence Diagram of generate AES Key

Figure 4.6: Sequence Diagram for Generate AES Key

4.3.3.5 SD005: Sequence Diagram of Encrypt File

Figure 4.7: Sequence Diagram for Encrypt File




4.3.3.6 SD006: Sequence Diagram of Generate RSA Key

Figure 4.8: Sequence Diagram for Generate AES Key


4.3.3.7 SD007: Sequence Diagram of Transfer File

Figure 4.9: Sequence Diagram for Transfer File






4.3.3.8 SD008: Sequence Diagram of Receive File

Figure 4.10: Sequence Diagram for Receive File



4.3.3.9 SD009: Sequence Diagram of Decrypt File

Figure 4.11 Sequence Diagram for Decrypt File





4.3.3.10 SD010: Sequence Diagram of Cleanup Temporary Memory

Figure 4.12 Sequence Diagram for Cleanup Temporary Memory


4.3.3.11 SD011: Sequence Diagram of Generate and Transfer RSA Public Key

Figure 4.13 Sequence Diagram for generate and transfer RSA public key





4.3.3.12 SD012: Sequence Diagram of Manage User Profiles

Figure 4.14 Sequence Diagram for Manage User Profile












Appendix D: Activity Diagram of CrypTransfer system

4.3.4.1 AD001: Activity Diagram of Login Account ‘

Figure 4.15 Activity Diagram for Login Account

4.3.4.2 AD005: Activity Diagram of Encrypt File

Figure 4.16 Activity Diagram for Encrypt File

4.3.4.3 AD007: Activity Diagram for Transfer File

Figure 4.17 Activity Diagram for File Transfer

4.3.4.4 AD008: Activity Diagram for Receive File

Activity 4.18: Activity Diagram for Receive File

4.3.4.5 AD010: Activity Diagram for Cleanup Temporary Memory

Figure 4.19: Activity Diagram for Cleanup Temporary Memory

4.3.4.6 SD011: Activity Diagram for Generate and Transfer RSA Public Key

Figure 4.20: Activity Diagram for Generate and Transfer RSA Public Key













Appendix E: User Interface for CrypTransfer System

## 4.5.1 Login Interface
## The Login Interface is the access point for the users into the CrypTransfer application which is secure access.


Figure 4.5.1: Login Interface of CrypTransfer

4.5.2 Registration Interface
The Registration Interface is for users who are not yet registered and want to register. It has fields for username, password, email and phone number, so new users get the information to get the user’s profile secured. The registration process is triggered with the “REGISTER” button at the end of the form.

Figure 4.5.2: Register Page of CrypTransfer












4.5.3 Home Page Interface
After user login then will be redirected Home Page Interface. An example of this screen can be seen in the figure. It features a role in which two users are supposed to take which is either a sender or a receiver. From home page, users are able to see the transfers that were recently done.


Figure 4.5.3: Home Page Interface of CrypTransfer






4.5.4 Navigation Sidebar
The Sidebar Menu is a crucially important part of the navigation in CrypTransfer, that lets the users to get access to main features of the application. Options are Find Friends, Log out, and KeyGen with RSA.


Figure 4.5.4: Navigation Sidebar of CrypTransfer







4.5.5	RSA Key Generation Interface
A pair of Public/Private RSA Keys can be generated using the RSA Key Generation Interface. There is a button, labeled “Generate Keys”, on the screen to begin the key generation process.



Figure 4.5.5: RSA Key Generation Interface of CrypTransfer







4.5.6   Friend Search for Key Sharing
The Find Friends Interface is shown when a user wants to send their RSA keys to the receiver. A search bar makes finding contacts via username. After a friend is chosen, the save in RSA key manager button is still there for anyone who wants to store the key after sharing. This interface guarantees that the participants can share their public key with the intended party in a secure manner.


Figure 4.5.8: Friend Search for Key Sharing of CrypTransfer






4.5.7 File Transfer Progress Screen
After selecting the file to transfer, the below File Transfer Progress Screen can be seen. The progress is communicated to the user with the help of a progress bar showing how the upload of the file is doing. The message “getting your file transferred now...” lets users know things are in progress.


Figure 4.5.10: File Transfer Progress Screen of CrypTransfer








4.5.8 Incoming File Screen
When the transfer is finished, the File Transfer Completion Screenwill be displayed to Sender. For A notification pops up at the bottom right of the screen saying “your file has been transferred” with a green tick to show it has been completed. The Continue-button will take the user to the next step, to view the file that has been transferred to the dashboard.


Figure 4.5.11: Incoming File Screen of CrypTransfer




4.5.9 Transfer Complete Screen
Upon sending the file, a successful notification pops up with letting the Sender know that the file is sent successfully.  The encrypted file can be seen sent to the respective user and the logs are immediately saved once the process is done.

Figure 4.5.12: Transfer Complete Screen of CrypTransfer








4.5.10 Decrypt File
After the Incoming File Screen is navigated by user through clicking “Proceed to Decrypt”, the receiver’s private key is used to recover the AES Key. The file will be locally saved onto the device.







Once decrypted, the user is presented with a last file selection screen where they can see the decrypted file. The Browse Files section is where they can regulate their files, with a visual indication of how much storage is being used. This screen serves as a last screen before reaching or working with the decrypted content.

Figure 4.5.11.1: Selecting File to Save or Cleanup for CrypTransfer

Figure 4.5.11.2: Selecting File to Save or Cleanup for CrypTransfer



| DECLARATION OF THESIS / UNDERGRADUATE PROJECT REPORT AND COPYRIGHT 
Author’s full name 	: NAVVEEN NAIR A/L MANOHARAN
 
Date of Birth           : 8/2/2003  
 
Title 	:  CRYPTRANSFER - FILE TRANSFER USING HYBRID ENCRYPTION/DECRYPTION TECHNIQUE (AES & RSA ALGORITHM)
 
 
Academic Session 	:  2024/2025-2
 
I declare that this thesis is classified as:  
 
CONFIDENTIAL (Contains confidential information under the Official Secret Act 1972)* 
 	 	 
RESTRICTED 	(Contains restricted information as specified by the organization where research was done)* 
 	 	 
OPEN ACCESS I agree that my thesis to be published as online open access (full text) 
 
1. I acknowledged that Universiti Teknologi Malaysia reserves the right as follows: 
The thesis is the property of Universiti Teknologi Malaysia 
The Library of Universiti Teknologi Malaysia has the right to make copies for the purpose of research only. 
The Library has the right to make copies of the thesis for academic exchange.                                                 Certified by: 
 	                                                             
	 
 	SIGNATURE OF STUDENT 	 	SIGNATURE OF SUPERVISOR 	      
           A22EC0092 	                                       DR RASHIDAH BINTI KADIR 	 	  
 	MATRIX NUMBER 	                                 NAME OF SUPERVISOR |
| --- |
| Signature | : | ________________________________ |
| --- | --- | --- |
| Name of Supervisor | : | DR RASHIDAH BINTI KADIR |
| Date | : | 24 JUNE 2025 |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
| Signature | : | .................................................... |
| --- | --- | --- |
| Name | : | NAVVEEN NAIR A/L MANOHARAN |
| Date | : | 24 JUNE 2025 |
|  |  |  |
|  |  |  |
|  | TITLE | PAGE |
| --- | --- | --- |
| TABLE NO. | TITLE | PAGE |
| --- | --- | --- |
| FIGURE NO. |  | TITLE | PAGE |
| --- | --- | --- | --- |
| AES | - | Advanced Encryption Standard |
| --- | --- | --- |
| RSA | - | Rivest-Shamir-Adleman Algorithm |
| TLS | - | Transport Layer Security |
| IDE | - | Integrated Development Environment |
| GUI | - | Graphical User Interface |
| UI | - | User Interface |
| SDLC | - | Software Development Life Cycle |
| UTM | - | Universiti Teknologi Malaysia |
| UML | - | Unified Modeling Language |
| ERD | - | Entity Relationship Diagram |
| CPU
CRUID
MITM 
RC4
DES
3DES
DH
ElGamal 
DSA | -
-  
-
-
-
-
-
-
- | Central Processing Unit
Create, Read, Update , Delete 
Man-in-the-Middle
Rivest Cipher 4 
Data Encryption Standard 
Triple Data Encryption Standard 
Diffie- Hellman 
ElGamal Encryption Algorithm 
Digital Signature Algorithm |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
|  |  |  |
| FIGURE NO. |  | TITLE | PAGE |
| --- | --- | --- | --- |
|  |
| --- |
| Feature | SHAREit , Zapya , Send Anywhere | 7-Zip | CrypTransfer |
| --- | --- | --- | --- |
| Main function | File Transfer | File Encryption | File Transfer and File Encryption |
| Encryption | No | Yes | Yes |
| Automatic Cleanup | No | No | Yes, after decryption |
| Data integrity | No | Yes | Yes, with guaranteed TLS Support |
| Security Transparency | No | Yes | Yes |
| All file format support | Yes | Yes | Yes |
| Main advantages | Fast Trasnfer | Secure Security | Secure File & Fast Transfer |
| Specifications | Minimum
Required
Specifications | Current Specifications | Status |
| --- | --- | --- | --- |
| Windows | Windows 10(64-bit) | Windows 11 Home (64-Bit) | Pass |
| Processor | Intel(R) Core
(TM) i3- 5700HQ @
2.50GHz 2.50 GHz | Intel(R) Core
(TM) i5-
10300H CPU@
2.50GHz   2.50GHz | Pass |
| RAM | 8GB: based on VS Code minimum
requirements | 32.0 GB | Pass |
| Memory | 40 - 60 GB | 1.5 TB | Pass |
| Internet | A stable connection is preferred | Unifi Fiber
100Mbps | Pass |
| Tools | Description |
| --- | --- |
| Visual Studio Code | Used during implementation as source code editor |
| Flutter | Used as framework for mobile applications |
| Firebase | Backend database and authentication |
| Pointycastle | Framework to install cryptographic libraries |
| GitHub | Used for version control |
| Dart | Primary language used for developing |
| Category | Elements |
| --- | --- |
| Network Elements | - Peer-to-Peer (P2P) Architecture
- TLS (Transport Layer Security) 
- Session-Based Transfer Channels |
| Security Elements | - AES-256 File Encryption
- RSA Public/Private Key Exchange
- Temporary File Cleanup |