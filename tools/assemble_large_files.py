#!/usr/bin/env python3
"""Verify small Git chunks and reused Release volumes, then publish the frozen ZIP.

Run in GitHub Actions with an immutable resource commit. Only one ZIP is written;
Release volumes are uploaded from bounded ranges, without local volume copies.
"""
from __future__ import annotations

import argparse
from email.utils import parsedate_to_datetime
import hashlib
import http.client
import json
import os
from pathlib import Path, PurePosixPath
import re
import time
import urllib.error
import urllib.parse
import urllib.request

REPOSITORY = 'hbzheng0942/greybox-to-multistyle-art-showcases'
SOURCE_COMMIT = '799c478fe45278cd5db3f3c3a1eb2ec83709583f'
ARCHIVE_SHA256 = '9e7e8608f3e109215712d62d654b34171f08e35157c537e76502ac71f44bef1d'
ARCHIVE_BYTES = 4895618862
BLOCK = 1024 * 1024
HEX40 = re.compile(r'^[0-9a-f]{40}$')
HEX64 = re.compile(r'^[0-9a-f]{64}$')


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    """Never forward a GitHub API bearer token to a storage/CDN host."""
    def redirect_request(self, request, fp, code, message, headers, new_url):
        old = urllib.parse.urlsplit(request.full_url)
        new = urllib.parse.urlsplit(new_url)
        if new.scheme != 'https':
            raise RuntimeError('Refusing a non-HTTPS download redirect')
        redirected = super().redirect_request(request, fp, code, message, headers, new_url)
        if redirected is not None and (old.hostname, old.port) != (new.hostname, new.port):
            for header in ('Authorization', 'Cookie', 'Proxy-authorization'):
                redirected.remove_header(header)
        return redirected


def retry_delay(error, attempt, body):
    """Respect server rate-limit windows; never print an API response body."""
    headers = error.headers or {}
    secondary = error.code == 403 and any(text in body.lower() for text in (b'secondary rate limit', b'abuse detection'))
    primary = error.code == 403 and headers.get('X-RateLimit-Remaining') == '0'
    if error.code not in (429, 500, 502, 503, 504) and not (error.code == 403 and (headers.get('Retry-After') or primary or secondary)):
        return None
    delay = max(float(2 ** attempt), 60.0 if secondary else 0.0)
    retry_after = headers.get('Retry-After')
    if retry_after:
        try:
            delay = max(delay, float(retry_after))
        except ValueError:
            try:
                delay = max(delay, parsedate_to_datetime(retry_after).timestamp() - time.time())
            except (TypeError, ValueError, OverflowError):
                pass
    if primary and headers.get('X-RateLimit-Reset'):
        try:
            delay = max(delay, float(headers['X-RateLimit-Reset']) - time.time())
        except ValueError:
            pass
    return delay


def wait_for_retry(delay):
    # Keep each wait bounded while honoring a longer server-provided deadline.
    while delay > 0:
        interval = min(30.0, delay)
        time.sleep(interval)
        delay -= interval


def checked_name(name):
    if not isinstance(name, str) or not name or Path(name).name != name or '\\' in name or name in ('.', '..'):
        raise RuntimeError('Invalid release filename')
    return name


def validate_sequence(records, total, description):
    offset = 0
    for record in records:
        length = record.get('bytes')
        if type(length) is not int or length <= 0 or record.get('offset') != offset:
            raise RuntimeError(f'{description} contains a gap, overlap, or invalid size')
        if not HEX64.fullmatch(record.get('sha256', '')):
            raise RuntimeError(f'{description} contains an invalid SHA256')
        offset += length
    if offset != total:
        raise RuntimeError(f'{description} does not cover the complete archive')


