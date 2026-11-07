import 'package:flutter/material.dart';
import 'package:flutter_intl_phone_field/flutter_intl_phone_field.dart';
import 'package:moovi/theme/app_colors.dart';
import '../services/Auth.dart';
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
                        floatingLabelStyle: TextStyle(
                          color: AppColors.primary
                        ),
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
                      initialCountryCode: 'MA',


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
                        print(phone.completeNumber);
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
                  text: 'Continuer',
                  onTap: () async {
                    //envoyer un code de vérification au numéro
                    print("Voici ce que vous m'avez demandé d'afficher");
                    print(_Countrycode+_phoneController.text);

                    //vérifier que le numéro est renseigné avant de passer à la page suivante passer à la page de vérification
                    if(isPhoneValid){

                      await AuthService.instance.sendOTP(_Countrycode+_phoneController.text);

                      Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => Otpverification(
                              phoneNumber: _phoneController.text,
                              countryCode : _Countrycode,
                            ),
                          ));
                    }

                  }),
            ],
          ),
        ),
      ),
    );
  }
}
