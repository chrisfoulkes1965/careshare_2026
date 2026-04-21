import "dart:async";

import "package:flutter/foundation.dart";

import "../features/auth/bloc/auth_bloc.dart";
import "../features/profile/profile_cubit.dart";

/// Drives [GoRouter] refresh when auth or profile changes.
final class SessionRefresh extends ChangeNotifier {
  SessionRefresh({
    required AuthBloc authBloc,
    required ProfileCubit profileCubit,
  })  : _authBloc = authBloc,
        _profileCubit = profileCubit {
    _authSub = _authBloc.stream.listen((_) => notifyListeners());
    _profileSub = _profileCubit.stream.listen((_) => notifyListeners());
  }

  final AuthBloc _authBloc;
  final ProfileCubit _profileCubit;
  late final StreamSubscription<dynamic> _authSub;
  late final StreamSubscription<dynamic> _profileSub;

  @override
  void dispose() {
    unawaited(_authSub.cancel());
    unawaited(_profileSub.cancel());
    super.dispose();
  }
}