def validate_manifest(manifest):
    if manifest.get('schema') != 1 or manifest.get('complete') is not True:
        raise RuntimeError('Resource manifest is incomplete or unsupported')
    archive = manifest['archive']
    checked_name(archive['name'])
    if type(archive['bytes']) is not int or archive['bytes'] <= 0 or not HEX64.fullmatch(archive.get('sha256', '')):
        raise RuntimeError('Invalid archive declaration')
    if not HEX40.fullmatch(archive.get('source_commit', '')):
        raise RuntimeError('Invalid frozen source commit')
    validate_sequence(manifest['segments'], archive['bytes'], 'Resource segments')
    paths = set()
    for segment in manifest['segments']:
        source = segment['source']
        if source.get('type') == 'git':
            path = source['path']
            parsed = PurePosixPath(path)
            if parsed.is_absolute() or '..' in parsed.parts or '\\' in path or not path.startswith('large-files/'):
                raise RuntimeError('Invalid Git chunk path')
            if path in paths or not HEX40.fullmatch(source.get('blob_sha', '')):
                raise RuntimeError('Duplicate Git path or invalid blob SHA1')
            paths.add(path)
        elif source.get('type') == 'release':
            if type(source.get('asset_id')) is not int or source['asset_id'] <= 0:
                raise RuntimeError('Invalid source Release asset')
            checked_name(source['name'])
        else:
            raise RuntimeError('Unknown resource source')
    release = manifest['release']
    if type(release.get('id')) is not int or release['id'] <= 0:
        raise RuntimeError('Invalid Release ID')
    if not isinstance(release.get('tag'), str) or not release['tag']:
        raise RuntimeError('Invalid Release tag')
    spec = release['spec']
    if spec.get('schema') != 1 or spec.get('tag') != release['tag']:
        raise RuntimeError('Release specification differs from resource manifest')
    if spec['archive'] != {key: archive[key] for key in ('name', 'bytes', 'sha256')}:
        raise RuntimeError('Release archive differs from resource manifest')
    validate_sequence(spec['parts'], archive['bytes'], 'Release volumes')
    names = [checked_name(part['name']) for part in spec['parts']]
    if len(set(names)) != len(names) or spec.get('join_order') != names:
        raise RuntimeError('Invalid Release join order')
    return manifest


def range_digest(stream, offset, length):
    stream.seek(offset)
    digest = hashlib.sha256()
    remaining = length
    while remaining:
        data = stream.read(min(BLOCK, remaining))
        if not data:
            return None
        digest.update(data)
        remaining -= len(data)
    return digest.hexdigest()


def matches_asset(asset, length, digest):
    return (asset.get('state') == 'uploaded' and asset.get('size') == length
            and asset.get('digest') == 'sha256:' + digest)


class GitHub:
    def __init__(self, repository, token):
        if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
            raise RuntimeError('Invalid repository')
        self.repository = repository
        self.token = token
        self.base = f'https://api.github.com/repos/{repository}'
        self.opener = urllib.request.build_opener(SafeRedirect())

    def headers(self, accept='application/vnd.github+json', authenticated=True):
        result = {'User-Agent': 'showcase-chunk-assembler', 'Accept': accept,
                  'X-GitHub-Api-Version': '2022-11-28'}
        if authenticated and self.token:
            result['Authorization'] = 'Bearer ' + self.token
        return result

    def json(self, route, method='GET', payload=None):
        body = None if payload is None else json.dumps(payload).encode()
        headers = self.headers()
        if body is not None:
            headers['Content-Type'] = 'application/json'
        for attempt in range(5):
            request = urllib.request.Request(self.base + route, data=body, headers=headers, method=method)
            try:
                with self.opener.open(request, timeout=90) as response:
                    data = response.read()
                    return json.loads(data) if data else None
            except urllib.error.HTTPError as error:
                try:
                    body = error.read(65536)
                finally:
                    error.close()
                delay = retry_delay(error, attempt, body)
                if attempt == 4 or delay is None:
                    raise RuntimeError(f'GitHub API {method} {route}: HTTP {error.code}') from None
                wait_for_retry(delay)
            except (OSError, TimeoutError):
                if attempt == 4:
                    raise
                time.sleep(min(2 ** attempt, 30))

    def assets(self, release_id):
        result = []
        for page in range(1, 20):
            batch = self.json(f'/releases/{release_id}/assets?per_page=100&page={page}')
            result.extend(batch)
            if len(batch) < 100:
                return result
        raise RuntimeError('Unexpectedly large Release asset list')

    def raw(self, commit, path):
        url = f'https://raw.githubusercontent.com/{self.repository}/{commit}/' + urllib.parse.quote(path, safe='/')
        return self.opener.open(urllib.request.Request(url, headers=self.headers('application/octet-stream', False)), timeout=180)

    def segment(self, commit, record):
        source = record['source']
        if source['type'] == 'git':
            return self.raw(commit, source['path'])
        asset = self.json(f"/releases/assets/{source['asset_id']}")
        if asset.get('name') != source['name'] or not matches_asset(asset, record['bytes'], record['sha256']):
            raise RuntimeError('Reused Release asset does not match its manifest')
        url = self.base + f"/releases/assets/{source['asset_id']}"
        request = urllib.request.Request(url, headers=self.headers('application/octet-stream'))
        return self.opener.open(request, timeout=180)

    def upload_range(self, upload_url, name, digest, source, offset, length):
        parsed = urllib.parse.urlsplit(upload_url.split('{', 1)[0])
        if parsed.scheme != 'https' or parsed.hostname != 'uploads.github.com':
            raise RuntimeError('Unexpected GitHub upload endpoint')
        query = urllib.parse.urlencode({'name': name, 'label': 'sha256:' + digest})
        path = parsed.path + '?' + query
        connection = http.client.HTTPSConnection(parsed.hostname, timeout=300)
        headers = self.headers()
        headers.update({'Content-Type': 'application/octet-stream', 'Content-Length': str(length)})
        try:
            connection.putrequest('POST', path)
            for key, value in headers.items():
                connection.putheader(key, value)
            connection.endheaders()
            source.seek(offset)
            remaining = length
            while remaining:
                block = source.read(min(BLOCK, remaining))
                if not block:
                    raise RuntimeError('Archive range ended unexpectedly')
                connection.send(block)
                remaining -= len(block)
            response = connection.getresponse()
            body = response.read()
            if response.status != 201:
                raise RuntimeError(f'Release upload failed: HTTP {response.status}')
            return json.loads(body)
        finally:
            connection.close()

    def ensure_asset(self, release, name, source, offset, length, digest):
        """Reuse an exact uploaded object; only remove our own failed starter."""
        for attempt in range(5):
            existing = [item for item in self.assets(release['id']) if item['name'] == name]
            if len(existing) > 1:
                raise RuntimeError(f'Duplicate Release assets: {name}')
            if existing:
                item = existing[0]
                if matches_asset(item, length, digest):
                    return item
                if item.get('state') == 'starter' and item.get('label') == 'sha256:' + digest:
                    self.json(f"/releases/assets/{item['id']}", 'DELETE')
                else:
                    raise RuntimeError(f'Existing Release asset differs: {name}')
            try:
                result = self.upload_range(release['upload_url'], name, digest, source, offset, length)
                if not matches_asset(result, length, digest):
                    raise RuntimeError(f'GitHub server digest mismatch: {name}')
                return result
            except (OSError, TimeoutError, http.client.HTTPException, RuntimeError):
                # The server may have accepted an upload whose response was lost.
                if attempt == 4:
                    matching = [item for item in self.assets(release['id'])
                                if item['name'] == name and matches_asset(item, length, digest)]
                    if len(matching) == 1:
                        return matching[0]
                    raise
                time.sleep(min(2 ** attempt, 30))
        raise RuntimeError('Unreachable upload state')


