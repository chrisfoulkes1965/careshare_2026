import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";
import "package:image_picker/image_picker.dart";

import "../../../core/avatars/avatar_choices.dart";
import "../../../core/theme/app_colors.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../auth/repository/auth_repository.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";
import "../models/alternate_email.dart";
import "../models/alternate_phone.dart";
import "../models/expense_payment_details.dart";
import "../models/postal_address.dart";
import "../models/user_profile.dart";
import "../repository/user_repository.dart";
import "widgets/care_user_avatar.dart";

class UserSettingsProfileScreen extends StatefulWidget {
  const UserSettingsProfileScreen({super.key});

  @override
  State<UserSettingsProfileScreen> createState() =>
      _UserSettingsProfileScreenState();
}

class _UserSettingsProfileScreenState extends State<UserSettingsProfileScreen> {
  final _identityFormKey = GlobalKey<FormState>();
  final _addressFormKey = GlobalKey<FormState>();
  final _paymentFormKey = GlobalKey<FormState>();

  final _displayNameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();

  final _addrLine1 = TextEditingController();
  final _addrLine2 = TextEditingController();
  final _addrCity = TextEditingController();
  final _addrRegion = TextEditingController();
  final _addrPostal = TextEditingController();
  final _addrCountry = TextEditingController();

  final _payAccountHolder = TextEditingController();
  final _paySortCode = TextEditingController();
  final _payAccountNumber = TextEditingController();
  final _payIban = TextEditingController();
  final _payBic = TextEditingController();

  bool _identityBusy = false;
  bool _addressBusy = false;
  bool _paymentBusy = false;
  bool _avatarBusy = false;
  String? _hydratedFromUid;

  @override
  void dispose() {
    _displayNameController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    _addrLine1.dispose();
    _addrLine2.dispose();
    _addrCity.dispose();
    _addrRegion.dispose();
    _addrPostal.dispose();
    _addrCountry.dispose();
    _payAccountHolder.dispose();
    _paySortCode.dispose();
    _payAccountNumber.dispose();
    _payIban.dispose();
    _payBic.dispose();
    super.dispose();
  }

  void _hydrateControllers(UserProfile p) {
    if (_hydratedFromUid == p.uid) {
      return;
    }
    _hydratedFromUid = p.uid;
    _displayNameController.text = p.displayName;
    _fullNameController.text = p.fullName ?? "";
    _phoneController.text = p.phone ?? "";
    final a = p.address;
    _addrLine1.text = a?.line1 ?? "";
    _addrLine2.text = a?.line2 ?? "";
    _addrCity.text = a?.city ?? "";
    _addrRegion.text = a?.region ?? "";
    _addrPostal.text = a?.postalCode ?? "";
    _addrCountry.text = a?.country ?? "";
    final pay = p.expensePaymentDetails;
    _payAccountHolder.text = pay?.accountHolderName ?? "";
    _paySortCode.text = pay?.sortCode ?? "";
    _payAccountNumber.text = pay?.accountNumber ?? "";
    _payIban.text = pay?.iban ?? "";
    _payBic.text = pay?.bic ?? "";
  }

