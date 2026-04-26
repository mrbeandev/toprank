import unittest
import http.server
import threading
import socket
import urllib.request
import importlib.util
import sys
from pathlib import Path

# Fix for hyphen in directory name
script_path = Path(__file__).parent.parent.parent / 'seo' / 'broken-link-checker' / 'scripts' / 'checker.py'
spec = importlib.util.spec_from_file_location("checker", str(script_path))
checker = importlib.util.module_from_spec(spec)
sys.modules["checker"] = checker
spec.loader.exec_module(checker)

check_url = checker.check_url
LinkParser = checker.LinkParser
crawl = checker.crawl

class TestBrokenLinkChecker(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Find a free port
        cls.port = 8001
        cls.server_address = ('127.0.0.1', cls.port)
        cls.base_url = f"http://127.0.0.1:{cls.port}"
        
        class MockHandler(http.server.SimpleHTTPRequestHandler):
            def do_GET(self):
                if self.path == '/':
                    self.send_response(200)
                    self.send_header("Content-type", "text/html")
                    self.end_headers()
                    self.wfile.write(b"<html><body><a href='/valid'>Valid</a><a href='/broken'>Broken</a><a href='http://google.com'>External</a></body></html>")
                elif self.path == '/valid':
                    self.send_response(200)
                    self.send_header("Content-type", "text/html")
                    self.end_headers()
                    self.wfile.write(b"Valid page")
                elif self.path == '/broken':
                    self.send_response(404)
                    self.end_headers()
                else:
                    super().do_GET()
            
            def do_HEAD(self):
                if self.path == '/valid':
                    self.send_response(200)
                    self.end_headers()
                elif self.path == '/broken':
                    self.send_response(404)
                    self.end_headers()
                else:
                    self.send_response(200)
                    self.end_headers()

            def log_message(self, format, *args):
                pass

        cls.httpd = http.server.HTTPServer(cls.server_address, MockHandler)
        cls.server_thread = threading.Thread(target=cls.httpd.serve_forever)
        cls.server_thread.daemon = True
        cls.server_thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.server_thread.join()

    def test_check_url_valid(self):
        status, reason = check_url(f"{self.base_url}/valid")
        self.assertEqual(status, 200)
        self.assertIsNone(reason)

    def test_check_url_broken(self):
        status, reason = check_url(f"{self.base_url}/broken")
        self.assertEqual(status, 404)

    def test_link_parser(self):
        parser = LinkParser(self.base_url)
        html = "<html><body><a href='/test'>Test</a><a href='https://external.com'>Ext</a></body></html>"
        parser.feed(html)
        self.assertIn(f"{self.base_url}/test", parser.links)
        self.assertIn("https://external.com", parser.links)

    def test_crawl_integration(self):
        # Test the crawl function logic
        broken = crawl(self.base_url, max_pages=2)
        # It should find the broken link /broken
        targets = [b.get('target') for b in broken if 'target' in b]
        self.assertIn(f"{self.base_url}/broken", targets)

if __name__ == '__main__':
    unittest.main()
