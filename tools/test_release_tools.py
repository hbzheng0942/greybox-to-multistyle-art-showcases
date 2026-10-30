"""Small download/extraction integrity tests; no showcase assets are duplicated."""
import hashlib
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from download_complete import download, extract, install_resources
import launch as launcher


class ReleaseTests(unittest.TestCase):
    def test_resume_and_join_verified_volumes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'
            source.mkdir()
            output = root / 'output'
            output.mkdir()
            chunks = [b'first-volume\x00', b'second-volume\xff']
            parts, assets = [], []
            for index, data in enumerate(chunks):
                path = source / f'complete.zip.{index + 1:03d}'
                path.write_bytes(data)
                parts.append({'name': path.name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
                assets.append({'name': path.name, 'browser_download_url': path.as_uri()})
            complete = b''.join(chunks)
            spec = {'archive': {'name': 'complete.zip', 'bytes': len(complete), 'sha256': hashlib.sha256(complete).hexdigest()}, 'parts': parts}
            manifest = source / 'release-files.json'
            manifest.write_text(json.dumps(spec))
            assets.append({'name': manifest.name, 'browser_download_url': manifest.as_uri()})
            # Resume after a valid first part and an interrupted second part.
            (output / 'complete.zip.partial').write_bytes(chunks[0] + b'wrong partial')
            result = download({'assets': assets}, output)
            self.assertEqual(result.read_bytes(), complete)
            self.assertEqual(download({'assets': assets}, output), result)

    def test_resource_links_extract_after_regular_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'links.zip'
            with zipfile.ZipFile(archive, 'w') as bundle:
                link = zipfile.ZipInfo('showcase/game/model.glb')
                link.create_system = 3
                link.external_attr = (stat.S_IFLNK | 0o777) << 16
                bundle.writestr(link, '../assets/model.glb')
                bundle.writestr('showcase/assets/model.glb', b'model bytes')
            extract(archive, root / 'output')
            self.assertEqual((root / 'output/showcase/game/model.glb').read_bytes(), b'model bytes')

    def test_reject_path_traversal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'bad.zip'
            with zipfile.ZipFile(archive, 'w') as bundle:
                bundle.writestr('../outside.txt', b'bad')
            with self.assertRaisesRegex(RuntimeError, 'Unsafe archive member'):
                extract(archive, root / 'output')
            self.assertFalse((root / 'outside.txt').exists())

    def test_reject_external_link(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / 'bad-link.zip'
            with zipfile.ZipFile(archive, 'w') as bundle:
                link = zipfile.ZipInfo('showcase/model.glb')
                link.create_system = 3
                link.external_attr = (stat.S_IFLNK | 0o777) << 16
                bundle.writestr(link, '../../outside.glb')
            with self.assertRaisesRegex(RuntimeError, 'Unsafe resource link'):
                extract(archive, root / 'output')

    def test_install_into_git_checkout_and_repair_text_link(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            checkout = root / 'checkout'
            (checkout / 'games/demo').mkdir(parents=True)
            data = b'actual model payload'
            digest = hashlib.sha256(data).hexdigest()
            relative = f'shared/assets/sha256/{digest[:2]}/{digest}.glb'
            (checkout / 'assets-manifest.json').write_text(json.dumps({'assets': [{'path': relative, 'bytes': len(data), 'sha256': digest}]}))
            link = '../../' + relative
            (checkout / 'resource-links.json').write_text(json.dumps({'links': [{'path': 'games/demo/model.glb', 'target': link}]}))
            (checkout / 'games/demo/model.glb').write_text(link)
            original = checkout / 'games/demo/game.gd'
            original.write_text('my editable source')
            archive = root / 'complete.zip'
            with zipfile.ZipFile(archive, 'w') as bundle:
                bundle.writestr('greybox-to-multistyle-art-showcases/' + relative, data)
            install_resources(archive, checkout)
            self.assertEqual((checkout / 'games/demo/model.glb').read_bytes(), data)
            self.assertEqual(original.read_text(), 'my editable source')
            install_resources(archive, checkout)

    def test_extract_preserves_existing_work(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / 'output'
            output.mkdir()
            (output / 'game.gd').write_text('local edits')
            archive = root / 'complete.zip'
            with zipfile.ZipFile(archive, 'w') as bundle:
                bundle.writestr('game.gd', 'replacement')
            with self.assertRaisesRegex(RuntimeError, 'overwrite an existing file'):
                extract(archive, output)
            self.assertEqual((output / 'game.gd').read_text(), 'local edits')

    def test_first_launch_imports_classes_and_stops_if_import_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'shared/assets/sha256/00').mkdir(parents=True)
            (root / 'shared/assets/sha256/00/model.glb').write_bytes(b'fixture')
            (root / 'game').mkdir()
            (root / 'game/project.godot').write_text('fixture')
            (root / 'catalog.json').write_text(json.dumps({'games': [{'id': 'train', 'styles': [{'id': 'art', 'name': 'Art', 'project': 'game/project.godot', 'scene': 'res://play.tscn', 'engine_args': ['--rendering-driver', 'vulkan']}]}]}))
            arguments = ['launch.py', 'train', 'art', '--godot', 'fixture-godot']
            with patch.object(launcher, 'ROOT', root), patch('sys.argv', arguments), patch.object(launcher.subprocess, 'call', side_effect=[0, 0]) as run:
                with self.assertRaises(SystemExit) as result:
                    launcher.main()
                self.assertEqual(result.exception.code, 0)
                self.assertIn('--import', run.call_args_list[0].args[0])
                self.assertIn('--rendering-driver', run.call_args_list[1].args[0])
                self.assertEqual(run.call_args_list[1].args[0][-1], 'res://play.tscn')
            with patch.object(launcher, 'ROOT', root), patch('sys.argv', arguments), patch.object(launcher.subprocess, 'call', return_value=7) as run:
                with self.assertRaises(SystemExit) as result:
                    launcher.main()
                self.assertEqual(result.exception.code, 7)
                self.assertEqual(run.call_count, 1)


if __name__ == '__main__':
    unittest.main()
