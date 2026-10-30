"""Tiny transfer integrity fixtures. No real showcase resources or network calls."""
import copy
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.request
import urllib.error

from assemble_large_files import GitHub, SafeRedirect, assemble, matches_asset, publish, validate_manifest


def fixture():
    pieces = [b'first Git chunk\x00', b'previously uploaded Release volume\xff']
    joined = b''.join(pieces)
    archive = {'name': 'complete.zip', 'bytes': len(joined), 'sha256': hashlib.sha256(joined).hexdigest(), 'source_commit': 'a' * 40}
    segments = []
    offset = 0
    for index, piece in enumerate(pieces):
        source = {'type': 'git', 'path': 'large-files/complete.zip.chunk0001',
                  'blob_sha': hashlib.sha1(f'blob {len(piece)}\0'.encode() + piece).hexdigest()} if index == 0 else {
                      'type': 'release', 'asset_id': 20, 'name': 'complete.zip.002'}
        segments.append({'offset': offset, 'bytes': len(piece), 'sha256': hashlib.sha256(piece).hexdigest(), 'source': source})
        offset += len(piece)
    parts = [{key: value for key, value in segment.items() if key != 'source'} | {'name': f'complete.zip.{index + 1:03d}'}
             for index, segment in enumerate(segments)]
    spec = {'schema': 1, 'tag': 'v0', 'archive': {key: archive[key] for key in ('name', 'bytes', 'sha256')},
            'parts': parts, 'join_order': [part['name'] for part in parts]}
    manifest = {'schema': 1, 'complete': True, 'archive': archive, 'segments': segments,
                'release': {'id': 1, 'tag': 'v0', 'spec': spec}}
    return manifest, pieces


class FixtureClient:
    def __init__(self, pieces):
        self.pieces = pieces
        self.requested_offsets = []

    def segment(self, commit, record):
        self.requested_offsets.append(record['offset'])
        return io.BytesIO(self.pieces[0 if record['offset'] == 0 else 1])


