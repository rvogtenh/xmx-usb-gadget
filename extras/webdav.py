#!/usr/bin/env python3
"""Minimal WebDAV server for the Percussa XMX (Python 3.9 stdlib only, no xml module).

Serves a directory (default /media/BOOT) so macOS Finder can mount it:
Finder > Go > Connect to Server > http://10.77.0.1:8080/

Supports what the macOS WebDAV client (webdavfs) needs: OPTIONS, PROPFIND (depth 0/1),
GET/HEAD, PUT (incl. chunked), DELETE, MKCOL, MOVE, COPY, PROPPATCH (accepted, ignored),
LOCK/UNLOCK (fake exclusive write locks, so Finder mounts read-write).

macOS metadata files (._*, .DS_Store, .Spotlight-V100, .Trashes, .fseventsd) are
accepted and silently discarded, so they never land on the FAT card. That matters:
TraxHost loads every *.so in plugins/, and a stray ._attn.so would be loaded too.

Bind to the USB link only (10.77.0.1): no authentication, only the computer at the
other end of the cable can reach it. Runs at nice 19 from gadget.sh.

Usage: webdav.py [--root DIR] [--bind ADDR] [--port N] [--readonly]
"""
import argparse
import email.utils
import html
import mimetypes
import os
import shutil
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote, unquote, urlparse

JUNK_PREFIX = ("._",)
JUNK_NAMES = {".DS_Store", ".Spotlight-V100", ".Trashes", ".fseventsd", ".TemporaryItems",
              ".metadata_never_index", ".metadata_never_index_unless_rootfs",
              ".metadata_direct_scope_only", ".hidden", ".localized"}
LOCKS = {}  # path -> token (fake locks, enough for Finder)
LOCKS_MX = threading.Lock()


def is_junk(name):
    return name in JUNK_NAMES or name.startswith(JUNK_PREFIX)


def httpdate(ts):
    return email.utils.formatdate(ts, usegmt=True)


