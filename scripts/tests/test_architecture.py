import contextlib
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / 'module_host/check_architecture.py'
SPEC = importlib.util.spec_from_file_location('architecture_check', SCRIPT)
architecture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(architecture)


class DartDirectivesTest(unittest.TestCase):
    def test_parts_are_forward_edges_and_part_of_is_not(self):
        self.assertEqual(list(architecture.directives(
            "library board; import 'base.dart'; export 'view.dart'; "
            "part /* implementation */ 'view_part.dart';"
        )), [('import', 'base.dart'), ('export', 'view.dart'), ('part', 'view_part.dart')])
        self.assertEqual(list(architecture.directives("part of 'board.dart';")), [])
        self.assertEqual(list(architecture.directives('part of board;')), [])

    def test_comments_and_source_examples_do_not_add_dependencies(self):
        source = '''
// import 'line_comment.dart';
/* part 'block_comment.dart'; /* nested */ export 'still_commented.dart'; */
part 'real.dart';
const example = """import 'example.dart'; part 'fake.dart';""";
'''
        self.assertEqual(list(architecture.directives(source)), [('part', 'real.dart')])

    def test_conditional_dependencies_ignore_condition_strings(self):
        self.assertEqual(list(architecture.directives(
            "import 'default.dart' if (dart.library.io) 'native.dart' "
            "if (dart.library.name == 'web') 'web.dart' as platform; "
            "export 'stub.dart' if (dart.library.io) 'desktop.dart';"
        )), [('import', 'default.dart'), ('import', 'native.dart'), ('import', 'web.dart'),
             ('export', 'stub.dart'), ('export', 'desktop.dart')])

    def test_library_metadata_and_raw_uris(self):
        self.assertEqual(list(architecture.directives(
            "@Deprecated('part \\\'fake.dart\\\';') library board; "
            "@experimental import r'base.dart'; part \"view.dart\";"
        )), [('import', 'base.dart'), ('part', 'view.dart')])

    def test_parameterless_library_annotation_preserves_following_directives(self):
        self.assertEqual(list(architecture.directives(
            "@someAnnotation\nlibrary example;\nimport 'dependency.dart';\npart 'body.dart';"
        )), [('import', 'dependency.dart'), ('part', 'body.dart')])


class ArchitectureLayersTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.lib = Path(self.directory.name)
        self.write('core/module_host/module_host.dart', '')

    def write(self, path, source):
        target = self.lib / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source)

    def test_pure_ui_contract_is_available_to_runtime(self):
        self.write('core/module_host/module_host.dart',
                   "import '../ui/ui_pack.dart';")
        self.write('core/ui/ui_pack.dart', "import 'dart:convert';")
        self.assertEqual(architecture.check_layers(self.lib), [])

    def test_runtime_cannot_reach_flutter_through_local_helper(self):
        self.write('core/module_host/module_host.dart', "import 'helper.dart';")
        self.write('core/module_host/helper.dart',
                   "import 'package:flutter/material.dart';")
        self.assertTrue(any('Flutter imported' in error
                            for error in architecture.check_layers(self.lib)))

    def test_runtime_cannot_import_ui_adapter_using_package_uri(self):
        self.write('core/module_host/module_host.dart',
                   "import 'package:task_app/core/module_host/helper.dart';")
        self.write('core/module_host/helper.dart',
                   "import '../ui/ui_component.dart';")
        self.write('core/ui/ui_component.dart', '')
        self.assertTrue(any('UI imported by headless' in error
                            for error in architecture.check_layers(self.lib)))

    def test_shared_ui_cannot_depend_on_app_compatibility_exports(self):
        self.write('core/ui/daily_widgets.dart',
                   "import '../../app/design_system.dart';")
        self.write('app/design_system.dart', "export '../core/ui/ui_design.dart';")
        self.assertTrue(any('Shared UI depends' in error
                            for error in architecture.check_layers(self.lib)))

    def test_foundation_cannot_reach_renderer_through_export(self):
        self.write('core/ui/ui_design.dart', "export 'helper.dart';")
        self.write('core/ui/helper.dart', "import 'ui_component.dart';")
        self.write('core/ui/ui_component.dart', '')
        self.assertTrue(any('Visual foundation depends' in error
                            for error in architecture.check_layers(self.lib)))

    def test_runtime_checks_part_dependencies_and_nested_helpers(self):
        self.write('core/module_host/module_host.dart', "part 'parts/helper.dart';")
        self.write('core/module_host/parts/helper.dart',
                   "part of '../module_host.dart'; import 'package:flutter/material.dart';")
        errors = architecture.check_layers(self.lib)
        self.assertTrue(any('Flutter imported by headless runtime: core/module_host/parts/helper.dart'
                            in error for error in errors))

    def test_runtime_cannot_include_ui_part_using_package_uri(self):
        self.write('core/module_host/module_host.dart',
                   "part 'package:task_app/core/ui/part.dart';")
        self.write('core/ui/part.dart', "part of '../module_host/module_host.dart';")
        self.assertTrue(any('UI imported by headless' in error
                            for error in architecture.check_layers(self.lib)))

    def test_shared_ui_follows_parts_outside_top_level_directory(self):
        self.write('core/ui/shared.dart', "part 'parts/adapter.dart';")
        self.write('core/ui/parts/adapter.dart', "part '../../../app/assembly.dart';")
        self.write('app/assembly.dart', '')
        self.assertTrue(any('Shared UI depends on App assembly: core/ui/parts/adapter.dart'
                            in error for error in architecture.check_layers(self.lib)))

    def test_foundation_cannot_reach_renderer_through_part(self):
        self.write('core/ui/ui_design.dart', "part 'parts/defaults.dart';")
        self.write('core/ui/parts/defaults.dart', "export '../ui_component.dart';")
        self.write('core/ui/ui_component.dart', '')
        self.assertTrue(any('Visual foundation depends on UI rendering: core/ui/parts/defaults.dart'
                            in error for error in architecture.check_layers(self.lib)))

    def test_commented_directives_do_not_create_layer_violations(self):
        self.write('core/module_host/module_host.dart',
                   "/* part '../ui/native_ui.dart'; */ // import 'package:flutter/material.dart';")
        self.write('core/ui/ui_design.dart',
                   "// part 'ui_component.dart';\nconst example = \"import '../../app/app.dart';\";")
        self.assertEqual(architecture.check_layers(self.lib), [])

    def test_business_identity_check_discovers_new_modules(self):
        self.write('packages/modules/private.inventory/module.json', json.dumps({
            'manifest': {'id': 'private.inventory'},
        }))
        pattern = architecture.business_identity_pattern(self.lib)
        self.assertIsNotNone(pattern.search("const id = 'private.inventory';"))
        self.assertIsNotNone(pattern.search("const page = 'private.inventory.home';"))
        self.assertIsNone(pattern.search("const id = 'private.inventory-other';"))


class ProductionPartsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.lib = self.root / 'client/lib'
        catalog = self.root / 'client/assets/modules/catalog.json'
        catalog.parent.mkdir(parents=True)
        catalog.write_text('[]')
        self.write('main.dart', "part 'implementation.dart';")

    def write(self, path, source):
        target = self.lib / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source)

    def test_parts_receive_identity_table_and_sql_checks(self):
        for source, message in [
            ("const id = 'app.tasks';", 'Business module identity special case'),
            ('final tasks = db.tasks;', 'Legacy business table reachable'),
            ("const query = 'SELECT * FROM tasks';", 'Legacy business SQL reachable'),
        ]:
            with self.subTest(message=message):
                self.write('implementation.dart', "part of 'main.dart';\n" + source)
                with self.assertRaisesRegex(SystemExit, message + ': implementation.dart'):
                    architecture.check_architecture(self.root)

    def test_legacy_runtime_cannot_be_reached_through_a_part(self):
        self.write('main.dart', "part 'features/tasks/legacy.dart';")
        self.write('features/tasks/legacy.dart', "part of '../../main.dart';")
        with self.assertRaisesRegex(SystemExit, 'Legacy business runtime reachable: features/tasks/legacy.dart'):
            architecture.check_architecture(self.root)

    def test_generated_database_part_keeps_table_exception(self):
        self.write('main.dart', "import 'data/app_database.dart';")
        self.write('data/app_database.dart', "part 'app_database.g.dart';")
        self.write('data/app_database.g.dart',
                   "part of 'app_database.dart';\nfinal table = db.tasks;\nconst sql = 'SELECT * FROM tasks';")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            architecture.check_architecture(self.root)
        self.assertIn('3 Dart files', output.getvalue())

    def test_part_of_and_comment_do_not_reach_legacy_files(self):
        self.write('implementation.dart',
                   "part of 'features/tasks/owner.dart';\n// part 'features/tasks/legacy.dart';")
        self.write('features/tasks/owner.dart', 'final tasks = db.tasks;')
        self.write('features/tasks/legacy.dart', "const id = 'app.tasks';")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            architecture.check_architecture(self.root)
        self.assertIn('2 Dart files', output.getvalue())




class BusinessSemanticsTest(unittest.TestCase):
    def test_generic_layers_cannot_read_business_fields(self):
        for path in ['core/module_host/script_page.dart', 'core/module_host/helper.dart',
                     'core/ui/presentation.dart', 'app/app_shell.dart']:
            self.assertTrue(architecture.check_business_semantics(path, "final date = row['plannedStartAt'];"))

    def test_comments_and_display_strings_are_not_record_access(self):
        self.assertEqual(architecture.check_business_semantics('core/ui/presentation.dart',
            "// row['plannedStartAt']\nconst label = \"row['plannedStartAt']\";"), [])

    def test_only_migration_may_read_private_business_fields(self):
        self.assertTrue(architecture.check_business_semantics(
            'core/module_host/planner_quick_adjust.dart', "row['plannedStartAt'];"))
        for path in ['core/module_host/legacy_data_migration.dart']:
            self.assertEqual(architecture.check_business_semantics(path, "row['plannedStartAt'];"), [])


if __name__ == '__main__':
    unittest.main()
