import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / 'module_host/check_architecture.py'
SPEC = importlib.util.spec_from_file_location('architecture_check', SCRIPT)
architecture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(architecture)


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

    def test_business_identity_check_discovers_new_modules(self):
        self.write('packages/modules/private.inventory/module.json', json.dumps({
            'manifest': {'id': 'private.inventory'},
        }))
        pattern = architecture.business_identity_pattern(self.lib)
        self.assertIsNotNone(pattern.search("const id = 'private.inventory';"))
        self.assertIsNotNone(pattern.search("const page = 'private.inventory.home';"))
        self.assertIsNone(pattern.search("const id = 'private.inventory-other';"))


if __name__ == '__main__':
    unittest.main()
