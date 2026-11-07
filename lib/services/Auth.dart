import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  /// INSCRIPTION AVEC MAIL ET MOT DE PASSE
  Future<User?> register({
    required String fullname,
    required String email,
    required String password,
    required String role,
  }) async {

    try {

      UserCredential credential =
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      User user = credential.user!;

      await user.updateDisplayName(fullname);

      await _firestore.collection("users").doc(user.uid).set({

        "uid": user.uid,
        "fullname": fullname,
        "email": email.trim(),
        "role": role,
        "createdAt": FieldValue.serverTimestamp(),

      });

      return user;

    } on FirebaseAuthException catch (e) {

      switch (e.code) {

        case 'email-already-in-use':
          throw "Cet email existe déjà.";

        case 'weak-password':
          throw "Le mot de passe est trop faible.";

        case 'invalid-email':
          throw "Email invalide.";

        default:
          throw e.message ?? "Erreur inconnue.";
      }
    }
  }

  /// CONNEXION AVEC MAIL ET MOT DE PASSE
  Future<User?> login({
    required String email,
    required String password,
  }) async {

    try {

      UserCredential credential =
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      return credential.user;

    } on FirebaseAuthException catch (e) {

      switch (e.code) {

        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          throw "Email ou mot de passe incorrect.";

        default:
          throw e.message ?? "Erreur inconnue.";
      }
    }
  }


  String verificationId = '';

  Future<void> sendOTP(String phoneNumber) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber, // Exemple : +22890123456

      verificationCompleted: (PhoneAuthCredential credential) async {
        // Vérification automatique possible sur Android
        await _auth.signInWithCredential(credential);
      },

      verificationFailed: (FirebaseAuthException e) {
        print('❌Erreur : ${e.message}');
      },

      codeSent: (String id, int? resendToken) {
        verificationId = id;

        print('✅Code OTP envoyé ');
        print(verificationId);

        // Naviguer vers ta page OTP ici
      },

      codeAutoRetrievalTimeout: (String id) {
        verificationId = id;
      },
    );
  }

  Future<bool> verifyOTP(String smsCode) async {
    try {
      print("⚠️ Début de la vérification OTP");

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      final UserCredential result =
      await _auth.signInWithCredential(credential);

      final User? user = result.user;

      if (user == null) {
        return false;
      }

      print("✅ Authentification Firebase réussie");
      print("UID : ${user.uid}");

      // Créer le profil s'il n'existe pas
      // ou conserver le profil existant.
      await createOrGetUser(user);

      print("✅ Profil utilisateur prêt");

      return true;

    } on FirebaseAuthException catch (e) {
      print("❌ Erreur Firebase Auth : ${e.code}");
      print("Message : ${e.message}");
      return false;

    } on FirebaseException catch (e) {
      print("❌ Erreur Firestore : ${e.code}");
      print("Message : ${e.message}");
      return false;

    } catch (e) {
      print("❌ Erreur inattendue : $e");
      return false;
    }
  }

  Future<void> createOrGetUser(User user) async {
    final firestore = FirebaseFirestore.instance;

    final userRef = firestore
        .collection('users')
        .doc(user.uid);

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);

      if (!snapshot.exists) {
        transaction.set(userRef, {
          'uid': user.uid,
          'phoneNumber': user.phoneNumber,
          'name': '',
          'email': '',
          'createdAt': FieldValue.serverTimestamp(),
        });

        print('✅ Nouveau profil utilisateur créé');
      } else {
        print('✅ Profil utilisateur existant');
      }
    });
  }


  /// DECONNEXION
  Future<void> logout() async {
    await _auth.signOut();
  }

}