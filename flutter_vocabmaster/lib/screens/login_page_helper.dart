import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class LoginPageHelper extends StatelessWidget {
  final bool isSignUp;
  final bool rememberMe;
  final ValueChanged<bool?> onRememberMeChanged;

  const LoginPageHelper({
    super.key,
    required this.isSignUp, 
    required this.rememberMe, 
    required this.onRememberMeChanged
  });

  @override
  Widget build(BuildContext context) {
    return buildRememberMe(context);
  }

  Widget buildRememberMe(BuildContext context) {
    if (isSignUp) return const SizedBox.shrink();
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            SizedBox(
              height: 24,
              width: 24,
              child: Checkbox(
                value: rememberMe,
                onChanged: onRememberMeChanged,
                activeColor: AppColors.cyan400,
                side: const BorderSide(color: AppColors.slate400),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              "Beni Hatırla",
              style: TextStyle(
                color: AppColors.slate400,
                fontSize: 12,
              ),
            ),
          ],
        ),
        Text(
          "Şifremi unuttum",
          style: TextStyle(
            color: AppColors.cyan400.withOpacity(0.9),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          )
        ),
      ],
    );
  }
}
