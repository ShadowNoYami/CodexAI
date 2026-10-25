import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/presentation/screens/main_chat_screen.dart';

/// Провайдер маршрутизации приложения (GoRouter).
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'chat',
        builder: (context, state) => const MainChatScreen(),
      ),
    ],
  );
});