def assemble(manifest, commit, directory, client):
    validate_manifest(manifest)
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / manifest['archive']['name']
    expected = manifest['archive']
    if archive.exists():
        with archive.open('rb') as stream:
            if archive.stat().st_size == expected['bytes'] and range_digest(stream, 0, expected['bytes']) == expected['sha256']:
                return archive
        raise RuntimeError('Existing complete archive differs; refusing to overwrite')
    partial = archive.with_name(archive.name + '.partial')
    partial.touch(exist_ok=True)
    with partial.open('r+b') as output:
        for index, record in enumerate(manifest['segments'], 1):
            offset, length = record['offset'], record['bytes']
            if partial.stat().st_size >= offset + length and range_digest(output, offset, length) == record['sha256']:
                continue
            output.truncate(offset)
            for attempt in range(5):
                output.seek(offset)
                output.truncate(offset)
                sha256 = hashlib.sha256()
                sha1 = hashlib.sha1(f'blob {length}\0'.encode())
                count = 0
                try:
                    with client.segment(commit, record) as source:
                        while block := source.read(BLOCK):
                            if count + len(block) > length:
                                raise RuntimeError('Resource exceeds its declared length')
                            output.write(block)
                            sha256.update(block)
                            sha1.update(block)
                            count += len(block)
                    if count != length or sha256.hexdigest() != record['sha256']:
                        raise RuntimeError('Resource SHA256 or length mismatch')
                    if record['source']['type'] == 'git' and sha1.hexdigest() != record['source']['blob_sha']:
                        raise RuntimeError('Git blob SHA1 mismatch')
                    output.flush()
                    print(f'Verified segment {index}/{len(manifest["segments"])}', flush=True)
                    break
                except (OSError, TimeoutError, http.client.HTTPException, RuntimeError):
                    output.truncate(offset)
                    output.flush()
                    if attempt == 4:
                        raise
                    time.sleep(min(2 ** attempt, 30))
        output.truncate(expected['bytes'])
        output.flush()
        if range_digest(output, 0, expected['bytes']) != expected['sha256']:
            raise RuntimeError('Complete archive SHA256 mismatch')
    partial.rename(archive)
    return archive


