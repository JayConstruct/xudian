import 'package:flutter_test/flutter_test.dart';
import 'package:xquickjs/error_message.dart';

void main() {
  test('nested transport wrappers and frames retain only business text', () {
    expect(
      scriptErrorMessage(
        StateError(
          'Error: Bad state: Error: 撤销已停止：任务或实例已被后续修改或完成\n'
          '    at batchUndo (main.js:34:375)\n',
        ),
      ),
      '撤销已停止：任务或实例已被后续修改或完成',
    );
    expect(
      scriptErrorMessage(
        StateError('Error: 请先配置 AI 连接\n    at render (main.js:82:60)\n'),
      ),
      '请先配置 AI 连接',
    );
    expect(scriptErrorMessage(const FormatException('输入无效')), '输入无效');
  });
  test('preserve multiline business details and colons inside content', () {
    expect(
      scriptErrorMessage('at least one task\n    at least two days'),
      'at least one task\n    at least two days',
    );
    expect(
      scriptErrorMessage('Error: 无法安排\n请调整日期: 2026-10-13'),
      '无法安排\n请调整日期: 2026-10-13',
    );
    expect(scriptErrorMessage('数据 Error: 请核对'), '数据 Error: 请核对');
    expect(
      scriptErrorMessage('Error: 请重试\nError: 请重试\n at run (main.js:1)'),
      '请重试',
    );
    expect(scriptErrorMessage('Error: \n at run (main.js:1)'), '模块操作失败，请重试。');
  });
}