class AssemblyTests(unittest.TestCase):
    def test_resume_keeps_verified_segment_and_replaces_corrupt_tail(self):
        manifest, pieces = fixture()
        client = FixtureClient(pieces)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            (output / 'complete.zip.partial').write_bytes(pieces[0] + b'interrupted incorrect tail')
            archive = assemble(manifest, 'c' * 40, output, client)
            self.assertEqual(archive.read_bytes(), b''.join(pieces))
            self.assertEqual(client.requested_offsets, [len(pieces[0])])
            self.assertEqual(assemble(manifest, 'c' * 40, output, client), archive)
            self.assertEqual(client.requested_offsets, [len(pieces[0])])

    def test_corrupt_segment_never_becomes_complete_archive(self):
        manifest, pieces = fixture()
        client = FixtureClient([b'x' * len(pieces[0]), pieces[1]])
        with tempfile.TemporaryDirectory() as temporary, patch('assemble_large_files.time.sleep'):
            output = Path(temporary)
            with self.assertRaisesRegex(RuntimeError, 'SHA256'):
                assemble(manifest, 'c' * 40, output, client)
            self.assertFalse((output / 'complete.zip').exists())
            self.assertEqual((output / 'complete.zip.partial').stat().st_size, 0)

    def test_wrong_git_blob_sha_rejected_even_when_sha256_matches(self):
        manifest, pieces = fixture()
        manifest['segments'][0]['source']['blob_sha'] = '0' * 40
        with tempfile.TemporaryDirectory() as temporary, patch('assemble_large_files.time.sleep'):
            with self.assertRaisesRegex(RuntimeError, 'Git blob SHA1'):
                assemble(manifest, 'c' * 40, Path(temporary), FixtureClient(pieces))

    def test_manifest_rejects_gap_incomplete_and_unsafe_paths(self):
        manifest, _ = fixture()
        invalid = copy.deepcopy(manifest)
        invalid['segments'][1]['offset'] += 1
        with self.assertRaisesRegex(RuntimeError, 'gap'):
            validate_manifest(invalid)
        invalid = copy.deepcopy(manifest)
        invalid['complete'] = False
        with self.assertRaisesRegex(RuntimeError, 'incomplete'):
            validate_manifest(invalid)
        invalid = copy.deepcopy(manifest)
        invalid['segments'][0]['source']['path'] = 'large-files/../secrets'
        with self.assertRaisesRegex(RuntimeError, 'Git chunk path'):
            validate_manifest(invalid)

    def test_release_join_order_must_match_exact_contiguous_parts(self):
        manifest, _ = fixture()
        manifest['release']['spec']['join_order'].reverse()
        with self.assertRaisesRegex(RuntimeError, 'join order'):
            validate_manifest(manifest)

    def test_authentication_removed_only_on_cross_host_https_redirect(self):
        request = urllib.request.Request('https://api.github.com/asset', headers={'Authorization': 'Bearer fixture', 'Cookie': 'secret'})
        handler = SafeRedirect()
        redirected = handler.redirect_request(request, None, 302, 'Found', {}, 'https://release-assets.githubusercontent.com/file')
        self.assertIsNone(redirected.get_header('Authorization'))
        self.assertIsNone(redirected.get_header('Cookie'))
        same_host = handler.redirect_request(request, None, 302, 'Found', {}, 'https://api.github.com/another-asset')
        self.assertEqual(same_host.get_header('Authorization'), 'Bearer fixture')
        with self.assertRaisesRegex(RuntimeError, 'non-HTTPS'):
            handler.redirect_request(request, None, 302, 'Found', {}, 'http://storage.example/file')

    def test_release_digest_is_required_in_addition_to_uploaded_size(self):
        asset = {'state': 'uploaded', 'size': 20, 'digest': 'sha256:' + 'a' * 64}
        self.assertTrue(matches_asset(asset, 20, 'a' * 64))
        self.assertFalse(matches_asset(asset, 20, 'b' * 64))
        self.assertFalse(matches_asset(asset | {'state': 'starter'}, 20, 'a' * 64))

    def test_publisher_stops_before_upload_when_source_tag_changed(self):
        manifest, _ = fixture()
        class Client:
            def json(self, route):
                if route == '/releases/1':
                    return {'id': 1, 'tag_name': 'v0'}
                if route == '/git/ref/tags/v0':
                    return {'object': {'type': 'commit', 'sha': 'b' * 40}}
                raise AssertionError('Unexpected request: ' + route)
        with self.assertRaisesRegex(RuntimeError, 'frozen engineering source'):
            publish(manifest, 'c' * 40, Path('never-read.zip'), Client(), Path('never-read.py'))

    def test_api_honors_full_retry_after_without_long_single_sleeps(self):
        client = GitHub('fixture/repo', 'fixture-token')
        error = urllib.error.HTTPError('https://api.github.com/fixture', 429, 'Rate limit', {'Retry-After': '95'}, io.BytesIO(b'limited'))
        with patch.object(client.opener, 'open', side_effect=[error, io.BytesIO(b'{"ok":true}')]), patch('assemble_large_files.time.sleep') as sleep:
            self.assertEqual(client.json('/fixture'), {'ok': True})
            self.assertEqual([call.args[0] for call in sleep.call_args_list], [30.0, 30.0, 30.0, 5.0])

    def test_api_honors_primary_reset_and_body_only_secondary_limit(self):
        client = GitHub('fixture/repo', 'fixture-token')
        errors = [
            urllib.error.HTTPError('https://api.github.com/fixture', 403, 'Rate limit', {'X-RateLimit-Remaining': '0', 'X-RateLimit-Reset': '1120'}, io.BytesIO(b'primary limit')),
            urllib.error.HTTPError('https://api.github.com/fixture', 403, 'Rate limit', {}, io.BytesIO(b'{"message":"You have exceeded a secondary rate limit."}')),
        ]
        with patch.object(client.opener, 'open', side_effect=errors + [io.BytesIO(b'{"ok":true}')]), patch('assemble_large_files.time.time', return_value=1000), patch('assemble_large_files.time.sleep') as sleep:
            self.assertEqual(client.json('/fixture'), {'ok': True})
            self.assertEqual([call.args[0] for call in sleep.call_args_list], [30.0] * 6)


if __name__ == '__main__':
    unittest.main()