class DAV(BaseHTTPRequestHandler):
    server_version = "XMX-WebDAV/1.0"
    protocol_version = "HTTP/1.1"

    # ---- helpers -------------------------------------------------------
    def log_message(self, fmt, *args):
        if self.server.verbose:
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def fs_path(self, url_path=None):
        p = unquote(urlparse(url_path if url_path is not None else self.path).path)
        parts = [x for x in p.split("/") if x not in ("", ".", "..")]
        return os.path.join(self.server.root, *parts), parts

    def send(self, code, body=b"", ctype="text/plain; charset=utf-8", headers=None):
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        if body or code not in (204, 304):
            self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body and self.command != "HEAD":
            self.wfile.write(body)

    def read_body(self):
        """Read request body (Content-Length or chunked). Returns bytes."""
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            out = bytearray()
            while True:
                line = self.rfile.readline().strip()
                size = int(line.split(b";")[0], 16) if line else 0
                if size == 0:
                    while self.rfile.readline().strip():  # trailers
                        pass
                    return bytes(out)
                out += self.rfile.read(size)
                self.rfile.readline()
        n = int(self.headers.get("Content-Length", 0) or 0)
        return self.rfile.read(n) if n else b""

    def copy_body_to(self, f):
        """Stream request body into file f (no full buffering for large uploads)."""
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            while True:
                line = self.rfile.readline().strip()
                size = int(line.split(b";")[0], 16) if line else 0
                if size == 0:
                    while self.rfile.readline().strip():
                        pass
                    return
                while size:
                    b = self.rfile.read(min(size, 65536))
                    if not b:
                        return
                    f.write(b)
                    size -= len(b)
                self.rfile.readline()
        else:
            n = int(self.headers.get("Content-Length", 0) or 0)
            while n:
                b = self.rfile.read(min(n, 65536))
                if not b:
                    return
                f.write(b)
                n -= len(b)

    def readonly(self):
        if self.server.readonly:
            self.read_body()
            self.send(403, b"read-only\n")
            return True
        return False

    # ---- PROPFIND ------------------------------------------------------
    def prop_entry(self, href, full):
        st = os.stat(full)
        isdir = os.path.isdir(full)
        name = html.escape(os.path.basename(full.rstrip("/")) or "XMX")
        rt = "<D:resourcetype><D:collection/></D:resourcetype>" if isdir else "<D:resourcetype/>"
        extra = "" if isdir else (
            "<D:getcontentlength>%d</D:getcontentlength>"
            "<D:getcontenttype>%s</D:getcontenttype>" % (
                st.st_size, html.escape(mimetypes.guess_type(full)[0] or "application/octet-stream")))
        return (
            "<D:response><D:href>%s</D:href><D:propstat><D:prop>"
            "<D:displayname>%s</D:displayname>%s%s"
            "<D:getlastmodified>%s</D:getlastmodified>"
            "<D:creationdate>%s</D:creationdate>"
            "<D:getetag>\"%x-%x\"</D:getetag>"
            "<D:supportedlock><D:lockentry><D:lockscope><D:exclusive/></D:lockscope>"
            "<D:locktype><D:write/></D:locktype></D:lockentry></D:supportedlock>"
            "</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>" % (
                html.escape(href), name, rt, extra, httpdate(st.st_mtime),
                time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(st.st_mtime)),
                int(st.st_mtime), st.st_size))

    def do_PROPFIND(self):
        self.read_body()
        full, parts = self.fs_path()
        if (parts and is_junk(parts[-1])) or not os.path.exists(full):
            return self.send(404, b"not found\n")
        depth = self.headers.get("Depth", "1")
        base = "/" + "/".join(quote(p) for p in parts)
        if os.path.isdir(full) and not base.endswith("/"):
            base += "/"
        out = ['<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">',
               self.prop_entry(base, full)]
        if depth != "0" and os.path.isdir(full):
            try:
                names = sorted(os.listdir(full))
            except OSError:
                names = []
            for n in names:
                if is_junk(n):
                    continue
                f = os.path.join(full, n)
                try:
                    href = base + quote(n) + ("/" if os.path.isdir(f) else "")
                    out.append(self.prop_entry(href, f))
                except OSError:
                    pass
        out.append("</D:multistatus>")
        self.send(207, "".join(out).encode("utf-8"), 'application/xml; charset="utf-8"')

    def do_PROPPATCH(self):
        self.read_body()
        full, parts = self.fs_path()
        href = html.escape("/" + "/".join(quote(p) for p in parts))
        body = ('<?xml version="1.0" encoding="utf-8"?><D:multistatus xmlns:D="DAV:">'
                '<D:response><D:href>%s</D:href><D:propstat><D:prop/>'
                '<D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>' % href)
        self.send(207, body.encode(), 'application/xml; charset="utf-8"')

    # ---- read ----------------------------------------------------------
    def do_OPTIONS(self):
        self.read_body()
        self.send(200, b"", headers={
            "DAV": "1, 2", "MS-Author-Via": "DAV",
            "Allow": "OPTIONS, PROPFIND, PROPPATCH, GET, HEAD, PUT, DELETE, MKCOL, MOVE, COPY, LOCK, UNLOCK"})

    def do_GET(self):
        full, parts = self.fs_path()
        if (parts and is_junk(parts[-1])) or not os.path.exists(full):
            return self.send(404, b"not found\n")
        if os.path.isdir(full):
            items = "".join('<li><a href="%s">%s</a></li>' % (quote(n) + ("/" if os.path.isdir(os.path.join(full, n)) else ""), html.escape(n))
                            for n in sorted(os.listdir(full)) if not is_junk(n))
            return self.send(200, ("<html><body><h1>XMX %s</h1><ul>%s</ul></body></html>" % (
                html.escape("/" + "/".join(parts)), items)).encode(), "text/html; charset=utf-8")
        st = os.stat(full)
        self.send_response(200)
        self.send_header("Content-Type", mimetypes.guess_type(full)[0] or "application/octet-stream")
        self.send_header("Content-Length", str(st.st_size))
        self.send_header("Last-Modified", httpdate(st.st_mtime))
        self.send_header("ETag", '"%x-%x"' % (int(st.st_mtime), st.st_size))
        self.end_headers()
        if self.command == "HEAD":
            return
        with open(full, "rb") as f:
            shutil.copyfileobj(f, self.wfile, 65536)

    do_HEAD = do_GET

    # ---- write ---------------------------------------------------------
    def do_PUT(self):
        if self.readonly():
            return
        full, parts = self.fs_path()
        if not parts:
            self.read_body()
            return self.send(403, b"forbidden\n")
        if is_junk(parts[-1]):
            self.read_body()  # discard macOS metadata
            return self.send(201, b"")
        if not os.path.isdir(os.path.dirname(full)):
            self.read_body()
            return self.send(409, b"parent missing\n")
        existed = os.path.exists(full)
        tmp = full + ".davtmp"
        with open(tmp, "wb") as f:
            self.copy_body_to(f)
        os.replace(tmp, full)
        self.send(204 if existed else 201, b"")

    def do_MKCOL(self):
        if self.readonly():
            return
        self.read_body()
        full, parts = self.fs_path()
        if parts and is_junk(parts[-1]):
            return self.send(201, b"")
        if os.path.exists(full):
            return self.send(405, b"exists\n")
        if not os.path.isdir(os.path.dirname(full)):
            return self.send(409, b"parent missing\n")
        os.mkdir(full)
        self.send(201, b"")

    def do_DELETE(self):
        if self.readonly():
            return
        self.read_body()
        full, parts = self.fs_path()
        if not parts:
            return self.send(403, b"forbidden\n")
        if is_junk(parts[-1]) and not os.path.exists(full):
            return self.send(204, b"")
        if not os.path.exists(full):
            return self.send(404, b"not found\n")
        shutil.rmtree(full) if os.path.isdir(full) else os.remove(full)
        self.send(204, b"")

    def _dest(self):
        d = self.headers.get("Destination", "")
        return self.fs_path(urlparse(d).path) if d else (None, None)

    def do_MOVE(self, copy=False):
        if self.readonly():
            return
        self.read_body()
        src, sparts = self.fs_path()
        dst, dparts = self._dest()
        if not dst or not sparts or not dparts:
            return self.send(400, b"bad destination\n")
        if is_junk(sparts[-1]) or is_junk(dparts[-1]):
            return self.send(201, b"")
        if not os.path.exists(src):
            return self.send(404, b"not found\n")
        overwrite = self.headers.get("Overwrite", "T").upper() != "F"
        existed = os.path.exists(dst)
        if existed and not overwrite:
            return self.send(412, b"exists\n")
        if existed:
            shutil.rmtree(dst) if os.path.isdir(dst) else os.remove(dst)
        if copy:
            shutil.copytree(src, dst) if os.path.isdir(src) else shutil.copy2(src, dst)
        else:
            shutil.move(src, dst)
        self.send(204 if existed else 201, b"")

    def do_COPY(self):
        self.do_MOVE(copy=True)

    def do_LOCK(self):
        self.read_body()
        full, parts = self.fs_path()
        token = "opaquelocktoken:" + str(uuid.uuid4())
        with LOCKS_MX:
            LOCKS[full] = token
        href = html.escape("/" + "/".join(quote(p) for p in parts))
        body = ('<?xml version="1.0" encoding="utf-8"?><D:prop xmlns:D="DAV:"><D:lockdiscovery>'
                '<D:activelock><D:locktype><D:write/></D:locktype><D:lockscope><D:exclusive/></D:lockscope>'
                '<D:depth>0</D:depth><D:timeout>Second-3600</D:timeout>'
                '<D:locktoken><D:href>%s</D:href></D:locktoken><D:lockroot><D:href>%s</D:href></D:lockroot>'
                '</D:activelock></D:lockdiscovery></D:prop>' % (token, href))
        self.send(200, body.encode(), 'application/xml; charset="utf-8"', {"Lock-Token": "<%s>" % token})

    def do_UNLOCK(self):
        self.read_body()
        full, _ = self.fs_path()
        with LOCKS_MX:
            LOCKS.pop(full, None)
        self.send(204, b"")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="/media/BOOT")
    ap.add_argument("--bind", default="10.77.0.1")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--readonly", action="store_true")
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    srv = ThreadingHTTPServer((a.bind, a.port), DAV)
    srv.daemon_threads = True
    srv.root = os.path.abspath(a.root)
    srv.readonly = a.readonly
    srv.verbose = a.verbose
    print("XMX WebDAV on http://%s:%d/ root=%s%s" % (a.bind, a.port, srv.root, " (read-only)" if a.readonly else ""), flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
