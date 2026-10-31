import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'check_docs.py'
spec = importlib.util.spec_from_file_location('docs_check', SCRIPT)
docs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(docs)


class DocumentationTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.published = set()

    def file(self, name, content='', *, published=True):
        target = self.root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding='utf-8')
        if published:
            self.published.add(name)
        return target

    def check(self, **kwargs):
        return docs.check_documents(self.root, self.published, **kwargs)

    def test_relative_files_unicode_encoded_anchors_and_images(self):
        self.file('docs/index.md', '[正文](guide.md#%E6%97%A5%E6%9C%9F%E4%B8%8E%E6%97%B6%E5%8C%BA)\n![图](../assets/icon.svg)')
        self.file('docs/guide.md', '# 日期与时区\n')
        self.file('assets/icon.svg', '<svg/>')
        report = self.check()
        self.assertEqual(report['errors'], [])
        self.assertEqual(report['linksChecked'], 2)

    def test_deleted_page_image_and_renamed_heading_fail(self):
        self.file('README.md', '[页面](gone.md) ![图](gone.png) [章节](guide.md#旧标题)')
        self.file('guide.md', '# 新标题\n')
        errors = self.check()['errors']
        self.assertEqual(len(errors), 3)
        self.assertIn('missing file: gone.md', errors[0])
        self.assertIn('missing file: gone.png', errors[1])
        self.assertIn('missing anchor', errors[2])

    def test_duplicate_headings_inline_formatting_and_explicit_anchors(self):
        self.file('README.md', '[一](#日期-api-1) [二](#日期-api-1-1) [旧入口](#old)\n'
                  '# 日期 `API` 1\n# 日期 **API** 1\n<a id="old"></a>\n')
        self.assertEqual(self.check()['errors'], [])

    def test_fenced_and_inline_examples_are_not_links_or_anchors(self):
        self.file('README.md', '````md\n[示例](gone.md)\n```\n# 假标题\n````\n'
                  '~~~md\n![示例](gone.png)\n~~~\n'
                  '`[调用](gone.md)` 和 `` `[示例](also-gone.md)` ``\n[真实](#有效)\n# 有效\n')
        self.assertEqual(self.check()['errors'], [])
        self.assertEqual(self.check()['linksChecked'], 1)
        self.assertNotIn('假标题', docs.markdown_anchors((self.root / 'README.md').read_text()))

    def test_reference_links_images_collapsed_and_shortcut_labels(self):
        self.file('README.md', '[显示][My Ref] [my ref][] [MY REF] ![图][image]\n\n'
                  '[my ref]: guide.md#details "标题"\n[image]: icon.png\n')
        self.file('guide.md', '# Details\n')
        self.file('icon.png')
        self.assertEqual(self.check()['errors'], [])
        self.assertEqual(self.check()['linksChecked'], 4)

    def test_reference_error_keeps_original_line_number(self):
        self.file('README.md', '# Intro\n\n[target]: guide.md#gone\n\n[target]\n')
        self.file('guide.md', '# Actual\n')
        self.assertIn('README.md:5: missing anchor', self.check()['errors'][0])

    def test_spaces_parentheses_and_escaped_destinations(self):
        self.file('README.md', '[空格](<docs/My Guide.md>) '
                  '[嵌套](docs/guide(v2).md "标题") '
                  r'[转义](docs/guide\(v2\).md)')
        self.file('docs/My Guide.md')
        self.file('docs/guide(v2).md')
        self.assertEqual(self.check()['errors'], [])
        self.assertEqual(self.check()['linksChecked'], 3)

    def test_external_urls_and_mail_are_not_fetched(self):
        self.file('README.md', '[网页](https://example.invalid/missing#gone) '
                  '[邮件](mailto:dev@example.invalid) [CDN](//example.invalid/icon.png)')
        report = self.check()
        self.assertEqual(report['errors'], [])
        self.assertEqual(report['linksChecked'], 0)

    def test_local_artifacts_are_optional_but_published_files_are_required(self):
        self.file('README.md', '[证据](dist/verification/missing.json) '
                  '![原图](design/styles/draft.png) [指南](design/styles/README.md)')
        self.published.add('design/styles/README.md')
        report = self.check()
        self.assertEqual(report['localLinksSkipped'], 2)
        self.assertEqual(len(report['errors']), 1)
        self.assertEqual(len(self.check(check_local=True)['errors']), 3)

    def test_local_markdown_can_be_checked_explicitly(self):
        self.file('README.md', '[证据](dist/report.md#result)')
        self.file('dist/report.md', '# Result\n', published=False)
        self.assertEqual(self.check(check_local=True)['errors'], [])
        (self.root / 'dist/report.md').write_text('# Renamed\n')
        self.assertIn('missing anchor', self.check(check_local=True)['errors'][0])

    def test_nested_build_outputs_do_not_break_clean_checkout(self):
        self.file('docs/history.md', '[历史 APK](../client/build/app/outputs/app.apk) '
                  '[编译记录](../client/.dart_tool/build.log)')
        report = self.check()
        self.assertEqual(report['errors'], [])
        self.assertEqual(report['localLinksSkipped'], 2)
        self.assertEqual(len(self.check(check_local=True)['errors']), 2)

    def test_links_cannot_read_outside_repository_via_parent_or_symlink(self):
        self.file('README.md', '[越界](../secret.md) [链接](secret.md#header)')
        external = tempfile.TemporaryDirectory()
        self.addCleanup(external.cleanup)
        target = Path(external.name) / 'secret.md'
        target.write_text('# Header\n')
        (self.root / 'secret.md').symlink_to(target)
        errors = self.check()['errors']
        self.assertEqual(len(errors), 2)
        self.assertTrue(all('leaves the repository' in error for error in errors))

    def test_sdk_current_version_must_match_host(self):
        self.file('client/lib/core/module_host/host_api.dart', 'final hostApiVersion = Version(1, 44, 0);')
        self.file('docs/MODULE_SDK.md', '当前宿主 API 为 `1.43.0`。')
        self.assertIn('current API', self.check()['errors'][0])
        (self.root / 'docs/MODULE_SDK.md').write_text('当前宿主 API 为 `1.44.0`。')
        self.assertEqual(self.check()['errors'], [])

    def test_setext_heading(self):
        self.file('README.md', '[入口](#详细说明)\n\n详细说明\n--------\n')
        self.assertEqual(self.check()['errors'], [])

    def test_cli_clean_checkout_and_failure_exit_code(self):
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        self.file('.gitignore', 'dist/\n')
        self.file('README.md', '[指南](docs/guide.md#开始) [本机证据](dist/result.json)')
        self.file('docs/guide.md', '# 开始\n')
        report = self.root / 'dist/report.json'
        command = [sys.executable, '-B', str(SCRIPT), '--root', str(self.root), '--json', str(report)]
        passed = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(passed.returncode, 0, passed.stderr)
        self.assertEqual(json.loads(report.read_text())['localLinksSkipped'], 1)
        (self.root / 'docs/guide.md').unlink()
        failed = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(failed.returncode, 1)
        self.assertIn('missing file', failed.stderr)


if __name__ == '__main__':
    unittest.main()
