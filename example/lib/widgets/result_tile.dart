import 'package:flutter/material.dart';

/// 统一展示操作结果日志的列表组件。
class ResultList extends StatelessWidget {
  const ResultList({super.key, required this.results});
  final List<String> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(
        child: Text('暂无结果', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final s = results[i];
        final isError = s.contains('✗');
        return ListTile(
          dense: true,
          leading: Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 16,
            color: isError ? Colors.red : Colors.green,
          ),
          title: Text(
            s,
            style: TextStyle(
              fontSize: 13,
              color: isError ? Colors.red.shade700 : null,
            ),
          ),
        );
      },
    );
  }
}