  Future<void> _savePaymentDetails() async {
    if (_paymentBusy) {
      return;
    }
    if (!_paymentFormKey.currentState!.validate()) {
      return;
    }
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final userRepo = context.read<UserRepository>();
    final profileCubit = context.read<ProfileCubit>();
    final d = ExpensePaymentDetails(
      accountHolderName: _payAccountHolder.text,
      sortCode: _paySortCode.text,
      accountNumber: _payAccountNumber.text,
      iban: _payIban.text,
      bic: _payBic.text,
    );
    if (!d.isComplete) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Enter the account holder name and either an IBAN or a UK sort code and account number.",
          ),
        ),
      );
      return;
    }
    setState(() => _paymentBusy = true);
    try {
      await userRepo.setExpensePaymentDetails(session.uid, d);
      if (!mounted) {
        return;
      }
      await profileCubit.refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Payment details saved.")),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _paymentBusy = false);
      }
    }
  }

  Future<void> _clearPaymentDetails() async {
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove payment details?"),
        content: const Text(
          "You will not be able to submit new expenses until you add payment details again.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    setState(() => _paymentBusy = true);
    try {
      await context.read<UserRepository>().setExpensePaymentDetails(
            session.uid,
            null,
          );
      if (!mounted) {
        return;
      }
      await context.read<ProfileCubit>().refresh();
      if (!mounted) {
        return;
      }
      _payAccountHolder.clear();
      _paySortCode.clear();
      _payAccountNumber.clear();
      _payIban.clear();
      _payBic.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Payment details removed.")),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _paymentBusy = false);
      }
    }
  }

  Future<void> _saveIdentity() async {
    if (_identityBusy) {
      return;
    }
    if (!_identityFormKey.currentState!.validate()) {
      return;
    }
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final authRepo = context.read<AuthRepository>();
    final userRepo = context.read<UserRepository>();
    final profileCubit = context.read<ProfileCubit>();
    setState(() => _identityBusy = true);
    try {
      final dn = _displayNameController.text.trim();
      final fn = _fullNameController.text.trim();
      final ph = _phoneController.text.trim();
      await authRepo.updateDisplayName(dn);
      if (!mounted) return;
      await userRepo.updateProfileFields(session.uid, {"displayName": dn});
      if (!mounted) return;
      await userRepo.setFullName(session.uid, fn.isEmpty ? null : fn);
      if (!mounted) return;
      await userRepo.setPrimaryPhone(session.uid, ph.isEmpty ? null : ph);
      if (!mounted) return;
      await profileCubit.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile saved.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _identityBusy = false);
      }
    }
  }

  Future<void> _saveAddress() async {
    if (_addressBusy) {
      return;
    }
    if (!_addressFormKey.currentState!.validate()) {
      return;
    }
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final userRepo = context.read<UserRepository>();
    final profileCubit = context.read<ProfileCubit>();
    setState(() => _addressBusy = true);
    try {
      final addr = PostalAddress(
        line1: _addrLine1.text.trim(),
        line2: _addrLine2.text.trim(),
        city: _addrCity.text.trim(),
        region: _addrRegion.text.trim(),
        postalCode: _addrPostal.text.trim(),
        country: _addrCountry.text.trim(),
      );
      await userRepo.setPostalAddress(session.uid, addr.isEmpty ? null : addr);
      if (!mounted) return;
      await profileCubit.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            addr.isEmpty ? "Address cleared." : "Address saved.",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _addressBusy = false);
      }
    }
  }

  Future<void> _pickAvatar(int oneBased) async {
    if (_avatarBusy) {
      return;
    }
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final userRepo = context.read<UserRepository>();
    final authRepo = context.read<AuthRepository>();
    final profileCubit = context.read<ProfileCubit>();
    setState(() => _avatarBusy = true);
    try {
      await userRepo.setAvatarPreset(session.uid, oneBased);
      if (!mounted) return;
      await authRepo.updatePhotoUrl(null);
      if (!mounted) return;
      await profileCubit.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Avatar updated. Your sign-in photo was cleared to show this image.",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _useAccountPhoto() async {
    if (_avatarBusy) {
      return;
    }
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final url = session.photoURL?.trim();
    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "No profile photo is available from your sign-in account.",
            ),
          ),
        );
      }
      return;
    }
    final authRepo = context.read<AuthRepository>();
    final userRepo = context.read<UserRepository>();
    final profileCubit = context.read<ProfileCubit>();
    setState(() => _avatarBusy = true);
    try {
      await authRepo.updatePhotoUrl(url);
      if (!mounted) return;
      await userRepo.setProfilePhotoUrl(session.uid, url);
      if (!mounted) return;
      await profileCubit.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Using your sign-in account photo in CareShare."),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _useInitialsAvatar() async {
    if (_avatarBusy) {
      return;
    }
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final userRepo = context.read<UserRepository>();
    final authRepo = context.read<AuthRepository>();
    final profileCubit = context.read<ProfileCubit>();
    setState(() => _avatarBusy = true);
    try {
      await userRepo.updateProfileFields(session.uid, {
        "avatarIndex": null,
        "photoUrl": null,
      });
      if (!mounted) return;
      await authRepo.updatePhotoUrl(null);
      if (!mounted) return;
      await profileCubit.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Using your initials as the avatar."),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _pickProfilePhoto(ImageSource source) async {
    if (_avatarBusy) {
      return;
    }
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );
    if (file == null || !mounted) {
      return;
    }
    final userRepo = context.read<UserRepository>();
    final authRepo = context.read<AuthRepository>();
    final profileCubit = context.read<ProfileCubit>();
    setState(() => _avatarBusy = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await userRepo.uploadProfilePhoto(
        uid: session.uid,
        bytes: bytes,
        mimeType: file.mimeType,
      );
      if (!mounted) return;
      await authRepo.updatePhotoUrl(url);
      if (!mounted) return;
      await userRepo.setProfilePhotoUrl(session.uid, url);
      if (!mounted) return;
      await profileCubit.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile photo updated.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _addAlternateEmail(UserProfile p) async {
    final addr = await _promptForString(
      title: "Add alternate email",
      hint: "name@example.com",
      keyboardType: TextInputType.emailAddress,
      validator: (v) {
        final t = (v ?? "").trim();
        if (t.isEmpty) {
          return "Enter an email";
        }
        if (!t.contains("@") || !t.contains(".")) {
          return "Enter a valid email";
        }
        if (t.toLowerCase() == p.email.toLowerCase()) {
          return "That's already your primary email.";
        }
        if (p.alternateEmails
            .any((e) => e.normalized == t.toLowerCase().trim())) {
          return "Already on the list.";
        }
        return null;
      },
    );
    if (addr == null) {
      return;
    }
    if (!mounted) return;
    final clean = addr.trim();
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final userRepo = context.read<UserRepository>();
    final profileCubit = context.read<ProfileCubit>();
    final next = [
      ...p.alternateEmails,
      AlternateEmail(
        address: clean,
        verified: false,
        addedAt: DateTime.now(),
      ),
    ];
    try {
      await userRepo.setAlternateEmails(session.uid, next);
      if (!mounted) return;
      await profileCubit.refresh();
      if (!mounted) return;
      // Fire-and-forget verification email — show feedback on result.
      try {
        await userRepo.requestAlternateEmailVerification(emailAddress: clean);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text("Verification email sent to $clean. Click the link to verify."),
            duration: const Duration(seconds: 5),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Saved as unverified — couldn't send verification email: $e",
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _resendAlternateEmailVerification(AlternateEmail e) async {
    final userRepo = context.read<UserRepository>();
    try {
      await userRepo.requestAlternateEmailVerification(
        emailAddress: e.address,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Verification email re-sent to ${e.address}."),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString())),
      );
    }
  }

  Future<void> _removeAlternateEmail(
    UserProfile p,
    AlternateEmail e,
  ) async {
    final ok = await _confirm(
      title: "Remove ${e.address}?",
      message:
          "It will no longer be associated with your CareShare profile. You can re-add it later.",
    );
    if (!ok) {
      return;
    }
    if (!mounted) return;
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final userRepo = context.read<UserRepository>();
    final profileCubit = context.read<ProfileCubit>();
    final next = p.alternateEmails
        .where((x) => x.normalized != e.normalized)
        .toList();
    try {
      await userRepo.setAlternateEmails(session.uid, next);
      if (!mounted) return;
      await profileCubit.refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString())),
      );
    }
  }

  Future<void> _addAlternatePhone(UserProfile p) async {
    final res = await _promptForAlternatePhone(existing: p.alternatePhones);
    if (res == null) {
      return;
    }
    if (!mounted) return;
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final userRepo = context.read<UserRepository>();
    final profileCubit = context.read<ProfileCubit>();
    final next = [...p.alternatePhones, res];
    try {
      await userRepo.setAlternatePhones(session.uid, next);
      if (!mounted) return;
      await profileCubit.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.verificationSkippedNonMobile
                ? "Saved ${res.number} as unverified (non-mobile)."
                : "Saved ${res.number}. SMS verification will be available soon.",
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString())),
      );
    }
  }

  Future<void> _removeAlternatePhone(
    UserProfile p,
    AlternatePhone phone,
  ) async {
    final ok = await _confirm(
      title: "Remove ${phone.number}?",
      message:
          "It will no longer be associated with your CareShare profile. You can re-add it later.",
    );
    if (!ok) {
      return;
    }
    if (!mounted) return;
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final userRepo = context.read<UserRepository>();
    final profileCubit = context.read<ProfileCubit>();
    final next =
        p.alternatePhones.where((x) => x.normalized != phone.normalized).toList();
    try {
      await userRepo.setAlternatePhones(session.uid, next);
      if (!mounted) return;
      await profileCubit.refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err.toString())),
      );
    }
  }

  Future<String?> _promptForString({
    required String title,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
              validator: validator,
              autofocus: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.of(ctx).pop(controller.text.trim());
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<AlternatePhone?> _promptForAlternatePhone({
    required List<AlternatePhone> existing,
  }) async {
    final numberCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var nonMobile = false;
    final result = await showDialog<AlternatePhone>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text("Add alternate number"),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: numberCtrl,
                      keyboardType: TextInputType.phone,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: "Phone number",
                        hintText: "+1 555 123 4567",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final t = (v ?? "").trim();
                        if (t.isEmpty) {
                          return "Enter a number";
                        }
                        if (existing.any((p) => p.normalized == t)) {
                          return "Already on the list.";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: labelCtrl,
                      decoration: const InputDecoration(
                        labelText: "Label (optional)",
                        hintText: "Home, Work, Mum…",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: nonMobile,
                      onChanged: (v) => setLocal(() => nonMobile = v),
                      title: const Text("This isn't a mobile number"),
                      subtitle: const Text(
                        "Skip SMS verification — saved as unverified.",
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "SMS verification of mobile numbers is coming soon — for now mobile numbers are saved as unverified.",
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: AppColors.grey500,
                          ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text("Cancel"),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() == true) {
                      Navigator.of(ctx).pop(
                        AlternatePhone(
                          number: numberCtrl.text.trim(),
                          label: labelCtrl.text.trim().isEmpty
                              ? null
                              : labelCtrl.text.trim(),
                          verified: false,
                          verificationSkippedNonMobile: nonMobile,
                          addedAt: DateTime.now(),
                        ),
                      );
                    }
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
    numberCtrl.dispose();
    labelCtrl.dispose();
    return result;
  }

  Future<bool> _confirm({
    required String title,
    required String message,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Remove"),
            ),
          ],
        );
      },
    );
    return res == true;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, ps) {
        if (ps is! ProfileReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final p = ps.profile;
        _hydrateControllers(p);
        final session = context.watch<AuthBloc>().state.user;
        if (session == null) {
          return const Scaffold(body: Center(child: Text("Not signed in.")));
        }
        final authFallback = UserProfile.fromAuthSession(
          uid: session.uid,
          email: session.email ?? "",
          displayName: session.displayName,
          photoUrl: session.photoURL,
        );
        return Scaffold(
          appBar: AppBar(
            title: const Text("Profile & avatar"),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go("/home");
                }
              },
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: CareUserAvatar(
                  radius: 48,
                  profile: p,
                  authFallback: authFallback,
                ),
              ),
              const SizedBox(height: 24),
              const _SectionHeader(text: "Identity"),
              const SizedBox(height: 8),
              Form(
                key: _identityFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: "Display name",
                        helperText: "Shown in chat and members lists.",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return "Enter a name";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: "Full name (optional)",
                        helperText: "Legal / formal name.",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: "Primary phone (optional)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: _identityBusy ? null : _saveIdentity,
                        child: _identityBusy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text("Save"),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const _SectionHeader(text: "Address"),
              const SizedBox(height: 8),
              Form(
                key: _addressFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _addrLine1,
                      decoration: const InputDecoration(
                        labelText: "Line 1",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addrLine2,
                      decoration: const InputDecoration(
                        labelText: "Line 2 (optional)",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _addrCity,
                            decoration: const InputDecoration(
                              labelText: "City",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _addrRegion,
                            decoration: const InputDecoration(
                              labelText: "State / region",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _addrPostal,
                            decoration: const InputDecoration(
                              labelText: "Postal code",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _addrCountry,
                            decoration: const InputDecoration(
                              labelText: "Country",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: _addressBusy ? null : _saveAddress,
                        child: _addressBusy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text("Save address"),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              const _SectionHeader(text: "Expense reimbursement payments"),
              const SizedBox(height: 8),
              Text(
                "Used when you submit expenses so organisers know where to send reimbursement. "
                "Provide either an IBAN or a UK sort code and account number.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.grey500,
                    ),
              ),
              const SizedBox(height: 12),
              Form(
                key: _paymentFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _payAccountHolder,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: "Account holder name",
                        helperText: "Must match your bank account.",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().length < 2) {
                          return "Enter the name on the account";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "UK bank account",
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _paySortCode,
                      decoration: const InputDecoration(
                        labelText: "Sort code (optional)",
                        hintText: "e.g. 12-34-56",
                        border: OutlineInputBorder(),
                      ),
                      autocorrect: false,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _payAccountNumber,
                      decoration: const InputDecoration(
                        labelText: "Account number (optional)",
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "International",
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _payIban,
                      decoration: const InputDecoration(
                        labelText: "IBAN (optional)",
                        border: OutlineInputBorder(),
                      ),
                      autocorrect: false,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _payBic,
                      decoration: const InputDecoration(
                        labelText: "BIC / SWIFT (optional)",
                        border: OutlineInputBorder(),
                      ),
                      autocorrect: false,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton(
                        onPressed: _paymentBusy ? null : _savePaymentDetails,
                        child: _paymentBusy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text("Save payment details"),
                      ),
                    ),
                    if (p.hasCompleteExpensePaymentDetails) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed:
                              _paymentBusy ? null : () => _clearPaymentDetails(),
                          child: const Text("Remove saved payment details"),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _SectionHeader(
                text: "Alternate phone numbers",
                actionLabel: "Add",
                onAction: () => _addAlternatePhone(p),
              ),
              const SizedBox(height: 8),
              if (p.alternatePhones.isEmpty)
                Text(
                  "None yet. Tap Add to include another number.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.grey500,
                      ),
                )
              else
                ...p.alternatePhones.map(
                  (ph) => _AlternatePhoneTile(
                    phone: ph,
                    onRemove: () => _removeAlternatePhone(p, ph),
                  ),
                ),
              const SizedBox(height: 32),
              _SectionHeader(
                text: "Alternate email addresses",
                actionLabel: "Add",
                onAction: () => _addAlternateEmail(p),
              ),
              const SizedBox(height: 8),
              if (p.alternateEmails.isEmpty)
                Text(
                  "None yet. Tap Add to include another email — we'll send a verification link.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.grey500,
                      ),
                )
              else
                ...p.alternateEmails.map(
                  (e) => _AlternateEmailTile(
                    email: e,
                    onResend: () => _resendAlternateEmailVerification(e),
                    onRemove: () => _removeAlternateEmail(p, e),
                  ),
                ),
              const SizedBox(height: 32),
              const _SectionHeader(text: "Profile picture"),
              const SizedBox(height: 8),
              Text(
                "Use your own photo, your sign-in account image, initials, or a preset below.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.grey500,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _avatarBusy ? null : () => _pickProfilePhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text("Take photo"),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _avatarBusy ? null : () => _pickProfilePhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text("Choose photo"),
                  ),
                  if (session.photoURL != null &&
                      session.photoURL!.trim().isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _avatarBusy ? null : _useAccountPhoto,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text("Use sign-in photo"),
                    ),
                  OutlinedButton.icon(
                    onPressed: _avatarBusy ? null : _useInitialsAvatar,
                    icon: const Icon(Icons.text_fields),
                    label: const Text("Use initials"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                "Or pick a preset (shown only inside CareShare):",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.grey500,
                    ),
              ),
              const SizedBox(height: 12),
              if (_avatarBusy)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Center(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var n = 1; n <= kSetupAvatarCount; n++)
                        InkWell(
                          onTap: () => _pickAvatar(n),
                          borderRadius: BorderRadius.circular(8),
                          child: Material(
                            color: setupAvatarBackground(n),
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: buildSetupAvatarImage(
                                    n,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add),
            label: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _AlternateEmailTile extends StatelessWidget {
  const _AlternateEmailTile({
    required this.email,
    required this.onResend,
    required this.onRemove,
  });

  final AlternateEmail email;
  final Future<void> Function() onResend;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          email.verified ? Icons.verified_outlined : Icons.email_outlined,
          color: email.verified
              ? Theme.of(context).colorScheme.primary
              : AppColors.grey500,
        ),
        title: Text(email.address),
        subtitle: Text(
          email.verified ? "Verified" : "Unverified — link not yet clicked",
          style: TextStyle(
            color: email.verified
                ? Theme.of(context).colorScheme.primary
                : AppColors.grey500,
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == "resend") {
              await onResend();
            } else if (v == "remove") {
              await onRemove();
            }
          },
          itemBuilder: (ctx) => [
            if (!email.verified)
              const PopupMenuItem(
                value: "resend",
                child: Text("Resend verification"),
              ),
            const PopupMenuItem(
              value: "remove",
              child: Text("Remove"),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlternatePhoneTile extends StatelessWidget {
  const _AlternatePhoneTile({
    required this.phone,
    required this.onRemove,
  });

  final AlternatePhone phone;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final status = phone.verified
        ? "Verified"
        : phone.verificationSkippedNonMobile
            ? "Unverified — non-mobile"
            : "Unverified — SMS verification coming soon";
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          phone.verified ? Icons.verified_outlined : Icons.phone_outlined,
          color: phone.verified
              ? Theme.of(context).colorScheme.primary
              : AppColors.grey500,
        ),
        title: Text(
          phone.label != null && phone.label!.isNotEmpty
              ? "${phone.number}  ·  ${phone.label}"
              : phone.number,
        ),
        subtitle: Text(
          status,
          style: TextStyle(
            color: phone.verified
                ? Theme.of(context).colorScheme.primary
                : AppColors.grey500,
          ),
        ),
        trailing: IconButton(
          tooltip: "Remove",
          icon: const Icon(Icons.delete_outline),
          onPressed: () => onRemove(),
        ),
      ),
    );
  }
}
