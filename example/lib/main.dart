// A minimal, runnable example.
//
// Add the usual platform directories (`flutter create .`) inside `example/` to
// run it, or copy the two wiring steps into your own app — that is all there is.
import 'package:dio/dio.dart';
import 'package:flutter_dio_inspector/flutter_dio_inspector.dart';
import 'package:flutter/material.dart';

/// The one store shared by the interceptor and the widget.
final NetworkStore networkStore = NetworkStore();

/// `MaterialApp.builder` wraps the Navigator, so the panel needs a way back to
/// it. See the README for the alternative placement.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final Dio dio = Dio(BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'))
  ..interceptors.add(DioNetworkPanelInterceptor(store: networkStore));

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'flutter_dio_inspector',
      builder: (BuildContext context, Widget? child) => DioNetworkPanel(
        store: networkStore,
        navigatorKey: navigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _run(
    BuildContext context,
    String label,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text('$label 成功')));
    } catch (error) {
      // The panel recorded the failure in full; the snack bar just says it failed.
      messenger.showSnackBar(SnackBar(content: Text('$label 失败：$error')));
    }
  }

  Future<void> _cancelled() async {
    final token = CancelToken();
    final request = dio.get<List<dynamic>>('/todos', cancelToken: token);
    token.cancel('the user navigated away');
    try {
      await request;
    } on DioException {
      // Expected.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_dio_inspector')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('点右下角的悬浮球打开面板。'),
          ),
          _DemoButton(
            label: 'GET /todos?_limit=5',
            onPressed: () => _run(
              context,
              'GET',
              () => dio.get<List<dynamic>>(
                '/todos',
                queryParameters: <String, Object?>{'_limit': 5},
              ),
            ),
          ),
          _DemoButton(
            label: 'POST /todos',
            onPressed: () => _run(
              context,
              'POST',
              () => dio.post<Map<String, dynamic>>(
                '/todos',
                data: <String, Object?>{'title': 'hello', 'userId': 1},
              ),
            ),
          ),
          _DemoButton(
            label: '404',
            onPressed: () => _run(
              context,
              '404',
              () => dio.get<dynamic>('/definitely-not-here'),
            ),
          ),
          _DemoButton(
            label: '超时',
            onPressed: () => _run(
              context,
              '超时',
              () => dio.get<List<dynamic>>(
                '/todos',
                options: Options(
                  receiveTimeout: const Duration(milliseconds: 1),
                ),
              ),
            ),
          ),
          _DemoButton(label: '取消', onPressed: _cancelled),
        ],
      ),
    );
  }
}

class _DemoButton extends StatelessWidget {
  const _DemoButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonal(
          onPressed: onPressed,
          child: Text(label),
        ),
      ),
    );
  }
}
