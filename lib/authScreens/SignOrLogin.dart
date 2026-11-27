import 'package:flutter/material.dart';
import 'package:flutter_intl_phone_field/flutter_intl_phone_field.dart';
import 'package:moovi/theme/app_colors.dart';
import '../services/Auth.dart';
import '../services/api_client.dart';
import '../widgets/animations/fadeSlideIn.dart';
import '../widgets/cButton.dart';
import 'otpVerification.dart';

class Signorlogin extends StatefulWidget {
  const Signorlogin({super.key});

  @override
  State<Signorlogin> createState() => _SignorloginState();
}

class _SignorloginState extends State<Signorlogin> {
  final _phoneController = TextEditingController();
  late String _Countrycode;

  //booléen pour vérifier la validité du numéro
  bool isPhoneValid = false;
  bool _isSendingCode = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 160),
              SizedBox(
                height: 60,
                child: Image.asset("assets/icon/MooviOrange.png"),
              ),
              const SizedBox(height: 20),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Entrez votre numéro de téléphone",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text("Un code de érification vous sera envoyé."),
                    ],
                  ),
                  const SizedBox(height: 28),
                  FadeSlideIn(
                    child: IntlPhoneField(
                      controller: _phoneController,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: InputDecoration(
                        fillColor: Colors.white,
                        labelText: 'Numéro de téléphone',
                        hintText: 'Entrez votre numéro',
                        floatingLabelStyle: TextStyle(color: AppColors.primary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.grey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.orange,
                            width: 2,
                          ),
                        ),
                      ),
                      initialCountryCode: 'GA',
                      validator: (phone) {
                        if (phone == null || phone.number.isEmpty) {
                          return 'Veuillez entrer votre numéro';
                        }

                        if (!phone.isValidNumber()) {
                          return 'Le numéro de téléphone est incorrect';
                        }

                        return null;
                      },
                      onChanged: (phone) {
                        setState(() {
                          isPhoneValid = phone.isValidNumber();
                        });
                        _Countrycode = phone.countryCode;
                      },
                      onCountryChanged: (country) {
                        setState(() {
                          isPhoneValid = false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
              CustomButton(
                  text: _isSendingCode ? 'Envoi du code...' : 'Continuer',
                  onTap: () async {
                    if (!isPhoneValid || _isSendingCode) return;
                    setState(() => _isSendingCode = true);
                    try {
                      final fullPhoneNumber =
                          '$_Countrycode${_phoneController.text}';
                      await AuthService.instance.sendOTP(fullPhoneNumber);
                      if (!mounted ||
                          AuthService.instance.currentUser != null) {
                        return;
                      }
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => Otpverification(
                            phoneNumber: _phoneController.text,
                            countryCode: _Countrycode,
                          ),
                        ),
                      );
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e is ApiException
                                  ? e.message
                                  : "Impossible d'envoyer le code. Vérifiez le numéro et réessayez.",
                            ),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _isSendingCode = false);
                      }
                    }
                  }),
            ],
          ),
        ),
      ),
    );
  }
}