def tag_commit(client, tag):
    reference = client.json('/git/ref/tags/' + urllib.parse.quote(tag, safe=''))
    obj = reference['object']
    for _ in range(5):
        if obj['type'] == 'commit':
            return obj['sha']
        if obj['type'] != 'tag':
            break
        obj = client.json('/git/tags/' + obj['sha'])['object']
    raise RuntimeError('Release tag does not resolve to a commit')


def publish(manifest, commit, archive, client, extractor):
    release_spec = manifest['release']
    release = client.json(f"/releases/{release_spec['id']}")
    if release['tag_name'] != release_spec['tag'] or tag_commit(client, release_spec['tag']) != manifest['archive']['source_commit']:
        raise RuntimeError('Release tag differs from the frozen engineering source')
    verified = []
    with archive.open('rb') as stream:
        for part in release_spec['spec']['parts']:
            if range_digest(stream, part['offset'], part['bytes']) != part['sha256']:
                raise RuntimeError('Assembled archive differs from the Release volume specification')
            asset = client.ensure_asset(release, part['name'], stream, part['offset'], part['bytes'], part['sha256'])
            verified.append({'name': asset['name'], 'bytes': asset['size'], 'digest': asset['digest'], 'id': asset['id']})
            print(f'Verified Release volume: {part["name"]}', flush=True)
    # Small portable metadata and extractor are the only additional local files.
    metadata = archive.parent / 'release-files.json'
    metadata.write_text(json.dumps(release_spec['spec'], indent=2) + '\n')
    for path in (metadata, extractor):
        with path.open('rb') as source:
            length = path.stat().st_size
            digest = range_digest(source, 0, length)
            client.ensure_asset(release, path.name, source, 0, length, digest)
    final = {item['name']: item for item in client.assets(release['id'])}
    for part in release_spec['spec']['parts']:
        if not matches_asset(final.get(part['name'], {}), part['bytes'], part['sha256']):
            raise RuntimeError('Final Release asset verification failed')
    # Explicit fields prevent a draft target update from losing its named tag.
    published = client.json(f"/releases/{release['id']}", 'PATCH', {
        'tag_name': release_spec['tag'], 'target_commitish': manifest['archive']['source_commit'],
        'draft': False, 'prerelease': False,
    })
    if published.get('draft') or published['tag_name'] != release_spec['tag']:
        raise RuntimeError('Release publication did not complete')
    return {'schema': 1, 'resources_commit': commit, 'source_commit': manifest['archive']['source_commit'],
            'archive': manifest['archive'], 'release_url': published['html_url'], 'assets': verified}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resources-commit', required=True, help='Immutable full SHA of the complete resource manifest')
    parser.add_argument('--repository', default=os.environ.get('GITHUB_REPOSITORY', REPOSITORY))
    parser.add_argument('--output', type=Path, default=Path(os.environ.get('RUNNER_TEMP', '.')) / 'showcase-release')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--publish', action='store_true', help='Publish only after every source and Release digest passes')
    mode.add_argument('--assemble-only', action='store_true', help='Only reconstruct and verify the complete ZIP (default)')
    args = parser.parse_args()
    if not HEX40.fullmatch(args.resources_commit):
        parser.error('--resources-commit requires a full lowercase 40-character SHA')
    client = GitHub(args.repository, os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN'))
    with client.raw(args.resources_commit, 'large-files/manifest.json') as response:
        manifest = json.load(response)
    validate_manifest(manifest)
    if (args.repository != REPOSITORY or manifest['archive']['source_commit'] != SOURCE_COMMIT
            or manifest['archive']['sha256'] != ARCHIVE_SHA256 or manifest['archive']['bytes'] != ARCHIVE_BYTES):
        raise RuntimeError('Resource manifest is not the approved frozen showcase package')
    archive = assemble(manifest, args.resources_commit, args.output, client)
    print('Complete ZIP SHA256 verified: ' + str(archive), flush=True)
    if args.publish:
        if not client.token:
            raise RuntimeError('Release publication requires GH_TOKEN or GITHUB_TOKEN')
        receipt = publish(manifest, args.resources_commit, archive, client, Path(__file__).with_name('extract_showcase.py'))
        receipt_path = args.output / 'publication-receipt.json'
        receipt_path.write_text(json.dumps(receipt, indent=2) + '\n')
        print(receipt['release_url'], flush=True)
        if summary := os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(summary, 'a') as output:
                output.write(f"Verified and published [{manifest['release']['tag']}]({receipt['release_url']}).\n\n")
                output.write(f"Archive SHA256: `{manifest['archive']['sha256']}`\n")


if __name__ == '__main__':
    main()
