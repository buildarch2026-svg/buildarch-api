enum AuthFlow { signUp, mobileLogin, googleLogin }

extension AuthFlowInfo on AuthFlow {
  String get label => switch (this) {
        AuthFlow.signUp => 'Sign up',
        AuthFlow.mobileLogin => 'Mobile login',
        AuthFlow.googleLogin => 'Google login',
      };

  String get heading => switch (this) {
        AuthFlow.signUp => 'Create your account',
        AuthFlow.mobileLogin => 'Welcome back',
        AuthFlow.googleLogin => 'Continue with Google',
      };

  String get subtitle => switch (this) {
        AuthFlow.signUp => 'We will send a one-time code to verify your number',
        AuthFlow.mobileLogin =>
          'Enter your mobile number to access your workspace',
        AuthFlow.googleLogin => 'We will finish your sign-in flow in a moment',
      };

  String get ctaLabel => switch (this) {
        AuthFlow.signUp => 'Send OTP',
        AuthFlow.mobileLogin => 'Send OTP',
        AuthFlow.googleLogin => 'Continue',
      };
}
